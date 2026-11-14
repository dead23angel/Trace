import Foundation

// MARK: Projects

/// Works out which project a file belongs to, so that time can be summed
/// per project without any setup.
///
/// A project is the nearest folder above the file that looks like the root
/// of one (a git repository, a Swift package, an Obsidian vault, and so on).
/// For files that are not on this Mac, or sit in no such folder, the folder
/// directly inside Documents, Desktop, Developer and similar is used.
public final class ProjectResolver: @unchecked Sendable {
    public struct Project: Hashable, Sendable {
        /// The project's folder.
        public let id: String
        public let name: String
    }

    static let markers = [".git", "Package.swift", "package.json", "pyproject.toml", "Cargo.toml", "go.mod",
                          ".obsidian", "pom.xml", "build.gradle", "CMakeLists.txt", "Makefile", "requirements.txt"]
    static let containers: Set<String> = ["Documents", "Desktop", "Downloads", "Developer", "Projects", "projects",
                                          "Github", "GitHub", "github", "Code", "code", "workspace", "Workspace",
                                          "repos", "Repos", "src", "Sites"]

    private let home: String
    private let exists: (String) -> Bool
    private var cache: [String: Project?] = [:]
    private let lock = NSLock()

    public init(home: String = NSHomeDirectory(),
                exists: @escaping (String) -> Bool = { FileManager.default.fileExists(atPath: $0) }) {
        self.home = home
        self.exists = exists
    }

    public func project(for path: String) -> Project? {
        let folder = (path as NSString).deletingLastPathComponent
        guard folder.hasPrefix("/"), folder.count > 1 else { return nil }
        lock.lock()
        defer { lock.unlock() }
        if let known = cache[folder] { return known }
        let found = byMarker(folder) ?? byContainer(folder)
        cache[folder] = found
        return found
    }

    /// Walks up from `folder` looking for a project root on disk.
    private func byMarker(_ folder: String) -> Project? {
        guard exists(folder) else { return nil }
        var current = folder
        for _ in 0..<12 {
            if current == "/" || current == home || current.isEmpty { return nil }
            if Self.markers.contains(where: { exists(current + "/" + $0) }) {
                return Project(id: current, name: (current as NSString).lastPathComponent)
            }
            current = (current as NSString).deletingLastPathComponent
        }
        return nil
    }

    /// The first folder below the well-known containers: `~/Documents/GitHub/App/src/x.c`
    /// belongs to "App", not to "GitHub" and not to whatever lies under `src`.
    private func byContainer(_ folder: String) -> Project? {
        let parts = folder.split(separator: "/").map(String.init)
        guard var index = parts.firstIndex(where: Self.containers.contains) else { return nil }
        while index + 1 < parts.count, Self.containers.contains(parts[index + 1]) { index += 1 }
        guard index + 1 < parts.count else { return nil }
        return Project(id: "/" + parts[...(index + 1)].joined(separator: "/"), name: parts[index + 1])
    }
}

// MARK: Gantt

/// One bar in a lane of the day.
public struct GanttBar: Identifiable, Sendable {
    public let start: Date
    public var end: Date
    public let tag: Tag?
    /// What the bar stands for, usually an app name.
    public let label: String
    /// Drawn lighter: the app was open but had no window showing.
    public let faint: Bool
    public var id: Date { start }

    public init(start: Date, end: Date, tag: Tag?, label: String, faint: Bool = false) {
        self.start = start
        self.end = end
        self.tag = tag
        self.label = label
        self.faint = faint
    }
}

/// One lane of the day: everything of one tag, one app, one background
/// activity or one Mac.
public struct GanttRow: Identifiable, Sendable {
    public enum Kind: Sendable { case tag, app, audio, mic, device, session, open }
    public let id: String
    public let kind: Kind
    public let label: String
    public let tag: Tag?
    public let bundleID: String?
    public var seconds: TimeInterval
    public var bars: [GanttBar]

    public init(id: String, kind: Kind, label: String, tag: Tag?, bundleID: String?, seconds: TimeInterval, bars: [GanttBar]) {
        self.id = id
        self.kind = kind
        self.label = label
        self.tag = tag
        self.bundleID = bundleID
        self.seconds = seconds
        self.bars = bars
    }
}

public enum GanttGrouping: Sendable { case tag, app }

public struct Gantt: Sendable {
    /// What was in front, one lane per tag or per app, busiest first.
    public var rows: [GanttRow] = []
    /// Sound and microphone lanes; empty when nothing was recorded.
    public var background: [GanttRow] = []
    /// One lane per app that was open, in front or not, longest on screen first.
    public var open: [GanttRow] = []
    /// One lane per Mac, when there is more than one.
    public var devices: [GanttRow] = []
}

