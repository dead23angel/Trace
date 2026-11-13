import SwiftUI
import TraceCore

extension ReportPeriod {
    var title: String {
        switch self {
        case .week: return L("Week")
        case .month: return L("Month")
        case .year: return L("Year")
        }
    }
}

/// A week, a month or a year at a glance: the trend, where the time went,
/// when in the day it falls, and the sites and files used most.
struct ReportsView: View {
    @EnvironmentObject private var model: AppModel
    @State private var report = RangeReport()
    @State private var previousTotal: TimeInterval = 0
    @State private var review: PeriodReview?

    private var period: ReportPeriod { model.reportPeriod }

    private var range: DateInterval {
        Calendar.current.dateInterval(of: period.component, for: model.reportAnchor)
            ?? DateInterval(start: model.reportAnchor, duration: 7 * 86_400)
    }

    private var isCurrent: Bool { range.contains(Date()) }

    private var rangeTitle: String {
        switch period {
        case .week: return "\(Fmt.monthDay(range.start)) – \(Fmt.monthDay(range.end.addingTimeInterval(-1)))"
        case .month: return Fmt.month(range.start)
        case .year: return Fmt.year(range.start)
        }
    }

    private var reloadKey: String {
        "\(range.start.timeIntervalSince1970)-\(period.rawValue)-\(model.revision)-\(model.deviceFilter ?? "*")-\(model.lastSync?.timeIntervalSince1970 ?? 0)"
    }

    var body: some View {
        Page {
            PageHeader(title: L("Reports"), subtitle: rangeTitle) {
                HStack(spacing: 4) {
                    IconButton(symbol: "chevron.left", label: L("Previous period")) { shift(-1) }
                    IconButton(symbol: "chevron.right", label: L("Next period")) { shift(1) }
                        .disabled(isCurrent)
                        .opacity(isCurrent ? 0.4 : 1)
                }
            } trailing: {
                Segmented(options: ReportPeriod.allCases.map { ($0, $0.title) }, selection: $model.reportPeriod)
                Button(L("Export CSV")) { model.exportCSV(range, name: rangeTitle) }
                    .buttonStyle(.trBordered)
                    .disabled(report.total == 0)
            }
            if report.total == 0 {
                Card { EmptyState(title: L("Nothing recorded in this period"),
                                  note: L("Pick another period with the arrows above."), symbol: "chart.bar")
                    .frame(minHeight: 420)
                }
            } else {
                if let review {
                    ReviewCard(review: review, period: period)
                }
                HStack(alignment: .top, spacing: 12) {
                    TrendCard(report: report, period: period, previousTotal: previousTotal)
                    TagSummaryCard(report: report).frame(minWidth: 300, maxWidth: 380)
                }
                .fixedSize(horizontal: false, vertical: true)
                if period == .year {
                    YearCalendarCard(report: report)
                }
                HeatCard(report: report)
                if !report.projects.isEmpty {
                    ProjectsCard(report: report)
                }
                HStack(alignment: .top, spacing: 12) {
                    if report.byDevice.count > 1 {
                        DeviceCard(report: report)
                    }
                    ListCard(title: L("Top sites"), rows: Array(report.sites.prefix(6)), mono: false,
                             empty: L("No web pages recorded"))
                    ListCard(title: L("Top files"), rows: report.files.prefix(6).map {
                        ItemTotal(label: Analyzer.abbreviate($0.label), seconds: $0.seconds)
                    }, mono: true, empty: L("No files recorded"))
                }
            }
        }
        .task(id: reloadKey) { load() }
    }

    private func shift(_ delta: Int) {
        guard let next = Calendar.current.date(byAdding: period.component, value: delta, to: model.reportAnchor),
              delta < 0 || next <= Date() else { return }
        model.reportAnchor = next
    }

    private func load() {
        let current = range
        report = model.report(for: current)
        if let before = Calendar.current.date(byAdding: period.component, value: -1, to: current.start),
           let previous = Calendar.current.dateInterval(of: period.component, for: before) {
            previousTotal = model.events(in: previous).reduce(0) { $0 + Analyzer.clipped($1, to: previous) }
            // A year of day-by-day focus is slow and reads poorly; review weeks and months.
            review = period == .year || report.total == 0 ? nil : model.review(for: current, previous: previous)
        } else {
            previousTotal = 0
            review = nil
        }
    }
}

