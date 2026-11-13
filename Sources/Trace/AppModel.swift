import AppKit
import Combine
import ServiceManagement
import SwiftUI
import TraceCore
import UniformTypeIdentifiers

enum Appearance: String, CaseIterable, Identifiable {
    case light, dark, system
    var id: String { rawValue }
}

enum Pane: String, CaseIterable, Identifiable {
    case overview, timeline, reports, tags, rules
    var id: String { rawValue }
}

enum TimelineMode: String, CaseIterable, Identifiable {
    case byTag, byApp, records
    var id: String { rawValue }
}

enum ReportPeriod: String, CaseIterable, Identifiable {
    case week, month, year
    var id: String { rawValue }
    var component: Calendar.Component {
        switch self {
        case .week: return .weekOfYear
        case .month: return .month
        case .year: return .year
        }
    }
}

/// App-wide state: settings, navigation, the selected day and everything
/// derived from it.
@MainActor
final class AppModel: ObservableObject {
    let store: EventStore
    let watcher: ActivityWatcher
    let databaseURL: URL?
    /// Started with `--demo`: made-up data in memory, nothing recorded.
    let isDemo: Bool

    // Navigation and selection, shared so one page can send you to another.
    @Published var pane: Pane = .overview
    @Published var timelineMode: TimelineMode = .byTag
    @Published var query = ""
    @Published var tagFilter: Int64?
    /// A stretch of the day picked in the timeline; the outline sums only this.
    @Published var selection: DateInterval?
    @Published var selectedBlock: Date?
    @Published var selectedEventID: Int64?
    @Published var reportPeriod: ReportPeriod = .week
    @Published var reportAnchor = Date()
    /// Prefills the new-rule form, e.g. from "Create rule" on untagged activity.
    @Published var ruleDraft: (field: RuleField, value: String)?
    @Published var showsOnboarding: Bool

    @Published var day = Calendar.current.startOfDay(for: Date()) {
        didSet { selection = nil; selectedBlock = nil; selectedEventID = nil; reload() }
    }
    @Published private(set) var events: [ActivityEvent] = []
    @Published private(set) var summary = DaySummary()
    @Published private(set) var blocks: [Block] = []
    @Published private(set) var appRuns: [AppRun] = []
    @Published private(set) var yesterdayTotal: TimeInterval = 0
    @Published private(set) var tags: [Tag] = []
    @Published private(set) var rules: [Rule] = []
    @Published private(set) var tagger = Tagger(tags: [], rules: [])
    /// Bumped whenever tags, rules or manual tags change.
    @Published private(set) var revision = 0

    @Published var appearance: Appearance {
        didSet { UserDefaults.standard.set(appearance.rawValue, forKey: "appearance"); applyAppearance() }
    }
    @Published var language: AppLanguage {
        didSet { UserDefaults.standard.set(language.rawValue, forKey: "language"); L10n.apply(language) }
    }
    @Published var idleMinutes: Int {
        didSet { UserDefaults.standard.set(idleMinutes, forKey: "idleMinutes"); watcher.idleThreshold = TimeInterval(idleMinutes * 60) }
    }
    @Published var captureTitles: Bool {
        didSet { UserDefaults.standard.set(captureTitles, forKey: "captureTitles"); watcher.captureTitles = captureTitles }
    }
    @Published var captureFiles: Bool {
        didSet { UserDefaults.standard.set(captureFiles, forKey: "captureFiles"); watcher.captureFiles = captureFiles }
    }
    @Published var captureURLs: Bool {
        didSet { UserDefaults.standard.set(captureURLs, forKey: "captureURLs"); watcher.captureURLs = captureURLs }
    }
    /// Bundle identifiers of apps that are never recorded.
    @Published var excludedApps: [String] {
        didSet { UserDefaults.standard.set(excludedApps, forKey: "excludedApps"); watcher.excluded = Set(excludedApps) }
    }
    @Published private(set) var launchAtLogin = SMAppService.mainApp.status == .enabled

    // Sync through a shared folder.
    private(set) var deviceID: String
    /// This Mac's name as other Macs see it; the system's name unless changed.
    @Published var deviceName: String {
        didSet {
            let trimmed = deviceName.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty {
                UserDefaults.standard.removeObject(forKey: "deviceName")
            } else {
                UserDefaults.standard.set(trimmed, forKey: "deviceName")
            }
        }
    }
    /// Today's time per Mac, whatever the device filter; keyed by device id.
    @Published private(set) var deviceTotals: [String: TimeInterval] = [:]
    @Published private(set) var syncFolder: String?
    @Published private(set) var lastSync: Date?
    @Published private(set) var syncError: String?
    @Published private(set) var isSyncing = false
    /// Other Macs whose records are in the database.
    @Published private(set) var devices: [SyncedDevice] = []
    /// Which Mac's records to show: nil for all, "" for this Mac, else a device id.
    @Published var deviceFilter: String? { didSet { reload() } }
    private var syncTimer: Timer?

