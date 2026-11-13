import Charts
import SwiftUI
import TraceCore

struct OverviewView: View {
    @EnvironmentObject private var model: AppModel

    private enum Span: Hashable { case day, week, month }

    var body: some View {
        Page {
            header
            if model.events.isEmpty {
                Card { EmptyState(title: L("No activity recorded"),
                                  note: L("Trace records the app, window, file and page you are using. Keep it running and check back in a few minutes."))
                    .frame(minHeight: 420)
                }
            } else {
                HStack(alignment: .top, spacing: 12) {
                    HeroCard().frame(minWidth: 340, maxWidth: 440)
                    HourlyCard()
                }
                .fixedSize(horizontal: false, vertical: true)
                GoalsCard()
                DayLanesCard()
                HStack(alignment: .top, spacing: 12) {
                    VStack(spacing: 12) {
                        FocusCard()
                        TopAppsCard()
                    }
                    .frame(minWidth: 300, maxWidth: 400)
                    ActivityCard()
                }
            }
        }
    }

    private var header: some View {
        PageHeader(title: Fmt.day(model.day), pill: model.isToday ? L("Today") : "") {
            HStack(spacing: 4) {
                IconButton(symbol: "chevron.left", label: L("Previous day")) { model.shiftDay(-1) }
                IconButton(symbol: "chevron.right", label: L("Next day")) { model.shiftDay(1) }
                    .disabled(model.isToday)
                    .opacity(model.isToday ? 0.4 : 1)
            }
        } trailing: {
            if !model.isToday {
                Button(L("Back to today")) { model.goToToday() }.buttonStyle(.trLink)
            }
            Segmented(options: [(Span.day, L("Day")), (.week, L("Week")), (.month, L("Month"))],
                      selection: Binding(get: { Span.day }, set: { span in
                          if span == .week { model.showReport(.week) }
                          if span == .month { model.showReport(.month) }
                      }))
            SearchField(text: $model.query, placeholder: L("Search activity"), width: 150)
        }
    }
}

private struct HeroCard: View {
    @EnvironmentObject private var model: AppModel

    private var longestFocus: TimeInterval { model.blocks.map(\.duration).max() ?? 0 }

    private var delta: String? {
        guard model.yesterdayTotal > 0 else { return nil }
        let diff = model.summary.total - model.yesterdayTotal
        guard abs(diff) >= 60 else { return nil }
        return String(format: diff > 0 ? L("%@ more than the day before") : L("%@ less than the day before"),
                      Fmt.duration(abs(diff)))
    }

    var body: some View {
        let summary = model.summary
        Card(padding: .hv(20, 18)) {
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 20) {
                    ZStack {
                        Chart(summary.byTag) { total in
                            SectorMark(angle: .value("Time", total.seconds),
                                       innerRadius: .ratio(0.72), angularInset: 1.2)
                                .cornerRadius(2)
                                .foregroundStyle(Palette.color(total.tag))
                        }
                        .chartLegend(.hidden)
                        if let top = summary.byTag.first, summary.total > 0 {
                            VStack(spacing: 0) {
                                Text(tagName(top.tag)).font(.system(size: 11)).foregroundStyle(Theme.muted).lineLimit(1)
                                Text("\(Int((top.seconds / summary.total * 100).rounded()))%")
                                    .font(.system(size: 18, weight: .bold))
                            }
                            .frame(width: 74)
                        }
                    }
                    .frame(width: 132, height: 132)
                    .accessibilityLabel(L("Share of the day by tag"))

                    VStack(alignment: .leading, spacing: 2) {
                        Text(model.isToday ? L("Tracked today") : L("Tracked"))
                            .font(.system(size: 12))
                            .foregroundStyle(Theme.muted)
                        Text(Fmt.duration(summary.total))
                            .font(.system(size: 34, weight: .bold))
                            .tracking(-0.6)
                            .lineLimit(1)
                            .minimumScaleFactor(0.6)
                        if let delta {
                            Text(delta).font(.system(size: 12, weight: .semibold)).foregroundStyle(Theme.accent)
                        } else if let first = summary.first, let last = summary.last {
                            Text("\(Fmt.time(first)) – \(Fmt.time(last))")
                                .font(.system(size: 12))
                                .foregroundStyle(Theme.muted)
                        }
                    }
                }
                Hairline()
                HStack(alignment: .top, spacing: 8) {
                    stat(L("Longest focus"), Fmt.duration(longestFocus))
                    stat(L("Most used app"), summary.byApp.first?.appName ?? "–")
                    stat(L("Away"), Fmt.duration(model.away))
                }
            }
        }
    }

    private func stat(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.system(size: 12)).foregroundStyle(Theme.muted)
            Text(value).font(.system(size: 16, weight: .bold)).lineLimit(1).minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// One capsule per hour, filled by tag.
