import Foundation
import GRDB

/// Local SQLite storage for events, tags and rules.
public final class EventStore: @unchecked Sendable {
    private let db: DatabaseQueue

    /// Opens (or creates) the database file at `path`.
    public init(path: String) throws {
        db = try DatabaseQueue(path: path)
        try migrate()
    }

    /// In-memory database, for tests.
    public init() throws {
        db = try DatabaseQueue()
        try migrate()
    }

    private func migrate() throws {
        var migrator = DatabaseMigrator()
        migrator.registerMigration("v1") { db in
            try db.create(table: "event") { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("start", .datetime).notNull().indexed()
                t.column("end", .datetime).notNull().indexed()
                t.column("bundleID", .text).notNull()
                t.column("appName", .text).notNull()
                t.column("category", .text)
                t.column("title", .text).notNull()
                t.column("path", .text)
                t.column("url", .text)
            }
            try db.create(table: "tag") { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("key", .text).unique()
                t.column("name", .text).notNull()
                t.column("colorIndex", .integer).notNull()
                t.column("enabled", .boolean).notNull().defaults(to: true)
                t.column("sortOrder", .integer).notNull()
            }
            try db.create(table: "rule") { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("tagID", .integer).notNull().indexed()
                    .references("tag", onDelete: .cascade)
                t.column("field", .text).notNull()
                t.column("op", .text).notNull()
                t.column("value", .text).notNull()
            }
        }
        migrator.registerMigration("v2") { db in
            try db.create(table: "eventTag") { t in
                t.column("eventID", .integer).notNull().references("event", onDelete: .cascade)
                t.column("tagID", .integer).notNull().references("tag", onDelete: .cascade)
                t.column("removed", .boolean).notNull().defaults(to: false)
                t.primaryKey(["eventID", "tagID"])
            }
        }
        try migrator.migrate(db)
        try seedPresetsIfNeeded()
    }

    // MARK: Events

    /// Records that `sample` was observed at `now`.
    ///
    /// If the latest event describes the same thing and ended at most `pulse`
    /// seconds ago, it is extended; otherwise a new event starts. This keeps one
    /// row per stay instead of one row per sample.
    @discardableResult
    public func heartbeat(_ sample: Sample, at now: Date, pulse: TimeInterval = 15) throws -> ActivityEvent {
        try db.write { db in
            if var last = try ActivityEvent.order(Column("id").desc).fetchOne(db),
               last.matches(sample),
               now >= last.end,
               now.timeIntervalSince(last.end) <= pulse {
                last.end = now
                try last.update(db)
                return last
            }
            var event = ActivityEvent(sample: sample, start: now, end: now)
            try event.insert(db)
            return event
        }
    }

    /// Cuts the latest event back to `date`, used when the user turns out to
    /// have been idle since then.
    public func trimLast(to date: Date) throws {
        try db.write { db in
            guard var last = try ActivityEvent.order(Column("id").desc).fetchOne(db),
                  last.end > date else { return }
            last.end = max(last.start, date)
            try last.update(db)
        }
    }

    /// Events overlapping `[from, to)`, oldest first.
    public func events(from: Date, to: Date) throws -> [ActivityEvent] {
        try db.read { db in
            try ActivityEvent
                .filter(Column("end") > from && Column("start") < to)
                .order(Column("start"))
                .fetchAll(db)
        }
    }

    public func deleteEvent(id: Int64) throws {
        _ = try db.write { db in try ActivityEvent.deleteOne(db, key: id) }
    }

    public func eventCount() throws -> Int {
        try db.read { db in try ActivityEvent.fetchCount(db) }
    }

    // MARK: Tags and rules

    public func tags() throws -> [Tag] {
        try db.read { db in try Tag.order(Column("sortOrder"), Column("id")).fetchAll(db) }
    }

    public func rules() throws -> [Rule] {
        try db.read { db in try Rule.order(Column("id")).fetchAll(db) }
    }