/// One capsule per day (or per month for a year), filled by tag.
private struct TrendCard: View {
    let report: RangeReport
    let period: ReportPeriod
    let previousTotal: TimeInterval

    private struct Column: Identifiable {
        let id: Int
        let label: String
        let total: TimeInterval
        let byTag: [(tag: Tag?, seconds: TimeInterval)]
        let isNow: Bool
    }

    private var columns: [Column] {
        let calendar = Calendar.current
        if period == .year {
            let symbols = Fmt.shortMonths
            return (1...12).map { month in
                let days = report.days.filter { calendar.component(.month, from: $0.day) == month }
                var tags: [Int64: (Tag?, TimeInterval)] = [:]
                for day in days {
                    for t in day.byTag { tags[t.id] = (t.tag, (tags[t.id]?.1 ?? 0) + t.seconds) }
                }
                return Column(id: month, label: symbols[month - 1], total: days.reduce(0) { $0 + $1.total },
                              byTag: tags.values.map { ($0.0, $0.1) },
                              isNow: days.contains { calendar.isDateInToday($0.day) })
            }
        }
        return report.days.enumerated().map { index, day in
            let number = calendar.component(.day, from: day.day)
            let label = period == .week ? Fmt.weekday(day.day) : (number == 1 || number % 5 == 0 ? "\(number)" : "")
            return Column(id: index, label: label, total: day.total,
                          byTag: day.byTag.map { ($0.tag, $0.seconds) }, isNow: calendar.isDateInToday(day.day))
        }
    }

    private var title: String {
        switch period {
        case .week: return L("Daily time this week")
        case .month: return L("Daily time this month")
        case .year: return L("Monthly time this year")
        }
    }

    private var note: String {
        var parts = [L("Daily average") + " " + Fmt.duration(report.dailyAverage)]
        if previousTotal > 0 {
            let percent = Int(((report.total - previousTotal) / previousTotal * 100).rounded())
            parts.append(String(format: L("%@ vs previous period"), percent >= 0 ? "+\(percent)%" : "\(percent)%"))
        }
        return parts.joined(separator: " · ")
    }

    var body: some View {
        let columns = columns
        let peak = max(columns.map(\.total).max() ?? 1, 1)
        // Round the scale up so the tallest column is not flush with the top.
        let ceiling = peak * 1.08
        let width: CGFloat = period == .month ? 12 : 28
        Card(padding: .hv(20, 18)) {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .firstTextBaseline, spacing: 12) {
                    Text(title).font(.system(size: 14, weight: .semibold))
                    Text(Fmt.duration(report.total)).font(.system(size: 26, weight: .bold)).tracking(-0.5)
                    Text(note).font(.system(size: 12)).foregroundStyle(Theme.muted).lineLimit(1)
                }
                HStack(alignment: .bottom, spacing: 0) {
                    ForEach(columns) { column in
                        VStack(spacing: 6) {
                            Text(period == .month || column.total == 0 ? " "
                                 : (period == .year ? Fmt.hours(column.total) : Fmt.duration(column.total)))
                                .font(.system(size: 12))
                                .foregroundStyle(Theme.muted)
                                .lineLimit(1)
                                .minimumScaleFactor(0.7)
                            PillColumn(segments: column.byTag
                                .sorted { ($0.tag?.sortOrder ?? .max) < ($1.tag?.sortOrder ?? .max) }
                                .map { (fraction: $0.seconds / ceiling, color: Palette.color($0.tag)) },
                                width: width, height: 200)
                            Text(column.label.isEmpty ? " " : column.label)
                                .font(.system(size: 12, weight: column.isNow ? .bold : .regular))
                                .foregroundStyle(column.isNow ? Theme.accent : Theme.muted)
                                .lineLimit(1)
                                .fixedSize()
                        }
                        .frame(maxWidth: .infinity)
                        .help(column.total > 0 ? Fmt.duration(column.total) : "")
                    }
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(title)
            }
        }
    }
}

private struct TagSummaryCard: View {
    let report: RangeReport

