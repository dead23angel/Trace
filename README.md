# Trace

An open-source, local-only activity tracker for macOS. Trace sits in the menu bar and records which app, window, file and web page you are using, then shows where the day went.

Trace 是一款开源、数据只存本机的 macOS 活动记录工具。它驻留在菜单栏，记录你正在使用的应用、窗口、文件和网页，并告诉你一天的时间花在了哪里。

- **Automatic**: no timers to start. App, window title, document path and page URL are captured every two seconds and merged into stays.
- **Detailed timeline**: drill down tag › app › file or site › page, pick any stretch of the day to sum it up, or read the day record by record with an inspector for each one.
- **Reports**: a week, a month or a year at a glance, with the trend, active hours, top sites and files, and CSV export.
- **Tags**: built-in tags (Development, Office, Study, Communication, Entertainment, Games, Design, Browsing) apply automatically; add your own, edit every rule, and tag single records by hand.
- **Private**: everything is stored in a SQLite file on your Mac. Trace makes no network connections. Keystrokes and screen contents are never recorded, and URLs are stored without query strings.
- **Native**: SwiftUI, light and dark appearance, English and 简体中文.

## Requirements

macOS 14 or later. Building needs Xcode 16 or later (Swift 6 toolchain).

## Build and run

```bash
scripts/bundle.sh
open build/Trace.app
```

On first launch, grant Trace access under System Settings › Privacy & Security › Accessibility. Without it Trace still records which app is in front, but not window titles, file paths or URLs.

The default build is ad-hoc signed, so macOS asks for Accessibility access again after every rebuild. To avoid that, sign with a certificate of your own:

```bash
CODESIGN_IDENTITY="Apple Development: Your Name (TEAMID)" scripts/bundle.sh
```

Run the tests with `swift test`.

## How it works

| Part | Where | What it does |
|---|---|---|
| Capture | `Sources/Trace/Capture` | Reads the frontmost app from `NSWorkspace`, the focused window through the Accessibility API, and idle time from `CGEventSource`. |
| Storage | `Sources/TraceCore/EventStore.swift` | SQLite via [GRDB](https://github.com/groue/GRDB.swift). Consecutive identical samples extend one event (a heartbeat), so there is one row per stay. |
| Tagging | `Sources/TraceCore/Tagging.swift` | Rules match on app, app category, file path, URL or window title. Tags are computed when reading, so changing a rule re-tags history. |
| Analysis | `Sources/TraceCore/Analyzer.swift` | Day summary, week and month reports, sessions and the drill-down outline. |
| Interface | `Sources/Trace/Views` | SwiftUI. Colours and shared controls live in `Theme.swift`. |

Data lives at `~/Library/Application Support/Trace/trace.sqlite`. Idle time is not stored; it appears as gaps between events.

## Adding a language

Copy `Resources/zh-Hans.lproj` to `Resources/<code>.lproj`, translate the right-hand side of each line, and add the code to `CFBundleLocalizations` in `Support/Info.plist` and to `AppLanguage` in `Sources/Trace/Localization.swift`.

## Known limitations

- Watching a video without touching the keyboard or mouse counts as idle after the idle threshold.
- Private browsing windows are not detected yet and are recorded like any other window.
- Page URLs depend on what each browser exposes to the Accessibility API; Safari and Chromium-based browsers are covered, others may only report the window title.
- No app icon yet, and the build is not notarized, so it is meant to be built from source.

## License

MIT. See [LICENSE](LICENSE).
