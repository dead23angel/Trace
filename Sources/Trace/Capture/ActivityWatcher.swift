import AppKit
import Combine
import TraceCore

/// Samples the frontmost app every couple of seconds and writes heartbeats to
/// the store. Idle time is not stored: it shows up as gaps between events.
@MainActor
final class ActivityWatcher: ObservableObject {
    @Published private(set) var current: Sample?
    @Published private(set) var isTrusted = AXReader.isTrusted
    @Published private(set) var isIdle = false
    @Published var isPaused = false {
        didSet {
            if isPaused { current = nil } else { resume?.invalidate() }
        }
    }

    /// When the current app, window and page were first seen together.
    @Published private(set) var currentSince: Date?

    /// Seconds without keyboard or mouse input before the user counts as away.
    var idleThreshold: TimeInterval = 180
    /// Bundle identifiers that are never recorded.
    var excluded: Set<String> = []
    var captureTitles = true
    var captureFiles = true
    var captureURLs = true
    private var resume: Timer?

    private let store: EventStore
    private let queue = DispatchQueue(label: "trace.watcher", qos: .utility)
    private var timer: Timer?
    private var busy = false
    private var categories: [String: String?] = [:]
    private var observer: NSObjectProtocol?
    private var lastWindow: (pid: pid_t, info: AXReader.WindowInfo)?

    private static let interval: TimeInterval = 2
    private static let ignored: Set<String> = ["com.apple.loginwindow", "com.apple.ScreenSaver.Engine"]
    private static let browsers: Set<String> = [
        "com.apple.Safari", "com.google.Chrome", "company.thebrowser.Browser", "org.mozilla.firefox",
        "com.microsoft.edgemac", "com.brave.Browser", "com.vivaldi.Vivaldi", "com.operasoftware.Opera",
    ]

    init(store: EventStore) {
        self.store = store
    }

    /// Shows `sample` as the current activity without recording anything.
    func showDemo(_ sample: Sample, since: Date) {
        current = sample
        currentSince = since
        isTrusted = true
    }

    func start() {
        guard timer == nil else { return }
        let timer = Timer(timeInterval: Self.interval, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tick() }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
        // Sample right away on app switches so short stays are not missed.
        observer = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.tick() }
        }
        tick()
    }

    /// Stops recording for `seconds`, then picks up again on its own.
    func pause(for seconds: TimeInterval) {
        isPaused = true
        resume?.invalidate()
        let timer = Timer(timeInterval: seconds, repeats: false) { [weak self] _ in
            Task { @MainActor in self?.isPaused = false }
        }
        RunLoop.main.add(timer, forMode: .common)
        resume = timer
    }

    private func tick() {
        let trusted = AXReader.isTrusted
        if trusted != isTrusted { isTrusted = trusted }
        guard !isPaused, !busy else { return }

        let now = Date()
        let anyInput = CGEventType(rawValue: ~0)!
        let idleSeconds = CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: anyInput)
        if idleSeconds >= idleThreshold {
            if !isIdle {
                isIdle = true
                current = nil
                // The last event kept growing while nobody was there; cut it back.
                let lastInput = now.addingTimeInterval(-idleSeconds)
                queue.async { [store] in try? store.trimLast(to: lastInput) }
            }
            return
        }
        if isIdle { isIdle = false }

        guard let app = NSWorkspace.shared.frontmostApplication,
              let bundleID = app.bundleIdentifier,
              !Self.ignored.contains(bundleID),
              bundleID != Bundle.main.bundleIdentifier else { return }
        if excluded.contains(bundleID) {
            if current != nil { current = nil }
            return
        }

        let pid = app.processIdentifier
        let name = app.localizedName ?? bundleID
        let category = category(for: bundleID, bundleURL: app.bundleURL)
        let isBrowser = Self.browsers.contains(bundleID)

        busy = true
        let pulse = Self.interval * 5
        let previous = lastWindow?.pid == pid ? lastWindow?.info : nil
        let (titles, files, urls) = (captureTitles, captureFiles, captureURLs)
        queue.async { [store] in
            let window = trusted
                ? AXReader.focusedWindow(pid: pid, isBrowser: isBrowser && urls, previous: previous) : .init()
            let sample = Sample(bundleID: bundleID, appName: name, category: category,
                                title: titles ? window.title : "",
                                path: files ? window.path : nil, url: urls ? window.url : nil)
            _ = try? store.heartbeat(sample, at: now, pulse: pulse)
            DispatchQueue.main.async {
                if self.current != sample { self.currentSince = now }
                self.current = sample
                self.lastWindow = (pid, window)
                self.busy = false
            }
        }
    }

    private func category(for bundleID: String, bundleURL: URL?) -> String? {
        if let cached = categories[bundleID] { return cached }
        let value = bundleURL.flatMap { Bundle(url: $0) }?
            .object(forInfoDictionaryKey: "LSApplicationCategoryType") as? String
        categories[bundleID] = value
        return value
    }
}
