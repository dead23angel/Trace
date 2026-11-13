import Foundation

public struct TagTotal: Identifiable, Sendable {
    public let tag: Tag?
    public let seconds: TimeInterval
    public var id: Int64 { tag?.id ?? 0 }
}

public struct AppTotal: Identifiable, Sendable {
    public let bundleID: String
    public let appName: String
    public let tag: Tag?
    public let seconds: TimeInterval
    public var id: String { bundleID }
}

/// Time spent on one tag during one hour of the day.
public struct HourSlice: Identifiable, Sendable {
    public let hour: Int
    public let tag: Tag?
    public let seconds: TimeInterval
    public var id: String { "\(hour)-\(tag?.id ?? 0)" }
}

/// A run of consecutive events sharing a primary tag: a "session".
public struct Block: Identifiable, Sendable {
    public var start: Date
    public var end: Date
    public let tag: Tag?
    public var events: [ActivityEvent]
    public var id: Date { start }
    public var duration: TimeInterval { end.timeIntervalSince(start) }
    /// The Mac the session happened on; empty for this Mac.
    public var device: String { events.first?.device ?? "" }

    /// The app and item the session was mostly about, e.g. "Xcode · Store.swift".
    public var title: String {
        var apps: [String: TimeInterval] = [:]
        var items: [String: TimeInterval] = [:]
        for e in events {
            apps[e.appName, default: 0] += e.duration
            if let label = Analyzer.item(for: e)?.shortLabel {
                items["\(e.appName)\u{1F}\(label)", default: 0] += e.duration
            }
        }
        guard let app = apps.max(by: { $0.value < $1.value })?.key else { return "" }
        let best = items.filter { $0.key.hasPrefix("\(app)\u{1F}") }.max { $0.value < $1.value }
        guard let label = best?.key.split(separator: "\u{1F}").last else { return app }
        return "\(app) · \(label)"
    }
}

public struct DaySummary: Sendable {
    public var total: TimeInterval = 0
    public var byTag: [TagTotal] = []
    public var byApp: [AppTotal] = []
    public var hourly: [HourSlice] = []
    public var first: Date?
    public var last: Date?
    public init() {}
}

/// One calendar day inside a report.
public struct DayTotal: Identifiable, Sendable {
    public let day: Date
    public let total: TimeInterval
    public let byTag: [TagTotal]
    public var id: Date { day }
}

/// Time recorded in one hour of one weekday (1 = Sunday, as in `Calendar`).
public struct HeatCell: Identifiable, Sendable {
    public let weekday: Int
    public let hour: Int
    public let seconds: TimeInterval
    public var id: Int { weekday * 24 + hour }
}

/// Time spent on one site, file or other named thing.
public struct ItemTotal: Identifiable, Sendable {
    public let label: String
    public let seconds: TimeInterval
    public var id: String { label }

    public init(label: String, seconds: TimeInterval) {
        self.label = label
        self.seconds = seconds
    }
}

/// Puts intervals that overlap in time into separate lanes, so that they
/// can be drawn side by side.
public enum Lanes {
    /// For each interval (sorted by start), its lane, and the number of lanes
    /// used by the group of overlapping intervals it belongs to.
    public static func assign(_ intervals: [(start: Date, end: Date)]) -> [(lane: Int, of: Int)] {
        var result = Array(repeating: (lane: 0, of: 1), count: intervals.count)
        var ends: [Date] = []           // end of the last interval in each lane
        var group: [Int] = []           // indices in the current overlapping group
        var groupEnd = Date.distantPast
        func close() {
            for index in group { result[index].of = ends.count }
        }
        for (index, interval) in intervals.enumerated() {
            if interval.start >= groupEnd {
                close()
                group = []
                ends = []
            }
            let lane = ends.firstIndex { $0 <= interval.start } ?? ends.count
            if lane == ends.count { ends.append(interval.end) } else { ends[lane] = interval.end }
            result[index].lane = lane
            group.append(index)
            groupEnd = max(groupEnd, interval.end)
        }
        close()
        return result
    }
}

/// A stretch spent in one app, whatever the window: one bar in an app lane.
public struct AppRun: Identifiable, Sendable {
    public let start: Date
    public var end: Date
    public let bundleID: String
    public let appName: String
    public let tag: Tag?
    public var id: Date { start }
}

