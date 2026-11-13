import Foundation

/// Keeps several Macs in step through a shared folder (iCloud Drive, or any
/// folder another tool keeps in sync).
///
/// Layout of the folder:
///
///     devices/<device id>/device.json          name of the Mac
///     devices/<device id>/events/<day>.jsonl   one record per line
///     tagging.json                             tags and rules
///
/// Each Mac writes only inside its own `devices/<id>` folder and only reads
/// the others, so two Macs never edit the same record file. Tags and rules
/// are shared: the most recently edited set wins.
public final class SyncEngine {
    public struct Result: Sendable {
        public var exportedDays = 0
        public var importedDays = 0
        /// Files that the cloud has not downloaded yet; they are picked up later.
        public var pendingFiles = 0
        public var appliedTagging = false
    }

    struct DeviceInfo: Codable {
        var id: String
        var name: String
        var updated: Date
    }

    /// One line of a day file.
    struct Record: Codable {
        var start: Date
        var end: Date
        var bundleID: String
        var appName: String
        var category: String?
        var title: String
        var path: String?
        var url: String?
    }

    private let store: EventStore
    private let folder: URL
    private let deviceID: String
    private let deviceName: String
    private let calendar: Calendar
    private let fm = FileManager.default

    public init(store: EventStore, folder: URL, deviceID: String, deviceName: String, calendar: Calendar = .current) {
        self.store = store
        self.folder = folder
        self.deviceID = deviceID
        self.deviceName = deviceName
        self.calendar = calendar
    }

    public static func dayKey(_ date: Date, calendar: Calendar = .current) -> String {
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
    }