// MARK: Focus

public struct FocusSummary: Sendable {
    public struct Interrupter: Identifiable, Sendable {
        public let bundleID: String
        public let appName: String
        public let count: Int
        public var id: String { bundleID }
    }

    /// Time in stretches of focus work at least `deepMinimum` long.
    public var deepSeconds: TimeInterval = 0
    public var deepCount = 0
    public var longestDeep: TimeInterval = 0
    /// All time on focus tags, long stretches or not.
    public var focusSeconds: TimeInterval = 0
    public var distractionSeconds: TimeInterval = 0
    public var total: TimeInterval = 0
    /// Times the app in front changed.
    public var switches = 0
    public var switchesByHour: [Int: Int] = [:]
    /// Apps that most often took over from focus work.
    public var interrupters: [Interrupter] = []
    public init() {}

    /// Share of tracked time spent in deep work, from 0 to 1.
    public var deepShare: Double { total > 0 ? deepSeconds / total : 0 }
    /// App switches per hour of tracked time.
    public var switchesPerHour: Double { total >= 600 ? Double(switches) / (total / 3600) : 0 }
}

// MARK: Review

/// What stands out in a period compared with the one before it.
public struct PeriodReview: Sendable {
    public struct Change: Identifiable, Sendable {
        public let tag: Tag?
        public let delta: TimeInterval
        public var id: Int64 { tag?.id ?? 0 }
    }

    public var total: TimeInterval = 0
    public var previousTotal: TimeInterval = 0
    public var topTag: TagTotal?
    /// Tags that grew or shrank the most, largest change first.
    public var risers: [Change] = []
    public var fallers: [Change] = []
    public var busiest: DayTotal?
    public var deepSeconds: TimeInterval = 0
    public var previousDeepSeconds: TimeInterval = 0
    public var bestFocusDay: (day: Date, seconds: TimeInterval)?
    public var switchesPerHour: Double = 0
    /// Apps and sites used for at least five minutes that did not appear before.
    public var newApps: [String] = []
    public var newSites: [String] = []
    public var topProject: ItemTotal?
    public init() {}
}

extension Analyzer {
    private static func merged(_ bars: [GanttBar], gap: TimeInterval) -> [GanttBar] {
        var result: [GanttBar] = []
        for bar in bars.sorted(by: { $0.start < $1.start }) {
            if var last = result.last, last.tag?.id == bar.tag?.id, last.label == bar.label, last.faint == bar.faint,
               bar.start.timeIntervalSince(last.end) <= gap {
                last.end = max(last.end, bar.end)
                result[result.count - 1] = last
            } else {
                result.append(bar)
            }
        }
        return result
    }