/// Untagged activity grouped by where it happened, with the rule that would
/// catch it.
public struct LooseItem: Identifiable, Sendable {
    public let label: String
    public let seconds: TimeInterval
    public let field: RuleField
    public let value: String
    public var id: String { label }
}

/// Several days summed up: a week, a month or a year.
public struct RangeReport: Sendable {
    public var total: TimeInterval = 0
    public var days: [DayTotal] = []
    public var byTag: [TagTotal] = []
    public var byApp: [AppTotal] = []
    public var heat: [HeatCell] = []
    public var sites: [ItemTotal] = []
    public var files: [ItemTotal] = []
    /// Time per Mac; the label is the device identifier, empty for this Mac.
    public var byDevice: [ItemTotal] = []
    public init() {}

    public var activeDays: Int { days.filter { $0.total > 0 }.count }
    public var dailyAverage: TimeInterval { activeDays > 0 ? total / Double(activeDays) : 0 }
    public var busiest: DayTotal? { days.filter { $0.total > 0 }.max { $0.total < $1.total } }
}

public struct TreeNode: Identifiable, Sendable {
    public enum Kind: Sendable { case tag, app, file, web, window, page }
    public let id: String
    public let kind: Kind
    public let label: String
    public let seconds: TimeInterval
    public let tag: Tag?
    public let bundleID: String?
    public var children: [TreeNode]?
}

public enum TreeMode: Sendable { case byTag, byApp }

public enum Analyzer {
    struct Item { let kind: TreeNode.Kind; let label: String; let shortLabel: String; let page: String? }

    /// What an event was "about" inside its app: a file, a site or a window.
    static func item(for e: ActivityEvent) -> Item? {
        if let path = e.path, !path.isEmpty {
            return Item(kind: .file, label: abbreviate(path),
                        shortLabel: (path as NSString).lastPathComponent, page: nil)
        }
        if let host = e.host {
            return Item(kind: .web, label: host, shortLabel: host, page: e.title.isEmpty ? nil : e.title)
        }
        // A window titled like its app says nothing more than the app row does.
        if !e.title.isEmpty, e.title != e.appName {
            return Item(kind: .window, label: e.title, shortLabel: e.title, page: nil)
        }
        return nil
    }

    public static func abbreviate(_ path: String) -> String {
        let home = NSHomeDirectory()
        return path.hasPrefix(home) ? "~" + path.dropFirst(home.count) : path
    }

    static func clip(_ e: ActivityEvent, to range: DateInterval) -> DateInterval? {
        let start = max(e.start, range.start), end = min(e.end, range.end)
        return end > start ? DateInterval(start: start, end: end) : nil
    }

    /// Seconds of `e` that fall inside `range`.
    public static func clipped(_ e: ActivityEvent, to range: DateInterval) -> TimeInterval {
        clip(e, to: range)?.duration ?? 0
    }

    public static func summarize(_ events: [ActivityEvent], in day: DateInterval,
                                 tagger: Tagger, calendar: Calendar = .current) -> DaySummary {
        var summary = DaySummary()
        var tagSeconds: [Int64: TimeInterval] = [:]
        var tagByID: [Int64: Tag] = [:]
        var apps: [String: (name: String, tags: [Int64: TimeInterval], seconds: TimeInterval)] = [:]
        var hourly: [Int: [Int64: TimeInterval]] = [:]

        for e in events {
            guard let span = clip(e, to: day) else { continue }
            let tag = tagger.primary(for: e)
            let tagID = tag?.id ?? 0
            if let tag { tagByID[tagID] = tag }

            summary.total += span.duration
            summary.first = min(summary.first ?? span.start, span.start)
            summary.last = max(summary.last ?? span.end, span.end)
            tagSeconds[tagID, default: 0] += span.duration

            var app = apps[e.bundleID] ?? (e.appName, [:], 0)
            app.seconds += span.duration
            app.tags[tagID, default: 0] += span.duration
            apps[e.bundleID] = app

            var cursor = span.start
            while cursor < span.end {
                let hour = calendar.component(.hour, from: cursor)
                let hourEnd = calendar.dateInterval(of: .hour, for: cursor)?.end ?? span.end
                let next = min(span.end, hourEnd)
                hourly[hour, default: [:]][tagID, default: 0] += next.timeIntervalSince(cursor)
                cursor = next
            }
        }

        summary.byTag = tagSeconds
            .map { TagTotal(tag: tagByID[$0.key], seconds: $0.value) }
            .sorted { $0.seconds > $1.seconds }
        summary.byApp = apps
            .map { bundleID, app in
                let top = app.tags.max { $0.value < $1.value }?.key ?? 0
                return AppTotal(bundleID: bundleID, appName: app.name, tag: tagByID[top], seconds: app.seconds)
            }
            .sorted { $0.seconds > $1.seconds }
        summary.hourly = hourly
            .flatMap { hour, tags in
                tags.map { HourSlice(hour: hour, tag: tagByID[$0.key], seconds: $0.value) }
            }
            .sorted { ($0.hour, $0.tag?.sortOrder ?? .max) < ($1.hour, $1.tag?.sortOrder ?? .max) }
        return summary
    }