    var body: some View {
        let top = report.byTag.first?.seconds ?? 1
        Card(padding: .hv(20, 18)) {
            VStack(alignment: .leading, spacing: 12) {
                SectionTitle(title: L("By tag"))
                ForEach(report.byTag.prefix(8)) { total in
                    VStack(spacing: 5) {
                        HStack(spacing: 8) {
                            Swatch(total.tag, size: 9)
                            Text(tagName(total.tag)).lineLimit(1)
                            Spacer(minLength: 8)
                            Text(Fmt.duration(total.seconds)).foregroundStyle(Theme.muted)
                            Text("\(Int((total.seconds / max(report.total, 1) * 100).rounded()))%")
                                .fontWeight(.semibold)
                                .frame(width: 36, alignment: .trailing)
                        }
                        Meter(fraction: total.seconds / top, color: Palette.color(total.tag))
                    }
                }
                Spacer(minLength: 0)
            }
        }
    }
}

/// Hour of day against day of week; darker means more time.
private struct HeatCard: View {
    let report: RangeReport

    var body: some View {
        var calendar = Calendar.current
        calendar.locale = L10n.locale
        let symbols = calendar.shortWeekdaySymbols
        let weekdays = (0..<7).map { (calendar.firstWeekday - 1 + $0) % 7 + 1 }
        let cells = Dictionary(uniqueKeysWithValues: report.heat.map { ($0.id, $0.seconds) })
        let peak = max(report.heat.map(\.seconds).max() ?? 0, 1)

        return Card(padding: .hv(20, 18)) {
            VStack(alignment: .leading, spacing: 12) {
                SectionTitle(title: L("Active hours"), note: L("The darker the cell, the fuller that hour was"))
                VStack(spacing: 4) {
                    ForEach(weekdays, id: \.self) { weekday in
                        HStack(spacing: 8) {
                            Text(symbols[weekday - 1])
                                .font(.system(size: 12))
                                .foregroundStyle(Theme.muted)
                                .frame(width: 32, alignment: .leading)
                            HStack(spacing: 3) {
                                ForEach(0..<24, id: \.self) { hour in
                                    let seconds = cells[weekday * 24 + hour] ?? 0
                                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                                        .fill(seconds > 0 ? Theme.accent.opacity(0.2 + 0.8 * seconds / peak) : Theme.bg)
                                        .frame(maxWidth: .infinity)
                                        .frame(height: 20)
                                        .help("\(symbols[weekday - 1]) \(String(format: "%02d:00", hour)) · \(Fmt.duration(seconds))")
                                }
                            }
                        }
                    }
                    HStack(spacing: 8) {
                        Color.clear.frame(width: 32, height: 1)
                        HStack {
                            ForEach(["00", "06", "12", "18", "24"], id: \.self) { label in
                                Text(label)
                                if label != "24" { Spacer() }
                            }
                        }
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.muted)
                    }
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(L("Active hours"))
            }
        }
    }
}

/// A few sentences on what stands out in the period.
private struct ReviewCard: View {
    @EnvironmentObject private var model: AppModel
    let review: PeriodReview
    let period: ReportPeriod

    private var before: String { period == .week ? L("the week before") : L("the month before") }

    private struct Line: Identifiable {
        let id: Int
        let symbol: String
        let text: String
    }

