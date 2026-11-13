import SwiftUI
import TraceCore

/// The day as parallel lanes: one per tag or app for what was in front,
/// then sound, calls, and one per Mac. Shows what happened at the same time.
struct GanttCard: View {
    @EnvironmentObject private var model: AppModel
    @State private var grouping: GanttGrouping = .tag

    private let labelWidth: CGFloat = 210
    private let rowHeight: CGFloat = 30

    var body: some View {
        let gantt = model.gantt(grouping)
        let scale = DayScale(day: model.day, first: firstMoment(gantt), last: lastMoment(gantt))
        Card(padding: EdgeInsets(top: 16, leading: 20, bottom: 18, trailing: 20)) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 12) {
                    SectionTitle(title: L("The day in lanes"),
                                 note: L("Each lane is one thing; bars that line up happened at the same time"))
                    Spacer()
                    Segmented(options: [(GanttGrouping.tag, L("By tag")), (.app, L("By app"))], selection: $grouping)
                }
                if let selection = model.selection {
                    HStack(spacing: 10) {
                        Text("\(Fmt.time(selection.start)) – \(Fmt.time(selection.end))").fontWeight(.semibold)
                        Text(Fmt.duration(selection.duration)).foregroundStyle(Theme.muted)
                        Button(L("See what happened")) { model.timelineMode = .byTag }.buttonStyle(.trLink)
                        Button(L("Clear")) { model.selection = nil }.buttonStyle(.trLink)
                    }
                    .padding(.horizontal, 10)
                    .frame(height: 30)
                    .background(Theme.soft, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                }

                axis(scale)
                section(L("IN FRONT"), rows: gantt.rows, scale: scale)
                if !gantt.background.isEmpty {
                    section(L("IN THE BACKGROUND"), rows: gantt.background, scale: scale)
                }
                if !gantt.devices.isEmpty {
                    section(L("MACS"), rows: gantt.devices, scale: scale)
                }
                if gantt.background.isEmpty && model.captureBackground {
                    Text(L("No sound or calls were recorded on this day."))
                        .font(.system(size: 12)).foregroundStyle(Theme.muted).padding(.top, 2)
                }
            }
        }
    }

    private func firstMoment(_ gantt: Gantt) -> Date? {
        ([model.summary.first] + gantt.background.flatMap(\.bars).map { Optional($0.start) }).compactMap { $0 }.min()
    }

    private func lastMoment(_ gantt: Gantt) -> Date? {
        ([model.summary.last] + gantt.background.flatMap(\.bars).map { Optional($0.end) }).compactMap { $0 }.max()
    }

    private func axis(_ scale: DayScale) -> some View {
        HStack(spacing: 0) {
            Color.clear.frame(width: labelWidth, height: 1)
            GeometryReader { geo in
                let hours = Array(scale.hours)
                let step = geo.size.width / CGFloat(max(hours.count - 1, 1)) < 34 ? 2 : 1
                ForEach(hours.filter { ($0 - scale.hours.lowerBound) % step == 0 }, id: \.self) { hour in
                    Text(String(format: "%02d", hour))
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.muted)
                        .fixedSize()
                        .position(x: geo.size.width * CGFloat(hour - scale.hours.lowerBound) / CGFloat(max(hours.count - 1, 1)), y: 7)
                }
            }
            .frame(height: 14)
        }
        .padding(.top, 4)
        .accessibilityHidden(true)
    }

    private func section(_ title: String, rows: [GanttRow], scale: DayScale) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(title)
                .font(.system(size: 11, weight: .semibold))
                .tracking(0.4)
                .foregroundStyle(Theme.muted)
                .padding(.top, 6)
                .padding(.bottom, 2)
            ForEach(rows) { row in
                HStack(spacing: 0) {
                    label(row).frame(width: labelWidth, alignment: .leading)
                    GanttLane(row: row, scale: scale, showsNow: model.isToday) { bar in
                        let interval = DateInterval(start: bar.start, end: bar.end)
                        model.selection = model.selection == interval ? nil : interval
                    }
                }
                .frame(height: rowHeight)
            }
        }
    }

    private func label(_ row: GanttRow) -> some View {
        HStack(spacing: 8) {
            switch row.kind {
            case .tag: Swatch(row.tag, size: 10).frame(width: 18)
            case .app: AppIcon(bundleID: row.bundleID ?? "", size: 18)
            case .audio: symbol("speaker.wave.2.fill")
            case .mic: symbol("phone.fill")
            case .device: symbol("laptopcomputer")
            }
            Text(name(row)).fontWeight(.medium).lineLimit(1)
            Spacer(minLength: 4)
            Text(Fmt.duration(row.seconds)).foregroundStyle(Theme.muted).padding(.trailing, 12)
        }
    }

    private func symbol(_ name: String) -> some View {
        Image(systemName: name).font(.system(size: 11)).foregroundStyle(Theme.muted).frame(width: 18)
    }

    private func name(_ row: GanttRow) -> String {
        switch row.kind {
        case .tag: return tagName(row.tag)
        case .audio: return L("Sound")
        case .mic: return L("Calls")
        default: return row.label
        }
    }
}

