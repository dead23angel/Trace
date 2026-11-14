import AppKit
import TraceCore

/// Finds every app that is open right now, and whether one of its windows
/// can be seen.
///
/// The window list gives the owner and frame of each window without any
/// permission; titles and contents are not read.
enum OpenApps {
    struct App: Hashable {
        let bundleID: String
        let appName: String
        /// A window of the app is on screen and not fully covered.
        let isShowing: Bool
    }

    /// Always running, so only worth noting while one of its windows shows.
    private static let quiet: Set<String> = ["com.apple.finder"]

    @MainActor
    static func current(excluding excluded: Set<String>) -> Set<App> {
        let showing = showingProcesses()
        var result: Set<App> = []
        for app in NSWorkspace.shared.runningApplications where app.activationPolicy == .regular {
            guard let bundleID = app.bundleIdentifier, bundleID != Bundle.main.bundleIdentifier,
                  !excluded.contains(bundleID) else { continue }
            let isShowing = !app.isHidden && showing.contains(app.processIdentifier)
            if !isShowing && quiet.contains(bundleID) { continue }
            result.insert(App(bundleID: bundleID, appName: app.localizedName ?? bundleID, isShowing: isShowing))
        }
        return result
    }

    /// Processes with a normal window on the current desktop that is not
    /// entirely behind a single other window.
    private static func showingProcesses() -> Set<pid_t> {
        let options: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
        guard let list = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] else { return [] }
        var above: [CGRect] = []
        var result: Set<pid_t> = []
        // The list runs from the front window to the back.
        for window in list {
            guard (window[kCGWindowLayer as String] as? Int) == 0,
                  let pid = window[kCGWindowOwnerPID as String] as? pid_t,
                  let bounds = window[kCGWindowBounds as String] as? [String: Any],
                  let frame = CGRect(dictionaryRepresentation: bounds as CFDictionary),
                  frame.width >= 120, frame.height >= 80,
                  (window[kCGWindowAlpha as String] as? Double ?? 1) > 0.05 else { continue }
            if !above.contains(where: { $0.contains(frame) }) { result.insert(pid) }
            above.append(frame)
        }
        return result
    }
}
