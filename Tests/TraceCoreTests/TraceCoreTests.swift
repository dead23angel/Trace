import XCTest
@testable import TraceCore

final class TraceCoreTests: XCTestCase {
    private let t0 = Date(timeIntervalSince1970: 1_800_000_000)

    private func xcode(_ file: String) -> Sample {
        Sample(bundleID: "com.apple.dt.Xcode", appName: "Xcode",
               category: "public.app-category.developer-tools",
               title: file, path: "/Users/me/Trace/\(file)")
    }

    func testHeartbeatExtendsSameSampleAndSplitsOnChange() throws {
        let store = try EventStore()
        try store.heartbeat(xcode("A.swift"), at: t0)
        try store.heartbeat(xcode("A.swift"), at: t0 + 2)
        try store.heartbeat(xcode("A.swift"), at: t0 + 4)
        try store.heartbeat(xcode("B.swift"), at: t0 + 6)

        let events = try store.events(from: t0 - 1, to: t0 + 100)
        XCTAssertEqual(events.count, 2)
        XCTAssertEqual(events[0].duration, 4, accuracy: 0.001)
        XCTAssertEqual(events[1].title, "B.swift")
    }

    func testHeartbeatStartsNewEventAfterLongGap() throws {
        let store = try EventStore()
        try store.heartbeat(xcode("A.swift"), at: t0)
        try store.heartbeat(xcode("A.swift"), at: t0 + 600)
        XCTAssertEqual(try store.eventCount(), 2)
    }

    func testTrimLastCutsIdleTail() throws {
        let store = try EventStore()
        try store.heartbeat(xcode("A.swift"), at: t0)
        try store.heartbeat(xcode("A.swift"), at: t0 + 10)
        try store.trimLast(to: t0 + 4)
        let events = try store.events(from: t0 - 1, to: t0 + 100)
        XCTAssertEqual(events[0].duration, 4, accuracy: 0.001)
    }

    func testPresetsTagByCategoryAndSiteBeforeBrowser() throws {
        let store = try EventStore()
        let tagger = try store.tagger()

        let dev = ActivityEvent(sample: xcode("A.swift"), start: t0, end: t0 + 60)
        XCTAssertEqual(tagger.primary(for: dev)?.key, "dev")

        let video = ActivityEvent(
            sample: Sample(bundleID: "com.apple.Safari", appName: "Safari",
                           title: "Video", url: "https://www.youtube.com/watch"),
            start: t0, end: t0 + 60)
        XCTAssertEqual(tagger.primary(for: video)?.key, "fun")
        XCTAssertEqual(tagger.tags(for: video).map(\.key), ["fun", "browse"])

        let plain = ActivityEvent(
            sample: Sample(bundleID: "com.apple.Safari", appName: "Safari",
                           title: "Example", url: "https://example.com/"),
            start: t0, end: t0 + 60)
        XCTAssertEqual(tagger.primary(for: plain)?.key, "browse")
    }

    func testCustomTagWinsOverPreset() throws {
        let store = try EventStore()
        try store.addTag(name: "Trace", colorIndex: 2, rule: (.path, .contains, "/Trace/"))
        let tagger = try store.tagger()
        let event = ActivityEvent(sample: xcode("A.swift"), start: t0, end: t0 + 60)
        XCTAssertEqual(tagger.primary(for: event)?.name, "Trace")
    }

    func testSummarySplitsAcrossHoursAndClipsToDay() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        let dayStart = calendar.startOfDay(for: t0)
        let day = DateInterval(start: dayStart, duration: 86_400)
        let store = try EventStore()
        let tagger = try store.tagger()

        // 09:30 to 10:30, plus an event that started the previous evening.
        let events = [
            ActivityEvent(sample: xcode("Late.swift"), start: dayStart - 1800, end: dayStart + 600),
            ActivityEvent(sample: xcode("A.swift"), start: dayStart + 9.5 * 3600, end: dayStart + 10.5 * 3600),
        ]
        let summary = Analyzer.summarize(events, in: day, tagger: tagger, calendar: calendar)