    private var refresh: Timer?

    init() {
        let defaults = UserDefaults.standard
        defaults.register(defaults: ["captureTitles": true, "captureFiles": true, "captureURLs": true])
        appearance = Appearance(rawValue: defaults.string(forKey: "appearance") ?? "") ?? .system
        language = AppLanguage(rawValue: defaults.string(forKey: "language") ?? "") ?? .system
        let minutes = defaults.integer(forKey: "idleMinutes")
        idleMinutes = minutes > 0 ? minutes : 3
        captureTitles = defaults.bool(forKey: "captureTitles")
        captureFiles = defaults.bool(forKey: "captureFiles")
        captureURLs = defaults.bool(forKey: "captureURLs")
        excludedApps = defaults.stringArray(forKey: "excludedApps") ?? []
        if let id = defaults.string(forKey: "deviceID") {
            deviceID = id
        } else {
            deviceID = UUID().uuidString.lowercased()
            defaults.set(deviceID, forKey: "deviceID")
        }
        syncFolder = defaults.string(forKey: "syncFolder")
        deviceName = defaults.string(forKey: "deviceName") ?? Host.current().localizedName ?? "Mac"

        // Launch arguments, used for demos and screenshots; they are not saved.
        let args = CommandLine.arguments
        func value(after flag: String) -> String? {
            args.firstIndex(of: flag).flatMap { $0 + 1 < args.count ? args[$0 + 1] : nil }
        }
        let demo = args.contains("--demo")
        isDemo = demo
        if let override = value(after: "--language").flatMap(AppLanguage.init(rawValue:)) { language = override }
        if let override = value(after: "--appearance").flatMap(Appearance.init(rawValue:)) { appearance = override }
        showsOnboarding = !demo && !defaults.bool(forKey: "onboarded")
        // For trying sync without touching real data: a separate database
        // folder, sync folder and device identity for this run only.
        let dataDir = value(after: "--data-dir")
        if let override = value(after: "--sync-folder") { syncFolder = override }
        if let override = value(after: "--device-id") { deviceID = override }

        // Keep data in Application Support; fall back to memory if that fails
        // so the app still opens and can say what went wrong.
        var url: URL?
        var opened: EventStore?
        if !demo, let support = try? FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask,
                                                      appropriateFor: nil, create: true) {
            let folder = dataDir.map { URL(fileURLWithPath: $0, isDirectory: true) }
                ?? support.appendingPathComponent("Trace", isDirectory: true)
            try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            let file = folder.appendingPathComponent("trace.sqlite")
            if let store = try? EventStore(path: file.path) {
                opened = store
                url = file
            }
        }
        store = opened ?? (try! EventStore())
        databaseURL = url
        watcher = ActivityWatcher(store: store)
        watcher.idleThreshold = TimeInterval(idleMinutes * 60)
        watcher.captureTitles = captureTitles
        watcher.captureFiles = captureFiles
        watcher.captureURLs = captureURLs
        watcher.excluded = Set(excludedApps)

        L10n.apply(language)
        if demo {
            try? store.insert(DemoData.events())
            if let last = (try? store.events(from: Date().addingTimeInterval(-86_400), to: Date()))?.last {
                watcher.showDemo(Sample(bundleID: last.bundleID, appName: last.appName, title: last.title,
                                        path: last.path, url: last.url), since: last.start)
            }
        }
        devices = (try? store.devices()) ?? []
        reload()
        if !demo {
            watcher.start()
            let sync = Timer(timeInterval: 300, repeats: true) { [weak self] _ in
                Task { @MainActor in self?.syncNow() }
            }
            RunLoop.main.add(sync, forMode: .common)
            syncTimer = sync
            DispatchQueue.main.asyncAfter(deadline: .now() + 3) { [weak self] in self?.syncNow() }
        }