    /// The day as parallel lanes. `events` is what was in front and
    /// `background` what played sound, used the microphone or was open.
    public static func gantt(_ events: [ActivityEvent], background: [ActivityEvent] = [], in day: DateInterval,
                             tagger: Tagger, grouping: GanttGrouping, maxRows: Int = 10,
                             deviceName: (String) -> String = { $0 }) -> Gantt {
        var gantt = Gantt()

        // Front lanes.
        var rows: [String: GanttRow] = [:]
        for e in events {
            guard let span = clip(e, to: day) else { continue }
            let tag = tagger.primary(for: e)
            let key = grouping == .tag ? "tag-\(tag?.id ?? 0)" : "app-\(e.bundleID)"
            var row = rows[key] ?? GanttRow(id: key, kind: grouping == .tag ? .tag : .app,
                                            label: grouping == .tag ? (tag?.name ?? "") : e.appName,
                                            tag: tag, bundleID: grouping == .tag ? nil : e.bundleID, seconds: 0, bars: [])
            row.seconds += span.duration
            row.bars.append(GanttBar(start: span.start, end: span.end, tag: tag,
                                     label: grouping == .tag ? "" : e.appName))
            rows[key] = row
        }
        gantt.rows = rows.values.sorted { $0.seconds > $1.seconds }.prefix(maxRows).map { row in
            var row = row
            row.bars = merged(row.bars, gap: 60)
            return row
        }

        // Sound and microphone.
        for (layer, kind, id) in [(Layer.audio, GanttRow.Kind.audio, "audio"), (.mic, .mic, "mic")] {
            var row = GanttRow(id: id, kind: kind, label: "", tag: nil, bundleID: nil, seconds: 0, bars: [])
            for e in background where e.layer == layer.rawValue {
                guard let span = clip(e, to: day) else { continue }
                row.bars.append(GanttBar(start: span.start, end: span.end, tag: tagger.primary(for: e), label: e.appName))
            }
            row.bars = merged(row.bars, gap: 60).filter { $0.end.timeIntervalSince($0.start) >= 20 }
            // Sound from two apps at once counts once.
            row.seconds = union(row.bars.map { ($0.start, $0.end) })
            if !row.bars.isEmpty { gantt.background.append(row) }
        }

        // Everything that was open, one lane per app.
        var open: [String: (row: GanttRow, showing: TimeInterval)] = [:]
        for e in background where e.layer == Layer.visible.rawValue || e.layer == Layer.open.rawValue {
            guard let span = clip(e, to: day) else { continue }
            let showing = e.layer == Layer.visible.rawValue
            var item = open[e.bundleID] ?? (GanttRow(id: "open-\(e.bundleID)", kind: .open, label: e.appName,
                                                     tag: tagger.primary(for: e), bundleID: e.bundleID, seconds: 0, bars: []), 0)
            item.row.bars.append(GanttBar(start: span.start, end: span.end, tag: item.row.tag, label: "", faint: !showing))
            if showing { item.showing += span.duration }
            open[e.bundleID] = item
        }
        gantt.open = open.values.compactMap { item -> (row: GanttRow, showing: TimeInterval)? in
            var row = item.row
            row.bars = merged(row.bars, gap: 60)
            row.seconds = union(row.bars.map { ($0.start, $0.end) })
            return row.seconds >= 60 ? (row, item.showing) : nil
        }
        .sorted { ($0.showing, $0.row.seconds, $1.row.label) > ($1.showing, $1.row.seconds, $0.row.label) }
        .map(\.row)

        // One lane per Mac.
        let byDevice = Dictionary(grouping: events, by: \.device)
        if byDevice.count > 1 {
            gantt.devices = byDevice.map { device, events in
                var bars: [GanttBar] = []
                var seconds: TimeInterval = 0
                for e in events {
                    guard let span = clip(e, to: day) else { continue }
                    seconds += span.duration
                    bars.append(GanttBar(start: span.start, end: span.end, tag: nil, label: ""))
                }
                return GanttRow(id: "device-\(device)", kind: .device, label: deviceName(device), tag: nil,
                                bundleID: nil, seconds: seconds, bars: merged(bars, gap: 300))
            }
            .sorted { $0.seconds > $1.seconds }
        }
        return gantt
    }

    /// Total length covered by intervals, counting overlaps once.
    static func union(_ intervals: [(Date, Date)]) -> TimeInterval {
        var total: TimeInterval = 0
        var end = Date.distantPast
        for (start, stop) in intervals.sorted(by: { $0.0 < $1.0 }) {
            if stop <= end { continue }
            total += stop.timeIntervalSince(max(start, end))
            end = stop
        }
        return total
    }

    /// How focused the time in `day` was.
    public static func focus(_ events: [ActivityEvent], in day: DateInterval, tagger: Tagger,
                             deepMinimum: TimeInterval = 25 * 60, calendar: Calendar = .current) -> FocusSummary {
        var summary = FocusSummary()
        var interruptions: [String: (name: String, count: Int)] = [:]

        for (_, events) in Dictionary(grouping: events, by: \.device) {
            var previous: (event: ActivityEvent, role: TagRole, end: Date)?
            for e in events {
                guard let span = clip(e, to: day) else { continue }
                let role = tagger.primary(for: e)?.role ?? .neutral
                summary.total += span.duration
                if role == .focus { summary.focusSeconds += span.duration }
                if role == .distraction { summary.distractionSeconds += span.duration }
                if let previous, previous.event.bundleID != e.bundleID,
                   span.start.timeIntervalSince(previous.end) <= 120 {
                    summary.switches += 1
                    summary.switchesByHour[calendar.component(.hour, from: span.start), default: 0] += 1
                    if previous.role == .focus, role != .focus {
                        var entry = interruptions[e.bundleID] ?? (e.appName, 0)
                        entry.count += 1
                        interruptions[e.bundleID] = entry
                    }
                }
                previous = (e, role, span.end)
            }
        }
        for block in blocks(events, in: day, tagger: tagger) where block.tag?.role == .focus && block.duration >= deepMinimum {
            summary.deepSeconds += block.duration
            summary.deepCount += 1
            summary.longestDeep = max(summary.longestDeep, block.duration)
        }
        summary.interrupters = interruptions
            .map { FocusSummary.Interrupter(bundleID: $0.key, appName: $0.value.name, count: $0.value.count) }
            .sorted { ($0.count, $1.appName) > ($1.count, $0.appName) }
        return summary
    }