private struct HourlyCard: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        let scale = DayScale(day: model.day, first: model.summary.first, last: model.summary.last)
        let hours = Array(scale.hours.lowerBound..<scale.hours.upperBound)
        let byHour = Dictionary(grouping: model.summary.hourly, by: \.hour)
        Card(padding: .hv(20, 18)) {
            VStack(alignment: .leading, spacing: 12) {
                SectionTitle(title: L("By hour"), note: L("60 minutes per column, stacked by tag"))
                HStack(alignment: .bottom, spacing: 0) {
                    ForEach(hours, id: \.self) { hour in
                        VStack(spacing: 6) {
                            // Two Macs in use at once can add up to more than an hour.
                            let full = max(3600, (byHour[hour] ?? []).reduce(0) { $0 + $1.seconds })
                            PillColumn(segments: (byHour[hour] ?? []).map {
                                (fraction: $0.seconds / full, color: Palette.color($0.tag))
                            })
                            Text(String(format: "%02d", hour)).font(.system(size: 11)).foregroundStyle(Theme.muted)
                        }
                        .frame(maxWidth: .infinity)
                        .help("\(String(format: "%02d:00", hour)) · \(Fmt.duration((byHour[hour] ?? []).reduce(0) { $0 + $1.seconds }))")
                    }
                }
                .frame(maxHeight: .infinity, alignment: .bottom)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(L("Tracked time per hour, stacked by tag"))
            }
        }
    }
}

/// The day as two lanes: sessions by tag, and the apps underneath.
private struct DayLanesCard: View {
    @EnvironmentObject fileprivate var model: AppModel

    var body: some View {
        let scale = DayScale(day: model.day, first: model.summary.first, last: model.summary.last)
        let sound = pieces(.audio, scale)
        let calls = pieces(.mic, scale)
        Card(padding: EdgeInsets(top: 16, leading: 20, bottom: 18, trailing: 20)) {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    SectionTitle(title: L("Timeline"))
                    Button(L("Open as lanes")) { model.timelineMode = .gantt; model.pane = .timeline }
                        .buttonStyle(.trLink).font(.system(size: 12))
                    Spacer()
                    Legend(tags: model.summary.byTag.prefix(6).map(\.tag))
                }
                HStack(alignment: .top, spacing: 12) {
                    VStack(alignment: .leading, spacing: 8) {
                        Color.clear.frame(height: 14)
                        Text(L("Tag")).frame(height: 26)
                        Text(L("App")).frame(height: 16)
                        if !sound.isEmpty { Text(L("Sound")).frame(height: 10) }
                        if !calls.isEmpty { Text(L("Calls")).frame(height: 10) }
                    }
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.muted)
                    .frame(width: 44, alignment: .leading)

                    VStack(spacing: 8) {
                        HStack {
                            let labels = scale.labels()
                            ForEach(labels, id: \.self) { hour in
                                Text(String(format: "%02d", hour))
                                if hour != labels.last { Spacer() }
                            }
                        }
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.muted)
                        .frame(height: 14)
                        .accessibilityHidden(true)

                        Lane(pieces: model.blocks.enumerated().map { index, block in
                            .init(id: index, start: scale.fraction(block.start), length: scale.length(block.duration),
                                  color: Palette.color(block.tag),
                                  tip: "\(tagName(block.tag)) · \(Fmt.time(block.start)) – \(Fmt.time(block.end)) · \(block.title)")
                        }, height: 26)
                        .accessibilityLabel(L("Timeline of the day by tag"))

                        Lane(pieces: model.appRuns.enumerated().map { index, run in
                            .init(id: index, start: scale.fraction(run.start),
                                  length: scale.length(run.end.timeIntervalSince(run.start)),
                                  color: Palette.color(run.tag),
                                  tip: "\(run.appName) · \(Fmt.time(run.start)) – \(Fmt.time(run.end))", opacity: 0.5)
                        }, height: 16, radius: 4)
                        .accessibilityLabel(L("Timeline of the day by app"))

                        if !sound.isEmpty {
                            Lane(pieces: sound, height: 10, radius: 3).accessibilityLabel(L("When sound was playing"))
                        }
                        if !calls.isEmpty {
                            Lane(pieces: calls, height: 10, radius: 3).accessibilityLabel(L("When the microphone was in use"))
                        }
                    }
                }
            }
        }
    }
}