    private var lines: [Line] {
        var texts: [(String, String)] = []
        if review.previousTotal > 0 {
            let diff = review.total - review.previousTotal
            let percent = Int((abs(diff) / review.previousTotal * 100).rounded())
            texts.append(("clock", String(format: diff >= 0 ? L("%1$@ tracked, %2$@ more than %3$@ (+%4$d%%).")
                                                              : L("%1$@ tracked, %2$@ less than %3$@ (−%4$d%%)."),
                                           Fmt.duration(review.total), Fmt.duration(abs(diff)), before, percent)))
        } else {
            texts.append(("clock", String(format: L("%@ tracked."), Fmt.duration(review.total))))
        }
        if let top = review.topTag, review.total > 0 {
            texts.append(("tag", String(format: L("Most of it went to %1$@: %2$@, %3$d%% of the total."), tagName(top.tag),
                                         Fmt.duration(top.seconds), Int((top.seconds / review.total * 100).rounded()))))
        }
        if let up = review.risers.first {
            var text = String(format: L("%1$@ grew by %2$@"), tagName(up.tag), Fmt.duration(up.delta))
            if let down = review.fallers.first {
                text += L("; ") + String(format: L("%1$@ shrank by %2$@"), tagName(down.tag), Fmt.duration(-down.delta))
            }
            texts.append(("arrow.up.arrow.down", text + L(".")))
        } else if let down = review.fallers.first {
            texts.append(("arrow.up.arrow.down",
                          String(format: L("%1$@ shrank by %2$@"), tagName(down.tag), Fmt.duration(-down.delta)) + L(".")))
        }
        if review.deepSeconds > 0 {
            var text = String(format: L("%@ of deep work"), Fmt.duration(review.deepSeconds))
            if review.previousDeepSeconds > 0 {
                text += String(format: L(" (%1$@ %2$@)"), before, Fmt.duration(review.previousDeepSeconds))
            }
            if let best = review.bestFocusDay {
                text += L("; ") + String(format: L("the most focused day was %1$@ with %2$@"), Fmt.day(best.day), Fmt.duration(best.seconds))
            }
            texts.append(("scope", text + L(".")))
        }
        if let busiest = review.busiest {
            var text = String(format: L("The busiest day was %1$@ with %2$@"), Fmt.day(busiest.day), Fmt.duration(busiest.total))
            if review.switchesPerHour >= 1 {
                text += L("; ") + String(format: L("you switched apps about %d times an hour"), Int(review.switchesPerHour.rounded()))
            }
            texts.append(("calendar", text + L(".")))
        }
        if let project = review.topProject {
            texts.append(("folder", String(format: L("The project you spent the most time in was %1$@: %2$@."),
                                           project.label, Fmt.duration(project.seconds))))
        }
        let fresh = Array(review.newApps.prefix(4)) + Array(review.newSites.prefix(4))
        if !fresh.isEmpty {
            texts.append(("sparkles", String(format: L("New this time: %@."), fresh.joined(separator: L(", ")))))
        }
        return texts.enumerated().map { Line(id: $0.offset, symbol: $0.element.0, text: $0.element.1) }
    }

    var body: some View {
        Card(padding: .hv(20, 16)) {
            VStack(alignment: .leading, spacing: 10) {
                SectionTitle(title: period == .week ? L("This week in review") : L("This month in review"))
                LazyVGrid(columns: [GridItem(.flexible(), spacing: 24, alignment: .topLeading),
                                    GridItem(.flexible(), spacing: 24, alignment: .topLeading)],
                          alignment: .leading, spacing: 8) {
                    ForEach(lines) { line in
                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            Image(systemName: line.symbol)
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(Theme.accent)
                                .frame(width: 16)
                            Text(line.text).fixedSize(horizontal: false, vertical: true)
                            Spacer(minLength: 0)
                        }
                    }
                }
            }
        }
    }
}

/// Time per project, found from the folders of the files that were open.
private struct ProjectsCard: View {
    let report: RangeReport

    var body: some View {
        let rows = Array(report.projects.prefix(8))
        let top = rows.first?.seconds ?? 1
        Card {
            VStack(alignment: .leading, spacing: 12) {
                SectionTitle(title: L("Projects"), note: L("Found from the folder each file is in"))
                LazyVGrid(columns: [GridItem(.flexible(), spacing: 28), GridItem(.flexible(), spacing: 28)], spacing: 10) {
                    ForEach(rows) { row in
                        VStack(spacing: 5) {
                            HStack(spacing: 8) {
                                Image(systemName: "folder.fill").font(.system(size: 11)).foregroundStyle(Theme.accent)
                                Text(row.label).lineLimit(1)
                                Spacer(minLength: 8)
                                Text(Fmt.duration(row.seconds)).foregroundStyle(Theme.muted)
                            }
                            Meter(fraction: row.seconds / top, color: Theme.accent)
                        }
                    }
                }
            }
        }
    }
}

/// The whole year, one square per day; click a day to open it.
private struct YearCalendarCard: View {
    @EnvironmentObject private var model: AppModel
    let report: RangeReport