/// One lane: hour lines, the bars, and a line for the present moment.
private struct GanttLane: View {
    let row: GanttRow
    let scale: DayScale
    let showsNow: Bool
    let select: (GanttBar) -> Void

    private var barHeight: CGFloat { row.kind == .tag || row.kind == .app ? 18 : 14 }

    var body: some View {
        GeometryReader { geo in
            let width = geo.size.width
            ZStack(alignment: .leading) {
                Canvas { context, size in
                    let count = max(scale.hours.count - 1, 1)
                    for index in 0...count {
                        let x = (size.width * CGFloat(index) / CGFloat(count)).rounded() + 0.5
                        var line = Path()
                        line.move(to: CGPoint(x: min(x, size.width - 0.5), y: 0))
                        line.addLine(to: CGPoint(x: min(x, size.width - 0.5), y: size.height))
                        context.stroke(line, with: .color(Theme.line.opacity(index % 2 == 0 ? 0.9 : 0.45)), lineWidth: 1)
                    }
                }
                ForEach(row.bars) { bar in
                    let x = width * CGFloat(scale.fraction(bar.start))
                    let w = max(3, width * CGFloat(scale.length(bar.end.timeIntervalSince(bar.start))) - 1)
                    Button { select(bar) } label: {
                        RoundedRectangle(cornerRadius: 4, style: .continuous)
                            .fill(color(bar))
                            .frame(width: w, height: barHeight)
                            .overlay(alignment: .leading) {
                                if !bar.label.isEmpty, w > 54, row.kind != .tag {
                                    Text(bar.label)
                                        .font(.system(size: 10, weight: .semibold))
                                        .foregroundStyle(row.kind == .app ? Color.white : Theme.ink)
                                        .lineLimit(1)
                                        .padding(.horizontal, 5)
                                        .frame(width: w, alignment: .leading)
                                }
                            }
                    }
                    .buttonStyle(.plain)
                    .offset(x: x)
                    .help(tip(bar))
                }
                if showsNow {
                    let now = scale.fraction(Date())
                    if now >= 0, now <= 1 {
                        Rectangle().fill(Theme.accent).frame(width: 1.5).offset(x: width * CGFloat(now))
                    }
                }
            }
            .frame(width: width, height: geo.size.height, alignment: .leading)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(row.label) \(Fmt.duration(row.seconds))")
    }

    private func color(_ bar: GanttBar) -> Color {
        switch row.kind {
        case .device: return Theme.accent.opacity(0.55)
        case .audio, .mic: return Palette.color(bar.tag).opacity(0.38)
        default: return Palette.color(bar.tag)
        }
    }

    private func tip(_ bar: GanttBar) -> String {
        let time = "\(Fmt.time(bar.start)) – \(Fmt.time(bar.end)) · \(Fmt.duration(bar.end.timeIntervalSince(bar.start)))"
        let what = bar.label.isEmpty ? (row.kind == .tag ? tagName(row.tag) : row.label) : bar.label
        return what.isEmpty ? time : "\(what) · \(time)"
    }
}