    /// Compares a period with the one before it. `events` and
    /// `previousEvents` are the front records of the two periods.
    public static func review(_ events: [ActivityEvent], in range: DateInterval,
                              previous previousEvents: [ActivityEvent], in previousRange: DateInterval,
                              tagger: Tagger, calendar: Calendar = .current,
                              projects: ProjectResolver? = nil) -> PeriodReview {
        let current = report(events, in: range, tagger: tagger, calendar: calendar, projects: projects)
        let before = report(previousEvents, in: previousRange, tagger: tagger, calendar: calendar)
        var review = PeriodReview()
        review.total = current.total
        review.previousTotal = before.total
        review.topTag = current.byTag.first
        review.busiest = current.busiest
        review.topProject = current.projects.first

        if before.total > 0 {
            var deltas: [Int64: (tag: Tag?, delta: TimeInterval)] = [:]
            for t in current.byTag { deltas[t.id] = (t.tag, t.seconds) }
            for t in before.byTag { deltas[t.id] = (t.tag ?? deltas[t.id]?.tag, (deltas[t.id]?.delta ?? 0) - t.seconds) }
            let changes = deltas.values.filter { abs($0.delta) >= 600 }.map { PeriodReview.Change(tag: $0.tag, delta: $0.delta) }
            review.risers = changes.filter { $0.delta > 0 }.sorted { $0.delta > $1.delta }
            review.fallers = changes.filter { $0.delta < 0 }.sorted { $0.delta < $1.delta }

            let oldApps = Set(before.byApp.map(\.bundleID))
            review.newApps = current.byApp.filter { $0.seconds >= 300 && !oldApps.contains($0.bundleID) }.map(\.appName)
            let oldSites = Set(before.sites.map(\.label))
            review.newSites = current.sites.filter { $0.seconds >= 300 && !oldSites.contains($0.label) }.map(\.label)
        }

        // Focus, day by day, so that deep work is not joined across midnight.
        var switches = 0
        var day = calendar.startOfDay(for: range.start)
        while day < range.end {
            let next = calendar.date(byAdding: .day, value: 1, to: day) ?? day.addingTimeInterval(86_400)
            let span = DateInterval(start: max(day, range.start), end: min(next, range.end))
            let summary = focus(events.filter { $0.end > span.start && $0.start < span.end }, in: span,
                                tagger: tagger, calendar: calendar)
            review.deepSeconds += summary.deepSeconds
            switches += summary.switches
            if summary.deepSeconds > (review.bestFocusDay?.seconds ?? 0) {
                review.bestFocusDay = (day, summary.deepSeconds)
            }
            day = next
        }
        review.switchesPerHour = current.total >= 600 ? Double(switches) / (current.total / 3600) : 0
        var previousDay = calendar.startOfDay(for: previousRange.start)
        while previousDay < previousRange.end {
            let next = calendar.date(byAdding: .day, value: 1, to: previousDay) ?? previousDay.addingTimeInterval(86_400)
            let span = DateInterval(start: max(previousDay, previousRange.start), end: min(next, previousRange.end))
            review.previousDeepSeconds += focus(previousEvents.filter { $0.end > span.start && $0.start < span.end },
                                                in: span, tagger: tagger, calendar: calendar).deepSeconds
            previousDay = next
        }
        return review
    }

    /// For a goal, how many days in a row up to and including `today` (or
    /// yesterday, if today's goal is still open) it was met.
    public static func streak(for goal: Goal, days: [DayTotal], today: Date, calendar: Calendar = .current) -> Int {
        let spent = Dictionary(uniqueKeysWithValues: days.map { day in
            (day.day, day.byTag.first { $0.tag?.id == goal.tagID }?.seconds ?? 0)
        })
        var count = 0
        var day = calendar.startOfDay(for: today)
        // An unfinished today does not break a streak of earlier days. A day
        // with nothing recorded at all does.
        if !goal.isMet(by: spent[day] ?? 0) || (goal.kind == .atMost && (days.first { $0.day == day }?.total ?? 0) == 0) {
            day = calendar.date(byAdding: .day, value: -1, to: day) ?? day
        }
        while let total = days.first(where: { $0.day == day })?.total, total > 0, goal.isMet(by: spent[day] ?? 0) {
            count += 1
            day = calendar.date(byAdding: .day, value: -1, to: day) ?? day
        }
        return count
    }
}