    /// Totals for a span of several days, with one entry per calendar day
    /// (empty days included), an hour-by-weekday grid, and the most used
    /// sites and files.
    public static func report(_ events: [ActivityEvent], in range: DateInterval,
                              tagger: Tagger, calendar: Calendar = .current) -> RangeReport {
        var report = RangeReport()
        let whole = summarize(events, in: range, tagger: tagger, calendar: calendar)
        report.total = whole.total
        report.byTag = whole.byTag
        report.byApp = whole.byApp

        var tagByID: [Int64: Tag] = [:]
        var perDay: [Date: [Int64: TimeInterval]] = [:]
        var heat: [Int: TimeInterval] = [:]
        var sites: [String: TimeInterval] = [:]
        var files: [String: TimeInterval] = [:]
        var perDevice: [String: TimeInterval] = [:]
        for e in events {
            guard let span = clip(e, to: range) else { continue }
            perDevice[e.device, default: 0] += span.duration
            let tag = tagger.primary(for: e)
            let tagID = tag?.id ?? 0
            if let tag { tagByID[tagID] = tag }
            if let path = e.path, !path.isEmpty { files[path, default: 0] += span.duration }
            else if let host = e.host { sites[host, default: 0] += span.duration }

            var cursor = span.start
            while cursor < span.end {
                let hourEnd = calendar.dateInterval(of: .hour, for: cursor)?.end ?? span.end
                let next = min(span.end, hourEnd)
                let parts = calendar.dateComponents([.weekday, .hour], from: cursor)
                let seconds = next.timeIntervalSince(cursor)
                perDay[calendar.startOfDay(for: cursor), default: [:]][tagID, default: 0] += seconds
                heat[(parts.weekday ?? 1) * 24 + (parts.hour ?? 0), default: 0] += seconds
                cursor = next
            }
        }

        var day = calendar.startOfDay(for: range.start)
        while day < range.end {
            let tags = perDay[day] ?? [:]
            let byTag = tags.map { TagTotal(tag: tagByID[$0.key], seconds: $0.value) }
                .sorted { $0.seconds > $1.seconds }
            report.days.append(DayTotal(day: day, total: tags.values.reduce(0, +), byTag: byTag))
            day = calendar.date(byAdding: .day, value: 1, to: day) ?? day.addingTimeInterval(86_400)
        }
        report.heat = heat.map { HeatCell(weekday: $0.key / 24, hour: $0.key % 24, seconds: $0.value) }
        report.sites = sites.map { ItemTotal(label: $0.key, seconds: $0.value) }.sorted { $0.seconds > $1.seconds }
        report.byDevice = perDevice.map { ItemTotal(label: $0.key, seconds: $0.value) }.sorted { $0.seconds > $1.seconds }
        report.files = files.map { ItemTotal(label: $0.key, seconds: $0.value) }.sorted { $0.seconds > $1.seconds }
        return report
    }