        XCTAssertEqual(summary.total, 600 + 3600, accuracy: 0.001)
        let hours = Dictionary(uniqueKeysWithValues: summary.hourly.map { ($0.hour, $0.seconds) })
        XCTAssertEqual(hours[0] ?? 0, 600, accuracy: 0.001)
        XCTAssertEqual(hours[9] ?? 0, 1800, accuracy: 0.001)
        XCTAssertEqual(hours[10] ?? 0, 1800, accuracy: 0.001)
        XCTAssertEqual(summary.byApp.first?.appName, "Xcode")
    }

    func testTreeDrillsFromTagToPage() throws {
        let store = try EventStore()
        let tagger = try store.tagger()
        let day = DateInterval(start: t0 - 10, duration: 86_400)
        let safari = { (title: String, url: String, start: TimeInterval, length: TimeInterval) in
            ActivityEvent(sample: Sample(bundleID: "com.apple.Safari", appName: "Safari", title: title, url: url),
                          start: self.t0 + start, end: self.t0 + start + length)
        }
        let events = [
            safari("AXUIElement", "https://developer.apple.com/documentation/a", 0, 120),
            safari("Accessibility", "https://developer.apple.com/documentation/b", 120, 60),
        ]
        let tree = Analyzer.tree(events, in: day, tagger: tagger, mode: .byTag)

        XCTAssertEqual(tree.count, 1)
        XCTAssertEqual(tree[0].tag?.key, "study")
        let site = tree[0].children?.first?.children?.first
        XCTAssertEqual(site?.label, "developer.apple.com")
        XCTAssertEqual(site?.seconds ?? 0, 180, accuracy: 0.001)
        XCTAssertEqual(site?.children?.map(\.label), ["AXUIElement", "Accessibility"])
    }

    func testBlocksMergeSameTagAcrossShortGaps() throws {
        let store = try EventStore()
        let tagger = try store.tagger()
        let day = DateInterval(start: t0 - 10, duration: 86_400)
        let events = [
            ActivityEvent(sample: xcode("A.swift"), start: t0, end: t0 + 600),
            ActivityEvent(sample: xcode("B.swift"), start: t0 + 660, end: t0 + 900),
            ActivityEvent(sample: xcode("C.swift"), start: t0 + 3000, end: t0 + 3300),
        ]
        let blocks = Analyzer.blocks(events, in: day, tagger: tagger)
        XCTAssertEqual(blocks.count, 2)
        XCTAssertEqual(blocks[0].events.count, 2)
        XCTAssertEqual(blocks[0].title, "Xcode · A.swift")
    }

    func testReportSumsDaysAndFillsHeatGrid() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        let store = try EventStore()
        let day1 = calendar.startOfDay(for: t0)
        let day3 = day1 + 2 * 86_400
        // 30 minutes at 09:00 on day 1, 90 minutes across 10:30-12:00 on day 3.
        try store.heartbeat(xcode("A.swift"), at: day1 + 9 * 3600)
        try store.heartbeat(xcode("A.swift"), at: day1 + 9 * 3600 + 10, pulse: 15)
        var events = try store.events(from: day1, to: day1 + 7 * 86_400)
        events[0].end = day1 + 9 * 3600 + 1800
        var second = events[0]
        second.id = 2
        second.start = day3 + 10 * 3600 + 1800
        second.end = day3 + 12 * 3600
        events.append(second)

        let range = DateInterval(start: day1, end: day1 + 7 * 86_400)
        let report = Analyzer.report(events, in: range, tagger: try store.tagger(), calendar: calendar)
        XCTAssertEqual(report.days.count, 7)
        XCTAssertEqual(report.total, 7200, accuracy: 0.001)
        XCTAssertEqual(report.activeDays, 2)
        XCTAssertEqual(report.dailyAverage, 3600, accuracy: 0.001)
        XCTAssertEqual(report.busiest?.day, day3)
        XCTAssertEqual(report.days[2].total, 5400, accuracy: 0.001)
        let weekday3 = calendar.component(.weekday, from: day3)
        let cell = report.heat.first { $0.weekday == weekday3 && $0.hour == 11 }
        XCTAssertEqual(cell?.seconds ?? 0, 3600, accuracy: 0.001)
        XCTAssertEqual(report.heat.reduce(0) { $0 + $1.seconds }, 7200, accuracy: 0.001)
    }

    func testAddAndDeleteRuleRetagsEvents() throws {
        let store = try EventStore()
        let tag = try store.addTag(name: "Thesis", colorIndex: 1)
        let event = ActivityEvent(sample: Sample(bundleID: "com.apple.TextEdit", appName: "TextEdit",
                                                 title: "draft.txt", path: "/Users/me/thesis/draft.txt"),
                                  start: t0, end: t0 + 60)
        XCTAssertNotEqual(try store.tagger().primary(for: event)?.id, tag.id)

        let rule = try XCTUnwrap(store.addRule(tagID: tag.id!, field: .path, op: .contains, value: " /thesis/ "))
        XCTAssertEqual(rule.value, "/thesis/")
        XCTAssertEqual(try store.tagger().primary(for: event)?.id, tag.id)
        XCTAssertNil(try store.addRule(tagID: tag.id!, field: .path, op: .contains, value: "  "))

        try store.deleteRule(id: rule.id!)
        XCTAssertNotEqual(try store.tagger().primary(for: event)?.id, tag.id)
    }

    func testMoveTagChangesPriority() throws {
        let store = try EventStore()
        let event = ActivityEvent(sample: xcode("A.swift"), start: t0, end: t0 + 60)
        let dev = try XCTUnwrap(store.tagger().primary(for: event))
        XCTAssertEqual(dev.key, "dev")

        let other = try XCTUnwrap(store.tags().first { $0.key == "office" })
        try store.addRule(tagID: other.id!, field: .path, op: .contains, value: "/Trace/")
        XCTAssertEqual(try store.tagger().primary(for: event)?.key, "dev")

        try store.moveTag(id: other.id!, by: -100)
        XCTAssertEqual(try store.tags().first?.key, "office")
        XCTAssertEqual(try store.tagger().primary(for: event)?.key, "office")
    }

    func testManualTagOverridesRules() throws {
        let store = try EventStore()
        try store.heartbeat(xcode("A.swift"), at: t0)
        let event = try XCTUnwrap(store.events(from: t0 - 1, to: t0 + 1).first)
        let dev = try XCTUnwrap(store.tags().first { $0.key == "dev" })
        let fun = try XCTUnwrap(store.tags().first { $0.key == "fun" })

        try store.setManualTag(eventID: event.id!, tagID: fun.id!)
        var tagger = try store.tagger()
        XCTAssertEqual(tagger.primary(for: event)?.key, "fun")
        XCTAssertEqual(tagger.tags(for: event).map(\.key), ["fun", "dev"])
        XCTAssertTrue(tagger.isManual(fun, for: event))
        XCTAssertFalse(tagger.isManual(dev, for: event))

        try store.setManualTag(eventID: event.id!, tagID: dev.id!, removed: true)
        tagger = try store.tagger()
        XCTAssertEqual(tagger.tags(for: event).map(\.key), ["fun"])

        try store.clearManualTag(eventID: event.id!, tagID: fun.id!)
        try store.clearManualTag(eventID: event.id!, tagID: dev.id!)
        XCTAssertEqual(try store.tagger().tags(for: event).map(\.key), ["dev"])
    }

    func testReportListsSitesFilesAndUntagged() throws {
        let store = try EventStore()
        let tagger = try store.tagger()
        let web = ActivityEvent(sample: Sample(bundleID: "com.apple.Safari", appName: "Safari", title: "Docs",
                                               url: "https://www.example.org/a"), start: t0, end: t0 + 120)
        let file = ActivityEvent(sample: xcode("A.swift"), start: t0 + 120, end: t0 + 180)
        let odd = ActivityEvent(sample: Sample(bundleID: "x.y.Odd", appName: "Odd"), start: t0 + 180, end: t0 + 200)
        let range = DateInterval(start: t0, end: t0 + 3600)
        let report = Analyzer.report([web, file, odd], in: range, tagger: tagger)
        XCTAssertEqual(report.sites.first?.label, "example.org")
        XCTAssertEqual(report.files.first?.label, "/Users/me/Trace/A.swift")

        let loose = Analyzer.untagged([web, file, odd], in: range, tagger: tagger)
        XCTAssertEqual(loose.map(\.label), ["Odd"])
        XCTAssertEqual(loose.first?.field, .app)
        XCTAssertEqual(loose.first?.value, "x.y.Odd")

        let runs = Analyzer.appRuns([web, file, odd], in: range, tagger: tagger)
        XCTAssertEqual(runs.map(\.appName), ["Safari", "Xcode", "Odd"])
    }

    func testCSVQuotesFields() throws {
        let store = try EventStore()
        let e = ActivityEvent(sample: Sample(bundleID: "a.b", appName: "App", title: "say \"hi\", ok"),
                              start: t0, end: t0 + 61)
        let csv = Analyzer.csv([e], tagger: try store.tagger())
        let lines = csv.split(separator: "\n")
        XCTAssertEqual(lines.count, 2)
        XCTAssertTrue(lines[1].contains(",61,\"App\",\"a.b\",\"say \"\"hi\"\", ok\","))
    }

    func testBlocksAbsorbBriefInterruptions() throws {
        let store = try EventStore()
        let tagger = try store.tagger()
        let day = DateInterval(start: t0 - 10, duration: 86_400)
        let mail = Sample(bundleID: "com.apple.mail", appName: "Mail", title: "Inbox")
        let events = [
            ActivityEvent(sample: xcode("A.swift"), start: t0, end: t0 + 600),
            ActivityEvent(sample: mail, start: t0 + 600, end: t0 + 620),
            ActivityEvent(sample: xcode("A.swift"), start: t0 + 620, end: t0 + 1200),
            ActivityEvent(sample: mail, start: t0 + 1200, end: t0 + 1800),
        ]
        let blocks = Analyzer.blocks(events, in: day, tagger: tagger)
        XCTAssertEqual(blocks.map { $0.tag?.key }, ["dev", "comm"])
        XCTAssertEqual(blocks[0].events.count, 3)
        XCTAssertEqual(blocks[0].duration, 1200, accuracy: 0.001)
    }

    func testDemoDataIsTaggedAndStopsAtNow() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        let day = calendar.startOfDay(for: t0)
        let now = day + 12 * 3600
        let events = DemoData.events(now: now, days: 7, calendar: calendar, home: "/Users/me")
        XCTAssertFalse(events.isEmpty)
        XCTAssertTrue(events.allSatisfy { $0.end <= now && $0.end > $0.start })

        let store = try EventStore()
        try store.insert(events)
        let tagger = try store.tagger()
        let today = try store.events(from: day, to: now)
        XCTAssertEqual(Set(today.compactMap { tagger.primary(for: $0)?.key }), ["dev", "comm"])
        XCTAssertEqual(today.first?.path, "/Users/me/Developer/Trace/Sources/Trace/Views/TimelineView.swift")
    }
}
