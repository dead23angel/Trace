import AppKit

/// Keeps Trace a menu bar app that grows a Dock presence only while one of
/// its windows is open.
///
/// With a window open Trace is a regular app: Dock icon with the running
/// dot, app switcher, menus. Close the last window and it goes back to
/// living in the menu bar: no dot, no place in the app switcher, still
/// recording. It quits only when asked to from the menu bar panel or with
/// Command-Q.
final class AppDelegate: NSObject, NSApplicationDelegate {
    static private(set) var shared: AppDelegate?

    /// Opens the main window; set by the interface once it exists.
    var openMain: (() -> Void)?
    private var observers: [NSObjectProtocol] = []

    func applicationDidFinishLaunching(_ notification: Notification) {
        Self.shared = self
        let center = NotificationCenter.default
        observers.append(center.addObserver(forName: NSWindow.willCloseNotification, object: nil, queue: .main) { [weak self] note in
            guard let window = note.object as? NSWindow, Self.isAppWindow(window) else { return }
            // The window is still listed while it closes; look again afterwards.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { self?.leaveDockIfNoWindows(ignoring: window) }
        })
        observers.append(center.addObserver(forName: NSWindow.didBecomeKeyNotification, object: nil, queue: .main) { note in
            guard let window = note.object as? NSWindow, Self.isAppWindow(window),
                  NSApp.activationPolicy() != .regular else { return }
            NSApp.setActivationPolicy(.regular)
        })
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

    /// Clicking the Dock icon, or opening the app again from Finder or Spotlight.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showMain()
        return false
    }

    /// Brings the main window to the front, opening it if it was closed.
    func showMain() {
        NSApp.setActivationPolicy(.regular)
        if let window = NSApp.windows.first(where: { Self.isMain($0) }) {
            if window.isMiniaturized { window.deminiaturize(nil) }
            window.makeKeyAndOrderFront(nil)
        } else {
            openMain?()
        }
        NSApp.activate(ignoringOtherApps: true)
        // A window that is being created needs a moment before it can come forward.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            NSApp.windows.first(where: { Self.isMain($0) })?.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
        }
    }

    private func leaveDockIfNoWindows(ignoring closing: NSWindow) {
        let open = NSApp.windows.contains { $0 !== closing && Self.isAppWindow($0) && ($0.isVisible || $0.isMiniaturized) }
        if !open { NSApp.setActivationPolicy(.accessory) }
    }

    /// The main window or Settings, not the menu bar panel or a popover.
    private static func isAppWindow(_ window: NSWindow) -> Bool {
        window.styleMask.contains(.titled) && !(window is NSPanel) && window.canBecomeMain
    }

    private static func isMain(_ window: NSWindow) -> Bool {
        isAppWindow(window) && (window.identifier?.rawValue.contains("main") ?? false)
    }
}