        let timer = Timer(timeInterval: 10, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.reloadIfToday() }
        }
        RunLoop.main.add(timer, forMode: .common)
        refresh = timer
        DispatchQueue.main.async { [weak self] in self?.applyAppearance() }
    }

    // MARK: Day

    var isToday: Bool { Calendar.current.isDateInToday(day) }
    var dayInterval: DateInterval {
        DateInterval(start: day, end: Calendar.current.date(byAdding: .day, value: 1, to: day) ?? day + 86_400)
    }
    /// The current calendar week.
    var weekInterval: DateInterval {
        Calendar.current.dateInterval(of: .weekOfYear, for: Date()) ?? DateInterval(start: Date(), duration: 7 * 86_400)
    }
    /// Time between the first and last record of the day that was not recorded.
    var away: TimeInterval {
        guard let first = summary.first, let last = summary.last else { return 0 }
        return max(0, last.timeIntervalSince(first) - summary.total)
    }

    func shiftDay(_ delta: Int) {
        guard let next = Calendar.current.date(byAdding: .day, value: delta, to: day),
              next <= Calendar.current.startOfDay(for: Date()) else { return }
        day = next
    }

    func goToToday() {
        day = Calendar.current.startOfDay(for: Date())
    }

    func reload() {
        let interval = dayInterval
        tags = (try? store.tags()) ?? []
        rules = (try? store.rules()) ?? []
        tagger = Tagger(tags: tags, rules: rules, manual: (try? store.manualTags()) ?? [])
        events = events(in: interval)
        if devices.isEmpty {
            deviceTotals = [:]
        } else {
            var totals: [String: TimeInterval] = [:]
            for event in (try? store.events(from: interval.start, to: interval.end)) ?? [] {
                totals[event.device, default: 0] += Analyzer.clipped(event, to: interval)
            }
            deviceTotals = totals
        }
        summary = Analyzer.summarize(events, in: interval, tagger: tagger)
        blocks = Analyzer.blocks(events, in: interval, tagger: tagger)
        appRuns = Analyzer.appRuns(events, in: interval, tagger: tagger)
        if let before = Calendar.current.date(byAdding: .day, value: -1, to: day) {
            let previous = DateInterval(start: before, end: day)
            yesterdayTotal = events(in: previous).reduce(0) { $0 + (Analyzer.clipped($1, to: previous)) }
        }
    }

    private func reloadIfToday() {
        if isToday { reload() }
    }

    private func changed() {
        revision += 1
        reload()
    }

    func events(in range: DateInterval) -> [ActivityEvent] {
        let all = (try? store.events(from: range.start, to: range.end)) ?? []
        guard let deviceFilter else { return all }
        return all.filter { $0.device == deviceFilter }
    }

    /// Name of the Mac an event was recorded on.
    func deviceName(for event: ActivityEvent) -> String {
        deviceName(forDevice: event.device)
    }

    func deviceName(forDevice id: String) -> String {
        id.isEmpty ? deviceName : (devices.first { $0.id == id }?.displayName ?? id)
    }

    /// Names another Mac on this Mac only.
    func renameDevice(_ device: SyncedDevice, to name: String) {
        try? store.renameDevice(id: device.id, to: name)
        devices = (try? store.devices()) ?? []
    }

    /// Whether `event` matches the search text and tag filter.
    func passesFilter(_ event: ActivityEvent) -> Bool {
        if let tagFilter, !tagger.tags(for: event).contains(where: { $0.id == tagFilter }) { return false }
        let needle = query.trimmingCharacters(in: .whitespaces).lowercased()
        guard !needle.isEmpty else { return true }
        return [event.appName, event.title, event.path ?? "", event.url ?? ""]
            .contains { $0.lowercased().contains(needle) }
    }

    // MARK: Navigation

    func showRecords(block: Date? = nil, event: Int64? = nil) {
        timelineMode = .records
        if let block { selectedBlock = block }
        selectedEventID = event
        pane = .timeline
    }

    func showReport(_ period: ReportPeriod) {
        reportPeriod = period
        reportAnchor = day
        pane = .reports
    }

    // MARK: Tags and rules

    func setTag(_ tag: Tag, enabled: Bool) {
        guard let id = tag.id else { return }
        try? store.setTagEnabled(id: id, enabled: enabled)
        changed()
    }

    func addTag(name: String, colorIndex: Int, field: RuleField, op: RuleOp, value: String) {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        _ = try? store.addTag(name: trimmed, colorIndex: colorIndex, rule: (field, op, value))
        changed()
    }

    func deleteTag(_ tag: Tag) {
        guard let id = tag.id else { return }
        try? store.deleteTag(id: id)
        changed()
    }

    func addRule(to tag: Tag, field: RuleField, op: RuleOp, value: String) {
        guard let id = tag.id else { return }
        _ = try? store.addRule(tagID: id, field: field, op: op, value: value)
        changed()
    }

    func deleteRule(_ rule: Rule) {
        guard let id = rule.id else { return }
        try? store.deleteRule(id: id)
        changed()
    }

    func moveTag(_ tag: Tag, by delta: Int) {
        guard let id = tag.id else { return }
        try? store.moveTag(id: id, by: delta)
        changed()
    }

    /// Puts `tag` on one record by hand.
    func addTag(_ tag: Tag, to event: ActivityEvent) {
        guard let eventID = event.id, let tagID = tag.id else { return }
        try? store.setManualTag(eventID: eventID, tagID: tagID)
        changed()
    }

    /// Takes `tag` off one record: a hand-added tag is forgotten, an
    /// automatic one is hidden for this record only.
    func removeTag(_ tag: Tag, from event: ActivityEvent) {
        guard let eventID = event.id, let tagID = tag.id else { return }
        if tagger.isManual(tag, for: event) {
            try? store.clearManualTag(eventID: eventID, tagID: tagID)
        } else {
            try? store.setManualTag(eventID: eventID, tagID: tagID, removed: true)
        }
        changed()
    }

    func deleteEvent(_ event: ActivityEvent) {
        guard let id = event.id else { return }
        try? store.deleteEvent(id: id)
        if selectedEventID == id { selectedEventID = nil }
        reload()
    }

    // MARK: Reports and export

    func report(for range: DateInterval) -> RangeReport {
        Analyzer.report(events(in: range), in: range, tagger: tagger)
    }

    /// Asks where to save, then writes every record in `range` as CSV.
    func exportCSV(_ range: DateInterval, name: String) {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.commaSeparatedText]
        panel.nameFieldStringValue = "Trace \(name).csv"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        let text = Analyzer.csv(events(in: range), tagger: tagger)
        do {
            try text.write(to: url, atomically: true, encoding: .utf8)
        } catch {
            NSAlert(error: error).runModal()
        }
    }

    func eraseAllRecords() {
        try? store.deleteAllEvents()
        reload()
    }

    // MARK: Sync

    /// A "Trace" folder in iCloud Drive, when iCloud Drive is set up on this Mac.
    var iCloudFolder: URL? {
        let drive = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Mobile Documents/com~apple~CloudDocs", isDirectory: true)
        guard FileManager.default.fileExists(atPath: drive.path) else { return nil }
        return drive.appendingPathComponent("Trace", isDirectory: true)
    }

    func chooseSyncFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.prompt = L("Use this folder")
        panel.directoryURL = iCloudFolder?.deletingLastPathComponent()
        guard panel.runModal() == .OK, let url = panel.url else { return }
        enableSync(folder: url)
    }

    func enableSync(folder: URL) {
        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        } catch {
            syncError = error.localizedDescription
            return
        }
        syncFolder = folder.path
        UserDefaults.standard.set(folder.path, forKey: "syncFolder")
        syncNow()
    }

    /// Stops syncing and forgets the other Macs' records here. The files in
    /// the folder stay, so turning sync on again brings everything back.
    func disableSync() {
        syncFolder = nil
        UserDefaults.standard.removeObject(forKey: "syncFolder")
        try? store.removeRemoteData()
        devices = []
        deviceFilter = nil
        lastSync = nil
        syncError = nil
        reload()
    }

    func syncNow() {
        guard !isDemo, !isSyncing, let path = syncFolder else { return }
        isSyncing = true
        let trimmed = deviceName.trimmingCharacters(in: .whitespaces)
        let (store, id, name) = (store, deviceID, trimmed.isEmpty ? (Host.current().localizedName ?? "Mac") : trimmed)
        DispatchQueue.global(qos: .utility).async {
            let outcome: Result<SyncEngine.Result, Error> = Result {
                try SyncEngine(store: store, folder: URL(fileURLWithPath: path, isDirectory: true),
                               deviceID: id, deviceName: name).sync()
            }
            DispatchQueue.main.async {
                self.isSyncing = false
                switch outcome {
                case .success(let result):
                    self.lastSync = Date()
                    self.syncError = nil
                    self.devices = (try? store.devices()) ?? []
                    if result.appliedTagging { self.revision += 1 }
                    if result.importedDays > 0 || result.appliedTagging { self.reload() }
                case .failure(let error):
                    self.syncError = error.localizedDescription
                }
            }
        }
    }

    // MARK: Settings

    private func applyAppearance() {
        switch appearance {
        case .system: NSApp.appearance = nil
        case .light: NSApp.appearance = NSAppearance(named: .aqua)
        case .dark: NSApp.appearance = NSAppearance(named: .darkAqua)
        }
    }

    func setLaunchAtLogin(_ enabled: Bool) {
        do {
            if enabled { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
        } catch {
            NSLog("Trace: launch at login failed: \(error.localizedDescription)")
        }
        launchAtLogin = SMAppService.mainApp.status == .enabled
    }

    func finishOnboarding() {
        UserDefaults.standard.set(true, forKey: "onboarded")
        showsOnboarding = false
    }

    func revealDatabase() {
        guard let databaseURL else { return }
        NSWorkspace.shared.activateFileViewerSelecting([databaseURL])
    }
}