    /// Consecutive events in the same app, merged across short gaps.
    public static func appRuns(_ events: [ActivityEvent], in day: DateInterval,
                               tagger: Tagger, maxGap: TimeInterval = 30) -> [AppRun] {
        Dictionary(grouping: events, by: \.device).values
            .flatMap { runs($0, in: day, tagger: tagger, maxGap: maxGap) }
            .sorted { $0.start < $1.start }
    }

    private static func runs(_ events: [ActivityEvent], in day: DateInterval,
                             tagger: Tagger, maxGap: TimeInterval) -> [AppRun] {
        var runs: [AppRun] = []
        for e in events {
            guard let span = clip(e, to: day) else { continue }
            let tag = tagger.primary(for: e)
            if var last = runs.last, last.bundleID == e.bundleID, last.tag?.id == tag?.id,
               span.start.timeIntervalSince(last.end) <= maxGap {
                last.end = max(last.end, span.end)
                runs[runs.count - 1] = last
            } else {
                runs.append(AppRun(start: span.start, end: span.end, bundleID: e.bundleID,
                                   appName: e.appName, tag: tag))
            }
        }
        return runs
    }

    /// Where the untagged time went: by site for web pages, by app otherwise.
    public static func untagged(_ events: [ActivityEvent], in range: DateInterval,
                                tagger: Tagger) -> [LooseItem] {
        var totals: [String: (seconds: TimeInterval, field: RuleField, value: String)] = [:]
        for e in events {
            guard let span = clip(e, to: range), tagger.primary(for: e) == nil else { continue }
            let key: String, field: RuleField, value: String
            if let host = e.host {
                (key, field, value) = ("\(e.appName) · \(host)", .url, host)
            } else {
                (key, field, value) = (e.appName, .app, e.bundleID)
            }
            var entry = totals[key] ?? (0, field, value)
            entry.seconds += span.duration
            totals[key] = entry
        }
        return totals.map { LooseItem(label: $0.key, seconds: $0.value.seconds, field: $0.value.field, value: $0.value.value) }
            .sorted { $0.seconds > $1.seconds }
    }

    /// Events as CSV text, one row per stay, for use in a spreadsheet.
    public static func csv(_ events: [ActivityEvent], tagger: Tagger) -> String {
        let iso = ISO8601DateFormatter()
        func quote(_ s: String) -> String { "\"" + s.replacingOccurrences(of: "\"", with: "\"\"") + "\"" }
        var lines = ["start,end,seconds,app,bundle_id,title,path,url,tags"]
        for e in events {
            let tags = tagger.tags(for: e).map(\.name).joined(separator: ";")
            lines.append([
                iso.string(from: e.start), iso.string(from: e.end), String(Int(e.duration.rounded())),
                quote(e.appName), quote(e.bundleID), quote(e.title), quote(e.path ?? ""), quote(e.url ?? ""),
                quote(tags),
            ].joined(separator: ","))
        }
        return lines.joined(separator: "\n") + "\n"
    }

    /// Groups events into sessions. Consecutive events with the same primary
    /// tag form a run; a run shorter than `minDuration` is a brief interruption
    /// and joins its neighbour instead of splitting the session. Gaps longer
    /// than `maxGap` always split. A session takes the tag it spent most time on.
    ///
    /// Each Mac gets its own sessions: when two Macs were in use at the same
    /// time, their sessions overlap instead of being mixed into one.
    public static func blocks(_ events: [ActivityEvent], in day: DateInterval, tagger: Tagger,
                              maxGap: TimeInterval = 300, minDuration: TimeInterval = 120) -> [Block] {
        Dictionary(grouping: events, by: \.device).values
            .flatMap { sessions($0, in: day, tagger: tagger, maxGap: maxGap, minDuration: minDuration) }
            .sorted { $0.start < $1.start }
    }