    var body: some View {
        var calendar = Calendar.current
        calendar.locale = L10n.locale
        let days = report.days
        let peak = max(days.map(\.total).max() ?? 0, 1)
        // Columns are weeks; pad the first one so that weekdays line up.
        let lead = days.first.map { (calendar.component(.weekday, from: $0.day) - calendar.firstWeekday + 7) % 7 } ?? 0
        let slots: [DayTotal?] = Array(repeating: nil, count: lead) + days.map { Optional($0) }
        let weeks = stride(from: 0, to: slots.count, by: 7).map { Array(slots[$0..<min($0 + 7, slots.count)]) }
        let months = Fmt.shortMonths
        let today = calendar.startOfDay(for: Date())

        return Card(padding: .hv(20, 18)) {
            VStack(alignment: .leading, spacing: 10) {
                SectionTitle(title: L("Every day of the year"), note: L("Click a day to open it"))
                HStack(alignment: .top, spacing: 3) {
                    ForEach(Array(weeks.enumerated()), id: \.offset) { _, week in
                        VStack(spacing: 3) {
                            // The month name sits above the week in which the month starts.
                            let starts = week.compactMap { $0 }.first { calendar.component(.day, from: $0.day) == 1 }
                            Text(starts.map { months[calendar.component(.month, from: $0.day) - 1] } ?? " ")
                                .font(.system(size: 10))
                                .foregroundStyle(Theme.muted)
                                .fixedSize()
                                .frame(width: 4, height: 12, alignment: .leading)
                            ForEach(0..<7, id: \.self) { index in
                                if index < week.count, let day = week[index] {
                                    let isFuture = day.day > today
                                    Button {
                                        model.day = day.day
                                        model.pane = .overview
                                    } label: {
                                        RoundedRectangle(cornerRadius: 3, style: .continuous)
                                            .fill(day.total > 0 ? Theme.accent.opacity(0.22 + 0.78 * day.total / peak) : Theme.bg)
                                            .aspectRatio(1, contentMode: .fit)
                                            .overlay(RoundedRectangle(cornerRadius: 3, style: .continuous)
                                                .strokeBorder(calendar.isDate(day.day, inSameDayAs: today) ? Theme.ink : .clear, lineWidth: 1.5))
                                    }
                                    .buttonStyle(.plain)
                                    .disabled(isFuture)
                                    .opacity(isFuture ? 0.4 : 1)
                                    .help("\(Fmt.day(day.day)) · \(Fmt.duration(day.total))")
                                } else {
                                    Color.clear.aspectRatio(1, contentMode: .fit)
                                }
                            }
                        }
                        .frame(maxWidth: .infinity)
                    }
                }
                .accessibilityElement(children: .contain)
                .accessibilityLabel(L("Every day of the year"))
            }
        }
    }
}

/// How the period's time splits between Macs.
private struct DeviceCard: View {
    @EnvironmentObject private var model: AppModel
    let report: RangeReport

    var body: some View {
        let top = report.byDevice.first?.seconds ?? 1
        Card {
            VStack(alignment: .leading, spacing: 12) {
                SectionTitle(title: L("By Mac"))
                ForEach(report.byDevice) { item in
                    VStack(spacing: 5) {
                        HStack(spacing: 8) {
                            Image(systemName: "laptopcomputer").font(.system(size: 11)).foregroundStyle(Theme.muted)
                            Text(model.deviceName(forDevice: item.label)).lineLimit(1)
                            Spacer(minLength: 8)
                            Text(Fmt.duration(item.seconds)).foregroundStyle(Theme.muted)
                            Text("\(Int((item.seconds / max(report.total, 1) * 100).rounded()))%")
                                .fontWeight(.semibold)
                                .frame(width: 36, alignment: .trailing)
                        }
                        Meter(fraction: item.seconds / top, color: Theme.accent)
                    }
                }
            }
        }
    }
}

private struct ListCard: View {
    let title: String
    let rows: [ItemTotal]
    let mono: Bool
    let empty: String

    var body: some View {
        Card {
            VStack(alignment: .leading, spacing: 0) {
                SectionTitle(title: title).padding(.bottom, 8)
                if rows.isEmpty {
                    Hairline()
                    Text(empty).foregroundStyle(Theme.muted).padding(.vertical, 8)
                }
                ForEach(rows) { row in
                    Hairline()
                    HStack(spacing: 12) {
                        Text(row.label).font(mono ? Theme.mono : .system(size: 13)).lineLimit(1).truncationMode(.head)
                        Spacer(minLength: 8)
                        Text(Fmt.duration(row.seconds)).foregroundStyle(Theme.muted)
                    }
                    .padding(.vertical, 8)
                }
            }
        }
    }
}
