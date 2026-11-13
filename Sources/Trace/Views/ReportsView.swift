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
        "\(range.start.timeIntervalSince1970)-\(period.rawValue)-\(model.revision)"
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
                HStack(alignment: .top, spacing: 12) {
                    TrendCard(report: report, period: period, previousTotal: previousTotal)
                    TagSummaryCard(report: report).frame(minWidth: 300, maxWidth: 380)
                }
                .fixedSize(horizontal: false, vertical: true)
                HeatCard(report: report)
                HStack(alignment: .top, spacing: 12) {
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
        } else {
            previousTotal = 0
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
                            Text(period == .month || column.total == 0 ? " " : Fmt.duration(column.total))
                                .font(.system(size: period == .year ? 10 : 12))
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