extension DayLanesCard {
    /// Background records of one layer as lane pieces.
    fileprivate func pieces(_ layer: Layer, _ scale: DayScale) -> [Lane.Piece] {
        model.background.filter { $0.layer == layer.rawValue && $0.duration >= 20 }.enumerated().map { index, event in
            let start = max(event.start, model.dayInterval.start), end = min(event.end, model.dayInterval.end)
            return .init(id: index, start: scale.fraction(start), length: scale.length(end.timeIntervalSince(start)),
                         color: Palette.color(model.tagger.primary(for: event)),
                         tip: "\(event.appName) · \(Fmt.time(start)) – \(Fmt.time(end))", opacity: 0.45)
        }
    }
}

private struct TopAppsCard: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        let apps = Array(model.summary.byApp.prefix(6))
        let top = apps.first?.seconds ?? 1
        Card {
            VStack(alignment: .leading, spacing: 12) {
                SectionTitle(title: L("Top apps"))
                ForEach(apps) { app in
                    VStack(spacing: 5) {
                        HStack(spacing: 8) {
                            AppIcon(bundleID: app.bundleID, size: 18)
                            Text(app.appName).lineLimit(1)
                            Spacer(minLength: 8)
                            Text(Fmt.duration(app.seconds)).foregroundStyle(Theme.muted)
                        }
                        Meter(fraction: app.seconds / top, color: Palette.color(app.tag))
                    }
                }
            }
        }
    }
}

private struct ActivityCard: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        let rows = model.events.filter { $0.duration >= 5 && model.passesFilter($0) }.suffix(6).reversed()
        Card {
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    SectionTitle(title: L("Activity log"))
                    Spacer()
                    Button(L("View all")) { model.showRecords() }.buttonStyle(.trLink).font(.system(size: 12))
                }
                .padding(.bottom, 8)
                if rows.isEmpty {
                    Text(L("No matching records")).foregroundStyle(Theme.muted).padding(.vertical, 12)
                }
                ForEach(Array(rows)) { event in
                    Hairline()
                    Button { model.showRecords(event: event.id) } label: { row(event) }
                        .buttonStyle(.plain)
                }
            }
        }
    }

    private func row(_ event: ActivityEvent) -> some View {
        HStack(spacing: 12) {
            Text(Fmt.time(event.start)).foregroundStyle(Theme.muted).frame(width: 42, alignment: .leading)
            AppIcon(bundleID: event.bundleID, size: 22)
            VStack(alignment: .leading, spacing: 0) {
                Text(event.headline).fontWeight(.semibold).lineLimit(1)
                if let detail = event.detail {
                    Text(detail).font(Theme.mono).foregroundStyle(Theme.muted).lineLimit(1).truncationMode(.middle)
                }
            }
            Spacer(minLength: 8)
            TagChip(tag: model.tagger.primary(for: event))
            Text(Fmt.duration(event.duration)).foregroundStyle(Theme.muted).frame(width: 64, alignment: .trailing)
        }
        .padding(.vertical, 7)
        .contentShape(Rectangle())
    }
}