    private static func encoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .secondsSince1970
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return encoder
    }

    private static func decoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
        return decoder
    }

    private var devicesFolder: URL { folder.appendingPathComponent("devices", isDirectory: true) }
    private var ownFolder: URL { devicesFolder.appendingPathComponent(deviceID, isDirectory: true) }

    /// Writes this Mac's records, reads the other Macs', and reconciles tags
    /// and rules.
    public func sync(now: Date = Date()) throws -> Result {
        var result = Result()
        try fm.createDirectory(at: devicesFolder, withIntermediateDirectories: true)
        result.exportedDays = try exportOwn(now: now)
        try importOthers(into: &result)
        result.appliedTagging = try syncTagging()
        return result
    }

    // MARK: Export

    private func exportOwn(now: Date) throws -> Int {
        let events = ownFolder.appendingPathComponent("events", isDirectory: true)
        let isFirst = !fm.fileExists(atPath: events.path)
        try fm.createDirectory(at: events, withIntermediateDirectories: true)

        let today = calendar.startOfDay(for: now)
        var days: Set<Date> = [today]
        if let yesterday = calendar.date(byAdding: .day, value: -1, to: today) { days.insert(yesterday) }
        let full = try isFirst || store.meta("fullExport") == "1"
        if full {
            // Everything this Mac has, and nothing else: stale files go.
            for file in (try? fm.contentsOfDirectory(at: events, includingPropertiesForKeys: nil)) ?? [] {
                try? fm.removeItem(at: file)
            }
            if var day = try store.firstLocalStart().map({ calendar.startOfDay(for: $0) }) {
                while day <= today {
                    days.insert(day)
                    day = calendar.date(byAdding: .day, value: 1, to: day) ?? day.addingTimeInterval(86_400)
                }
            }
        }
        for key in (try store.meta("dirtyDays") ?? "").split(separator: ",") {
            let parts = key.split(separator: "-").compactMap { Int($0) }
            if parts.count == 3,
               let day = calendar.date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2])) {
                days.insert(day)
            }
        }

        let encoder = Self.encoder()
        var written = 0
        for day in days {
            let next = calendar.date(byAdding: .day, value: 1, to: day) ?? day.addingTimeInterval(86_400)
            let file = events.appendingPathComponent(Self.dayKey(day, calendar: calendar) + ".jsonl")
            let records = try store.localEvents(startingFrom: day, to: next).map {
                Record(start: $0.start, end: $0.end, bundleID: $0.bundleID, appName: $0.appName,
                       category: $0.category, title: $0.title, path: $0.path, url: $0.url)
            }
            if records.isEmpty {
                try? fm.removeItem(at: file)
                continue
            }
            var data = Data()
            for record in records {
                data.append(try encoder.encode(record))
                data.append(0x0A)
            }
            // Leave an unchanged file alone so that it is not uploaded again.
            if (try? Data(contentsOf: file)) != data {
                try data.write(to: file, options: .atomic)
                written += 1
            }
        }
        try store.setMeta("dirtyDays", nil)
        try store.setMeta("fullExport", nil)

        let info = DeviceInfo(id: deviceID, name: deviceName, updated: now)
        try Self.encoder().encode(info).write(to: ownFolder.appendingPathComponent("device.json"), options: .atomic)
        return written
    }

    // MARK: Import

    private func importOthers(into result: inout Result) throws {
        let decoder = Self.decoder()
        let folders = (try? fm.contentsOfDirectory(at: devicesFolder, includingPropertiesForKeys: [.isDirectoryKey])) ?? []
        for dir in folders where dir.lastPathComponent != deviceID {
            guard (try? dir.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true else { continue }
            let id = dir.lastPathComponent
            var device = SyncedDevice(id: id, name: id)
            if let data = try? Data(contentsOf: dir.appendingPathComponent("device.json")),
               let info = try? decoder.decode(DeviceInfo.self, from: data) {
                device.name = info.name
                device.lastSeen = info.updated
            }
            try store.saveDevice(device)

            let events = dir.appendingPathComponent("events", isDirectory: true)
            let files = (try? fm.contentsOfDirectory(at: events, includingPropertiesForKeys: [.fileSizeKey, .contentModificationDateKey])) ?? []
            var known = try store.syncStamps(device: id)
            var pending: Set<String> = []
            for file in files {
                let name = file.lastPathComponent
                // iCloud shows a file it has not downloaded as ".<name>.icloud".
                if name.hasPrefix("."), name.hasSuffix(".jsonl.icloud") {
                    pending.insert(String(name.dropFirst().dropLast(".jsonl.icloud".count)))
                    try? fm.startDownloadingUbiquitousItem(at: file)
                    continue
                }
                guard file.pathExtension == "jsonl" else { continue }
                let day = file.deletingPathExtension().lastPathComponent
                let values = try? file.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey])
                let stamp = "\(values?.fileSize ?? 0)-\(values?.contentModificationDate?.timeIntervalSince1970 ?? 0)"
                defer { known[day] = nil }
                if known[day] == stamp { continue }
                guard let data = try? Data(contentsOf: file) else { continue }
                let records = data.split(separator: 0x0A).compactMap { try? decoder.decode(Record.self, from: Data($0)) }
                let imported = records.filter { $0.end >= $0.start }.map { record in
                    ActivityEvent(sample: Sample(bundleID: record.bundleID, appName: record.appName,
                                                 category: record.category, title: record.title,
                                                 path: record.path, url: record.url),
                                  start: record.start, end: record.end)
                }
                try store.replaceRemote(device: id, day: day, stamp: stamp, with: imported)
                result.importedDays += 1
            }
            result.pendingFiles += pending.count
            // Days whose file has disappeared were deleted on that Mac.
            for day in known.keys where !pending.contains(day) {
                try store.replaceRemote(device: id, day: day, stamp: nil, with: nil)
            }
        }
    }

    // MARK: Tags and rules

    /// The newer of the local and the shared tagging wins. A Mac that has
    /// never edited its tags adopts the shared set without publishing its own.
    private func syncTagging() throws -> Bool {
        let file = folder.appendingPathComponent("tagging.json")
        let remote = (try? Data(contentsOf: file)).flatMap { try? Self.decoder().decode(TaggingSnapshot.self, from: $0) }
        let local = try store.taggingSnapshot()
        switch (local, remote) {
        case let (local?, remote?) where remote.updated > local.updated.addingTimeInterval(0.5):
            _ = local
            try store.applyTagging(remote)
            return true
        case let (nil, remote?):
            try store.applyTagging(remote)
            return true
        case let (local?, remote):
            if remote == nil || local.updated > remote!.updated.addingTimeInterval(0.5) {
                let encoder = Self.encoder()
                encoder.outputFormatting.insert(.prettyPrinted)
                try encoder.encode(local).write(to: file, options: .atomic)
            }
            return false
        case (nil, nil):
            return false
        }
    }
}
