import AppKit
import UserNotifications

/// Tells the user when a timed session is over.
enum Notifier {
    /// Asks for permission to show notifications, the first time it matters.
    static func prepare() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    static func post(title: String, body: String) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: UUID().uuidString,
                                                                     content: content, trigger: nil)) { error in
            // Without permission there is still a sound to mark the end.
            if error != nil { DispatchQueue.main.async { NSSound(named: "Glass")?.play() } }
        }
    }
}
