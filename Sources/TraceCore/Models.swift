import Foundation
import GRDB

/// What the watcher sees at one instant: the frontmost app and its focused window.
public struct Sample: Equatable, Sendable {
    public var bundleID: String
    public var appName: String
    public var category: String?
    public var title: String
    public var path: String?
    public var url: String?

    public init(bundleID: String, appName: String, category: String? = nil,
                title: String = "", path: String? = nil, url: String? = nil) {
        self.bundleID = bundleID
        self.appName = appName
        self.category = category
        self.title = title
        self.path = path
        self.url = url
    }
}

/// One uninterrupted stay in the same app, window, document and page.
public struct ActivityEvent: Codable, Identifiable, Equatable, Sendable,
    FetchableRecord, MutablePersistableRecord {
    public var id: Int64?
    public var start: Date
    public var end: Date
    public var bundleID: String
    public var appName: String
    public var category: String?
    public var title: String
    public var path: String?
    public var url: String?
    /// Identifier of the Mac the event was recorded on; empty for this Mac.
    public var device: String = ""
    /// For events from another Mac: the day file they came from.
    public var syncDay: String?

    public static let databaseTableName = "event"

    public var isLocal: Bool { device.isEmpty }

    public init(sample: Sample, start: Date, end: Date) {
        self.start = start
        self.end = end
        bundleID = sample.bundleID
        appName = sample.appName
        category = sample.category
        title = sample.title
        path = sample.path
        url = sample.url
    }

    public mutating func didInsert(_ inserted: InsertionSuccess) {
        id = inserted.rowID
    }

    public var duration: TimeInterval { max(0, end.timeIntervalSince(start)) }

    public var host: String? {
        guard let url, let host = URL(string: url)?.host else { return nil }
        return host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
    }

    func matches(_ s: Sample) -> Bool {
        bundleID == s.bundleID && title == s.title && path == s.path && url == s.url
    }
}

/// A label for activity, either a built-in preset (`key` set) or user-defined.
public struct Tag: Codable, Identifiable, Hashable, Sendable,
    FetchableRecord, MutablePersistableRecord {
    public var id: Int64?
    /// Stable identifier of a preset tag; nil for custom tags.
    public var key: String?
    public var name: String
    public var colorIndex: Int
    public var enabled: Bool
    public var sortOrder: Int

    public static let databaseTableName = "tag"

    public init(id: Int64? = nil, key: String? = nil, name: String,
                colorIndex: Int, enabled: Bool = true, sortOrder: Int) {
        self.id = id
        self.key = key
        self.name = name
        self.colorIndex = colorIndex
        self.enabled = enabled
        self.sortOrder = sortOrder
    }

    public mutating func didInsert(_ inserted: InsertionSuccess) {
        id = inserted.rowID
    }

    public var isPreset: Bool { key != nil }
}

/// Another Mac whose records were brought in through the sync folder.
public struct SyncedDevice: Codable, Identifiable, Hashable, Sendable, FetchableRecord, PersistableRecord {
    public var id: String
    public var name: String
    public var lastSeen: Date?

    public static let databaseTableName = "device"

    public init(id: String, name: String, lastSeen: Date? = nil) {
        self.id = id
        self.name = name
        self.lastSeen = lastSeen
    }
}

/// Tags and rules in a form that can be written to a file and applied on
/// another Mac. Presets are matched by key, custom tags by name.
public struct TaggingSnapshot: Codable, Equatable, Sendable {
    public struct RuleEntry: Codable, Equatable, Sendable {
        public var field: RuleField
        public var op: RuleOp
        public var value: String
    }

    public struct TagEntry: Codable, Equatable, Sendable {
        public var key: String?
        public var name: String
        public var colorIndex: Int
        public var enabled: Bool
        public var sortOrder: Int
        public var rules: [RuleEntry]
    }

    public var updated: Date
    public var tags: [TagEntry]
}

/// A tag the user put on, or took off, one specific event by hand.
public struct ManualTag: Codable, Hashable, Sendable, FetchableRecord, PersistableRecord {
    public var eventID: Int64
    public var tagID: Int64
    /// True when an automatically applied tag was removed from this event.
    public var removed: Bool

    public static let databaseTableName = "eventTag"

    public init(eventID: Int64, tagID: Int64, removed: Bool = false) {
        self.eventID = eventID
        self.tagID = tagID
        self.removed = removed
    }
}

public enum RuleField: String, Codable, CaseIterable, Sendable {
    case app, category, path, url, title
}

public enum RuleOp: String, Codable, CaseIterable, Sendable {
    case equals, contains, hasPrefix
}

/// A condition that applies a tag automatically.
public struct Rule: Codable, Identifiable, Hashable, Sendable,
    FetchableRecord, MutablePersistableRecord {
    public var id: Int64?
    public var tagID: Int64
    public var field: RuleField
    public var op: RuleOp
    public var value: String

    public static let databaseTableName = "rule"

    public init(id: Int64? = nil, tagID: Int64, field: RuleField, op: RuleOp, value: String) {
        self.id = id
        self.tagID = tagID
        self.field = field
        self.op = op
        self.value = value
    }

    public mutating func didInsert(_ inserted: InsertionSuccess) {
        id = inserted.rowID
    }

    public func matches(_ e: ActivityEvent) -> Bool {
        let needle = value.lowercased()
        guard !needle.isEmpty else { return false }
        let candidates: [String]
        switch field {
        case .app: candidates = [e.bundleID, e.appName]
        case .category: candidates = [e.category ?? ""]
        case .path: candidates = [e.path ?? ""]
        case .url: candidates = [e.url ?? ""]
        case .title: candidates = [e.title]
        }
        return candidates.contains { raw in
            let hay = raw.lowercased()
            guard !hay.isEmpty else { return false }
            switch op {
            case .equals: return hay == needle
            case .contains: return hay.contains(needle)
            case .hasPrefix: return hay.hasPrefix(needle)
            }
        }
    }
}
