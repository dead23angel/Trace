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
        showsOnboarding = !defaults.bool(forKey: "onboarded")

        // Keep data in Application Support; fall back to memory if that fails
        // so the app still opens and can say what went wrong.
        var url: URL?
        var opened: EventStore?
        if let support = try? FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask,
                                                      appropriateFor: nil, create: true) {
            let folder = support.appendingPathComponent("Trace", isDirectory: true)
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
        reload()
        watcher.start()

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
        events = (try? store.events(from: interval.start, to: interval.end)) ?? []
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
        (try? store.events(from: range.start, to: range.end)) ?? []
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