    private static func sessions(_ events: [ActivityEvent], in day: DateInterval, tagger: Tagger,
                                 maxGap: TimeInterval, minDuration: TimeInterval) -> [Block] {
        struct Run {
            var start: Date
            var end: Date
            var events: [ActivityEvent]
            var seconds: [Int64: TimeInterval]
            var tags: [Int64: Tag]
            var lastTag: Int64
            var span: TimeInterval { end.timeIntervalSince(start) }
        }
        var runs: [Run] = []
        for e in events {
            guard let span = clip(e, to: day) else { continue }
            let tag = tagger.primary(for: e)
            let tagID = tag?.id ?? 0
            var clipped = e
            clipped.start = span.start
            clipped.end = span.end
            if var last = runs.last, span.start.timeIntervalSince(last.end) <= maxGap,
               last.lastTag == tagID || span.duration < minDuration || last.span < minDuration {
                last.end = max(last.end, span.end)
                last.events.append(clipped)
                last.seconds[tagID, default: 0] += span.duration
                if let tag { last.tags[tagID] = tag }
                // A brief interruption does not change what the session is about.
                if span.duration >= minDuration || last.span < minDuration { last.lastTag = tagID }
                runs[runs.count - 1] = last
            } else {
                runs.append(Run(start: span.start, end: span.end, events: [clipped],
                                seconds: [tagID: span.duration], tags: tag.map { [tagID: $0] } ?? [:],
                                lastTag: tagID))
            }
        }
        return runs.map { run in
            let top = run.seconds.max { $0.value < $1.value }?.key ?? 0
            return Block(start: run.start, end: run.end, tag: run.tags[top], events: run.events)
        }
    }

    /// The drill-down outline: tag › app › file or site › page.
    public static func tree(_ events: [ActivityEvent], in day: DateInterval,
                            tagger: Tagger, mode: TreeMode) -> [TreeNode] {
        struct Leaf {
            let tag: Tag?
            let bundleID: String
            let appName: String
            let item: Item?
            let seconds: TimeInterval
        }
        let leaves: [Leaf] = events.compactMap { e in
            guard let span = clip(e, to: day) else { return nil }
            return Leaf(tag: tagger.primary(for: e), bundleID: e.bundleID, appName: e.appName,
                        item: item(for: e), seconds: span.duration)
        }

        func total(_ xs: [Leaf]) -> TimeInterval { xs.reduce(0) { $0 + $1.seconds } }
        func grouped<K: Hashable>(_ xs: [Leaf], by key: (Leaf) -> K) -> [[Leaf]] {
            Dictionary(grouping: xs, by: key).values.sorted { total($0) > total($1) }
        }

        func itemNodes(_ xs: [Leaf], prefix: String, tag: Tag?) -> [TreeNode]? {
            let withItem = xs.filter { $0.item != nil }
            guard !withItem.isEmpty else { return nil }
            return grouped(withItem) { $0.item!.label }.map { group in
                let item = group[0].item!
                let id = "\(prefix)/\(item.label)"
                var pages: [TreeNode]?
                if item.kind == .web {
                    let titled = group.filter { $0.item?.page != nil }
                    let nodes = grouped(titled) { $0.item!.page! }.map { pageGroup in
                        TreeNode(id: "\(id)/\(pageGroup[0].item!.page!)", kind: .page,
                                 label: pageGroup[0].item!.page!, seconds: total(pageGroup),
                                 tag: tag, bundleID: nil, children: nil)
                    }
                    pages = nodes.isEmpty ? nil : nodes
                }
                return TreeNode(id: id, kind: item.kind, label: item.label, seconds: total(group),
                                tag: tag, bundleID: nil, children: pages)
            }
        }

        func appNodes(_ xs: [Leaf], prefix: String, tag: Tag?) -> [TreeNode] {
            grouped(xs) { $0.bundleID }.map { group in
                let id = "\(prefix)/\(group[0].bundleID)"
                let nodeTag = tag ?? group.max { $0.seconds < $1.seconds }?.tag
                return TreeNode(id: id, kind: .app, label: group[0].appName, seconds: total(group),
                                tag: nodeTag, bundleID: group[0].bundleID,
                                children: itemNodes(group, prefix: id, tag: nodeTag))
            }
        }

        switch mode {
        case .byApp:
            return appNodes(leaves, prefix: "app", tag: nil)
        case .byTag:
            return grouped(leaves) { $0.tag?.id ?? 0 }.map { group in
                let tag = group[0].tag
                let id = "tag-\(tag?.id ?? 0)"
                return TreeNode(id: id, kind: .tag, label: tag?.name ?? "", seconds: total(group),
                                tag: tag, bundleID: nil, children: appNodes(group, prefix: id, tag: tag))
            }
        }
    }
}
