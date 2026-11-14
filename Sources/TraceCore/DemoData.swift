import Foundation

/// Made-up activity for screenshots and for trying the interface without
/// recording anything real. Used when the app is started with `--demo`.
public enum DemoData {
    private struct Stay {
        let from: Int       // minutes after midnight
        let to: Int
        let sample: Sample
    }

    private static func app(_ bundleID: String, _ name: String, _ category: String? = nil,
                            title: String = "", path: String? = nil, url: String? = nil) -> Sample {
        Sample(bundleID: bundleID, appName: name, category: category, title: title, path: path, url: url)
    }

    /// One working day, as groups of stays that belong together.
    private static func day(home: String) -> [[Stay]] {
        let dev = "public.app-category.developer-tools"
        let project = "\(home)/Developer/Trace"
        func xcode(_ file: String, _ folder: String) -> Sample {
            let path = folder.isEmpty ? "\(project)/\(file)" : "\(project)/\(folder)/\(file)"
            return app("com.apple.dt.Xcode", "Xcode", dev, title: file, path: path)
        }
        let terminal = app("com.apple.Terminal", "Terminal", title: "Trace — swift build")
        func safari(_ title: String, _ url: String) -> Sample {
            app("com.apple.Safari", "Safari", title: title, url: url)
        }
        return [
            [Stay(from: 520, to: 580, sample: xcode("TimelineView.swift", "Sources/Trace/Views")),
             Stay(from: 580, to: 600, sample: terminal),
             Stay(from: 600, to: 615, sample: xcode("EventStore.swift", "Sources/TraceCore"))],
            [Stay(from: 615, to: 627, sample: app("com.apple.mail", "Mail", title: "Inbox")),
             Stay(from: 627, to: 640, sample: app("com.apple.MobileSMS", "Messages", title: "Design team"))],
            [Stay(from: 640, to: 700, sample: xcode("EventStore.swift", "Sources/TraceCore")),
             Stay(from: 700, to: 715, sample: safari("groue/GRDB.swift: A toolkit for SQLite databases",
                                                     "https://github.com/groue/GRDB.swift")),
             Stay(from: 715, to: 725, sample: safari("ActivityWatch/activitywatch",
                                                     "https://github.com/ActivityWatch/activitywatch"))],
            [Stay(from: 790, to: 819, sample: safari("Accessibility API",
                                                     "https://developer.apple.com/documentation/accessibility")),
             Stay(from: 819, to: 840, sample: safari("AXUIElement | Apple Developer Documentation",
                                                     "https://developer.apple.com/documentation/applicationservices/axuielement"))],
            [Stay(from: 840, to: 900, sample: app("us.zoom.xos", "zoom.us", title: "Weekly sync"))],
            [Stay(from: 900, to: 962, sample: app("com.microsoft.Word", "Microsoft Word", title: "Design notes.docx",
                                                  path: "\(home)/Documents/Handbook/Design notes.docx")),
             Stay(from: 962, to: 975, sample: app("com.apple.Notes", "Notes", "public.app-category.productivity",
                                                  title: "Release checklist")),
             Stay(from: 975, to: 1010, sample: app("com.microsoft.Word", "Microsoft Word", title: "Design notes.docx",
                                                   path: "\(home)/Documents/Handbook/Design notes.docx"))],
            [Stay(from: 1010, to: 1030, sample: app("com.apple.mail", "Mail", title: "Re: Release plan"))],
            [Stay(from: 1030, to: 1090, sample: xcode("TimelineView.swift", "Sources/Trace/Views")),
             Stay(from: 1090, to: 1100, sample: terminal),
             Stay(from: 1100, to: 1115, sample: xcode("Package.swift", ""))],
            [Stay(from: 1150, to: 1185, sample: safari("Platforms State of the Union",
                                                       "https://www.youtube.com/watch"))],
        ]
    }

    /// Sound and calls that ran alongside, as (from, to, bundle id, app, layer).
    private static let alongside: [(Int, Int, String, String, Layer)] = [
        (525, 612, "com.apple.Music", "Music", .audio),
        (642, 722, "com.apple.Music", "Music", .audio),
        (840, 900, "us.zoom.xos", "zoom.us", .mic),
        (840, 900, "us.zoom.xos", "zoom.us", .audio),
        (1032, 1112, "com.apple.Music", "Music", .audio),
        (1150, 1185, "com.apple.Safari", "Safari", .audio),
        (522, 1188, "com.apple.dt.Xcode", "Xcode", .visible),
        (522, 760, "com.apple.Safari", "Safari", .visible),
        (760, 1040, "com.apple.Safari", "Safari", .open),
        (1040, 1188, "com.apple.Safari", "Safari", .visible),
        (522, 640, "com.apple.mail", "Mail", .visible),
        (640, 1188, "com.apple.mail", "Mail", .open),
        (522, 1188, "com.apple.Music", "Music", .open),
        (835, 905, "us.zoom.xos", "zoom.us", .visible),
        (905, 1188, "us.zoom.xos", "zoom.us", .open),
    ]

    /// Background records to go with `events`, generated the same way.
    public static func background(now: Date = Date(), days: Int = 28, calendar: Calendar = .current) -> [ActivityEvent] {
        let today = calendar.startOfDay(for: now)
        var events: [ActivityEvent] = []
        for back in stride(from: days - 1, through: 0, by: -1) {
            guard let start = calendar.date(byAdding: .day, value: -back, to: today),
                  back == 0 || !calendar.isDateInWeekend(start) else { continue }
            let shift = back == 0 ? 0 : (back * 37) % 41 - 20
            for (index, item) in alongside.enumerated() where back == 0 || (back + index) % 4 != 0 {
                let from = start.addingTimeInterval(TimeInterval((item.0 + shift) * 60))
                let to = min(start.addingTimeInterval(TimeInterval((item.1 + shift) * 60)), now)
                guard to > from else { continue }
                var event = ActivityEvent(sample: Sample(bundleID: item.2, appName: item.3), start: from, end: to)
                event.layer = item.4.rawValue
                events.append(event)
            }
        }
        return events
    }

    /// Events for the `days` days up to and including the day of `now`.
    /// Nothing is generated after `now`. The same input gives the same output.
    public static func events(now: Date = Date(), days: Int = 28, calendar: Calendar = .current,
                              home: String = NSHomeDirectory()) -> [ActivityEvent] {
        let today = calendar.startOfDay(for: now)
        let groups = day(home: home)
        var events: [ActivityEvent] = []
        for back in stride(from: days - 1, through: 0, by: -1) {
            guard let start = calendar.date(byAdding: .day, value: -back, to: today) else { continue }
            let isWeekend = calendar.isDateInWeekend(start)
            // Earlier days are shifted and thinned so that no two look alike.
            let shift = back == 0 ? 0 : (back * 37) % 41 - 20
            for (index, group) in groups.enumerated() {
                if back > 0 {
                    if isWeekend && index != 3 && index != 8 { continue }
                    if !isWeekend && (back + index) % 5 == 0 { continue }
                }
                for stay in group {
                    let from = start.addingTimeInterval(TimeInterval((stay.from + shift) * 60))
                    let to = min(start.addingTimeInterval(TimeInterval((stay.to + shift) * 60)), now)
                    guard to > from else { continue }
                    events.append(ActivityEvent(sample: stay.sample, start: from, end: to))
                }
            }
        }
        return events
    }
}