    public func setTagEnabled(id: Int64, enabled: Bool) throws {
        try db.write { db in
            guard var tag = try Tag.fetchOne(db, key: id) else { return }
            tag.enabled = enabled
            try tag.update(db)
        }
    }

    /// Creates a custom tag, optionally with one rule. Custom tags sort before
    /// presets so that a specific tag wins over a generic one.
    @discardableResult
    public func addTag(name: String, colorIndex: Int,
                       rule: (field: RuleField, op: RuleOp, value: String)? = nil) throws -> Tag {
        try db.write { db in
            let minOrder = try Int.fetchOne(db, sql: "SELECT MIN(sortOrder) FROM tag") ?? 0
            var tag = Tag(name: name, colorIndex: colorIndex, sortOrder: min(minOrder, 0) - 1)
            try tag.insert(db)
            if let rule, let tagID = tag.id, !rule.value.trimmingCharacters(in: .whitespaces).isEmpty {
                var record = Rule(tagID: tagID, field: rule.field, op: rule.op,
                                  value: rule.value.trimmingCharacters(in: .whitespaces))
                try record.insert(db)
            }
            return tag
        }
    }

    public func deleteTag(id: Int64) throws {
        _ = try db.write { db in try Tag.deleteOne(db, key: id) }
    }

    @discardableResult
    public func addRule(tagID: Int64, field: RuleField, op: RuleOp, value: String) throws -> Rule? {
        let trimmed = value.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return nil }
        return try db.write { db in
            var rule = Rule(tagID: tagID, field: field, op: op, value: trimmed)
            try rule.insert(db)
            return rule
        }
    }

    public func deleteRule(id: Int64) throws {
        _ = try db.write { db in try Rule.deleteOne(db, key: id) }
    }

    /// Moves a tag up (negative `delta`) or down in priority. When several
    /// tags match an event, the one listed first is its primary tag.
    public func moveTag(id: Int64, by delta: Int) throws {
        try db.write { db in
            var tags = try Tag.order(Column("sortOrder"), Column("id")).fetchAll(db)
            guard let index = tags.firstIndex(where: { $0.id == id }) else { return }
            let target = min(max(index + delta, 0), tags.count - 1)
            guard target != index else { return }
            let moved = tags.remove(at: index)
            tags.insert(moved, at: target)
            for (order, var tag) in tags.enumerated() where tag.sortOrder != order {
                tag.sortOrder = order
                try tag.update(db)
            }
        }
    }

    public func tagger() throws -> Tagger {
        Tagger(tags: try tags(), rules: try rules(), manual: try manualTags())
    }

    // MARK: Manual tags

    public func manualTags() throws -> [ManualTag] {
        try db.read { db in try ManualTag.fetchAll(db) }
    }

    /// Adds `tagID` to one event by hand, or (with `removed`) hides a tag
    /// that a rule applied to it.
    public func setManualTag(eventID: Int64, tagID: Int64, removed: Bool = false) throws {
        try db.write { db in try ManualTag(eventID: eventID, tagID: tagID, removed: removed).save(db) }
    }

    /// Forgets a manual change, so the rules decide again.
    public func clearManualTag(eventID: Int64, tagID: Int64) throws {
        _ = try db.write { db in
            try ManualTag.deleteOne(db, key: ["eventID": eventID, "tagID": tagID])
        }
    }

    public func deleteAllEvents() throws {
        _ = try db.write { db in try ActivityEvent.deleteAll(db) }
    }

    private func seedPresetsIfNeeded() throws {
        try db.write { db in
            guard try Tag.fetchCount(db) == 0 else { return }
            for (index, preset) in Presets.all.enumerated() {
                var tag = Tag(key: preset.key, name: preset.name,
                              colorIndex: preset.colorIndex, sortOrder: index)
                try tag.insert(db)
                guard let tagID = tag.id else { continue }
                for r in preset.rules {
                    var rule = Rule(tagID: tagID, field: r.0, op: r.1, value: r.2)
                    try rule.insert(db)
                }
            }
        }
    }
}
