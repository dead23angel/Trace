import SwiftUI
import TraceCore

/// One chip per tag used that day; the chosen one narrows every timeline
/// view to that tag.
struct TagFilterBar: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                chip(label: L("All"), color: Theme.ink, isOn: model.tagFilter == nil) { model.tagFilter = nil }
                ForEach(model.summary.byTag) { total in
                    chip(label: tagName(total.tag), color: Palette.color(total.tag), isOn: model.tagFilter == total.id) {
                        model.tagFilter = model.tagFilter == total.id ? nil : total.id
                    }
                }
            }
            .padding(.vertical, 1)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(L("Filter by tag"))
    }

    private func chip(label: String, color: Color, isOn: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Circle().fill(color).frame(width: 8, height: 8)
                Text(label).fontWeight(isOn ? .semibold : .medium)
            }
            .padding(.horizontal, 12)
            .frame(height: 28)
            .background(isOn ? Theme.hover : .clear, in: Capsule())
            .overlay(Capsule().strokeBorder(isOn ? .clear : Theme.line))
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isOn ? .isSelected : [])
    }
}

/// Every record of the day, grouped into sessions, with an inspector for
/// the selected one.
struct RecordsView: View {
    @EnvironmentObject private var model: AppModel
    let events: [ActivityEvent]

    @State private var opened: Set<Date> = []
    @State private var collapsed: Set<Date> = []

    private var isFiltered: Bool {
        model.tagFilter != nil || !model.query.trimmingCharacters(in: .whitespaces).isEmpty
    }

    var body: some View {
        let blocks = model.filteredBlocks
        let selected = model.events.first { $0.id == model.selectedEventID }
        let current = blocks.first { $0.start == model.selectedBlock }
            ?? selected.flatMap { event in blocks.first { $0.start <= event.start && event.start < $0.end } }
            ?? blocks.last

        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 12) {
                VStack(spacing: 12) {
                    if let current {
                        DayStripCard(blocks: blocks, current: current)
                    }
                    Card(padding: EdgeInsets(top: 4, leading: 20, bottom: 8, trailing: 20)) {
                        VStack(spacing: 0) {
                            if blocks.isEmpty {
                                Text(L("No matching records")).foregroundStyle(Theme.muted)
                                    .frame(maxWidth: .infinity, alignment: .leading).padding(.vertical, 14)
                            }
                            ForEach(Array(blocks.enumerated()), id: \.element.id) { index, block in
                                if !isFiltered, index > 0 {
                                    let gap = block.start.timeIntervalSince(blocks[index - 1].end)
                                    if gap >= 300 { awayRow(from: blocks[index - 1].end, to: block.start) }
                                }
                                group(block, isOpen: isOpen(block, current: current), selected: selected)
                            }
                        }
                    }
                }
                Inspector(event: selected, blocks: blocks).frame(width: 320)
            }
        }
    }

    private func isOpen(_ block: Block, current: Block?) -> Bool {
        if opened.contains(block.start) { return true }
        return block.start == current?.start && !collapsed.contains(block.start)
    }

    private func toggle(_ block: Block, isOpen: Bool) {
        if isOpen {
            opened.remove(block.start)
            collapsed.insert(block.start)
        } else {
            collapsed.remove(block.start)
            opened.insert(block.start)
            model.selectedBlock = block.start
        }
    }

    private func awayRow(from: Date, to: Date) -> some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Color.clear.frame(width: 12)
                Text("\(Fmt.time(from)) – \(Fmt.time(to))").foregroundStyle(Theme.muted).frame(width: 96, alignment: .leading)
                Swatch(color: Theme.line)
                Text(L("Away")).fontWeight(.semibold).foregroundStyle(Theme.muted)
                Text(awayNote(from: from, to: to)).font(.system(size: 12)).foregroundStyle(Theme.muted).lineLimit(1)
                Spacer()
                Text(Fmt.duration(to.timeIntervalSince(from))).fontWeight(.semibold).foregroundStyle(Theme.muted)
            }
            .frame(minHeight: 44)
            Hairline()
        }
    }

    /// What was going on while nothing was typed or clicked: sound that
    /// kept playing, a call, or nothing at all.
    private func awayNote(from: Date, to: Date) -> String {
        let during = model.background.filter { $0.end > from && $0.start < to && min($0.end, to).timeIntervalSince(max($0.start, from)) >= 30 }
        let calls = Set(during.filter { $0.layer == Layer.mic.rawValue }.map(\.appName)).sorted()
        let sound = Set(during.filter { $0.layer == Layer.audio.rawValue }.map(\.appName)).sorted()
        if !calls.isEmpty { return String(format: L("no input, on a call in %@"), calls.joined(separator: L(", "))) }
        if !sound.isEmpty { return String(format: L("no input, %@ was playing"), sound.joined(separator: L(", "))) }
        return L("no keyboard or mouse input")
    }

    private func group(_ block: Block, isOpen: Bool, selected: ActivityEvent?) -> some View {
        let rows = block.events.filter { $0.duration >= 3 || $0.id == selected?.id }
        return VStack(spacing: 0) {
            Button { toggle(block, isOpen: isOpen) } label: {
                HStack(spacing: 10) {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(Theme.muted)
                        .rotationEffect(.degrees(isOpen ? 90 : 0))
                        .frame(width: 12)
                    Text("\(Fmt.time(block.start)) – \(Fmt.time(block.end))")
                        .foregroundStyle(Theme.muted)
                        .frame(width: 96, alignment: .leading)
                    Swatch(block.tag)
                    Text(tagName(block.tag)).fontWeight(.semibold)
                    Text(Fmt.records(rows.count)).font(.system(size: 12)).foregroundStyle(Theme.muted)
                    Text(block.title).font(.system(size: 12)).foregroundStyle(Theme.muted).lineLimit(1)
                    if !model.devices.isEmpty {
                        Badge(text: model.deviceName(forDevice: block.device))
                    }
                    Spacer(minLength: 8)
                    Text(Fmt.duration(block.duration)).fontWeight(.semibold)
                }
                .frame(minHeight: 44)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            if isOpen {
                ForEach(rows) { event in
                    RecordRow(event: event, isSelected: event.id == selected?.id) {
                        model.selectedEventID = event.id
                    }
                }
            }
            Hairline()
        }
    }
}

private struct RecordRow: View {
    @EnvironmentObject private var model: AppModel
    let event: ActivityEvent
    let isSelected: Bool
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Text(Fmt.time(event.start)).foregroundStyle(Theme.muted).frame(width: 40, alignment: .leading)
                AppIcon(bundleID: event.bundleID, size: 28)
                VStack(alignment: .leading, spacing: 0) {
                    HStack(spacing: 8) {
                        Text(event.headline).fontWeight(.semibold).lineLimit(1)
                        Badge(text: event.kindName)
                    }
                    if let detail = event.detail {
                        Text(detail).font(Theme.mono).foregroundStyle(Theme.muted).lineLimit(1).truncationMode(.middle)
                    }
                }
                Spacer(minLength: 8)
                HStack(spacing: 4) {
                    ForEach(model.tagger.tags(for: event).prefix(2)) { tag in TagChip(tag: tag, round: true) }
                }
                Text(Fmt.duration(event.duration)).foregroundStyle(Theme.muted).frame(width: 52, alignment: .trailing)
            }
            .padding(.horizontal, 10)
            .frame(minHeight: 52)
            .background(isSelected ? Theme.soft : (hovering ? Theme.hover : .clear),
                        in: RoundedRectangle(cornerRadius: 9, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.horizontal, -10)
        .padding(.bottom, 4)
        .onHover { hovering = $0 }
        .contextMenu {
            Button(L("Delete this record"), role: .destructive) { model.deleteEvent(event) }
        }
    }
}

/// The whole day as one strip, with the selected session magnified below.
private struct DayStripCard: View {
    @EnvironmentObject private var model: AppModel
    let blocks: [Block]
    let current: Block

    var body: some View {
        let scale = DayScale(day: model.day, first: model.summary.first, last: model.summary.last)
        let runs = Analyzer.appRuns(current.events, in: DateInterval(start: current.start, end: current.end),
                                    tagger: model.tagger, maxGap: 5)
        Card(padding: EdgeInsets(top: 14, leading: 20, bottom: 16, trailing: 20)) {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    let labels = scale.labels()
                    ForEach(labels, id: \.self) { hour in
                        Text(String(format: "%02d", hour))
                        if hour != labels.last { Spacer() }
                    }
                }
                .font(.system(size: 11))
                .foregroundStyle(Theme.muted)
                .accessibilityHidden(true)

                Lane(pieces: blocks.enumerated().map { index, block in
                    .init(id: index, start: scale.fraction(block.start), length: scale.length(block.duration),
                          color: Palette.color(block.tag),
                          tip: "\(tagName(block.tag)) · \(Fmt.time(block.start)) – \(Fmt.time(block.end))",
                          opacity: block.start == current.start ? 1 : 0.35)
                }, height: 30, radius: 7) { index in
                    model.selectedBlock = blocks[index].start
                }
                .accessibilityLabel(L("The whole day; click a session to magnify it"))

                HStack(spacing: 8) {
                    Text("\(Fmt.time(current.start)) – \(Fmt.time(current.end))").fontWeight(.semibold)
                    Text(L("Magnified") + " · " + Fmt.records(current.events.count))
                        .foregroundStyle(Theme.muted)
                }
                .padding(.top, 6)

                GeometryReader { geo in
                    let total = max(runs.reduce(0) { $0 + $1.end.timeIntervalSince($1.start) }, 1)
                    let usable = max(0, geo.size.width - CGFloat(max(runs.count - 1, 0)) * 2)
                    HStack(spacing: 2) {
                        ForEach(runs) { run in
                            let width = usable * CGFloat(run.end.timeIntervalSince(run.start) / total)
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .fill(Palette.color(run.tag).opacity(0.28))
                                .frame(width: max(1, width))
                                .overlay {
                                    if width > 44 {
                                        Text(run.appName).font(.system(size: 11, weight: .semibold))
                                            .lineLimit(1).padding(.horizontal, 4)
                                    }
                                }
                                .help("\(run.appName) · \(Fmt.time(run.start)) – \(Fmt.time(run.end))")
                        }
                    }
                }
                .frame(height: 34)
                .accessibilityLabel(L("Apps in the selected session, in order"))
            }
        }
    }
}

/// Details of one record, its tags, and a shortcut to turn a tag into a rule.
private struct Inspector: View {
    @EnvironmentObject private var model: AppModel
    let event: ActivityEvent?
    let blocks: [Block]

    var body: some View {
        Card(padding: .hv(20, 18)) {
            if let event {
                content(event)
            } else {
                EmptyState(title: L("No record selected"),
                           note: L("Open a session on the left and click a record to see its details and edit its tags."),
                           symbol: "cursorarrow.click")
                    .frame(height: 260)
            }
        }
    }

    private func content(_ event: ActivityEvent) -> some View {
        let tags = model.tagger.tags(for: event)
        let session = blocks.first { $0.start <= event.start && event.start < $0.end }
        let same = model.events.filter { sameItem($0, event) }
        return VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 2) {
                Text("\(Fmt.time(event.start)) – \(Fmt.time(event.end)) · \(Fmt.duration(event.duration))")
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.muted)
                Text(event.title.isEmpty ? event.appName : event.title)
                    .font(.system(size: 16, weight: .bold))
                    .fixedSize(horizontal: false, vertical: true)
                    .textSelection(.enabled)
            }
            Grid(alignment: .topLeading, horizontalSpacing: 10, verticalSpacing: 8) {
                field(L("App")) { Text(event.appName) }
                field(L("Type")) { Text(event.kindName) }
                if !model.devices.isEmpty {
                    field(L("Mac")) { Text(model.deviceName(for: event)) }
                }
                if let path = event.path, !path.isEmpty {
                    field(L("Path")) {
                        Text(Analyzer.abbreviate(path)).font(Theme.mono).textSelection(.enabled)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                if let detail = event.url.flatMap({ _ in event.detail }) {
                    field(L("URL")) {
                        Text(detail).font(Theme.mono).textSelection(.enabled)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                if let session {
                    field(L("Session")) {
                        Text("\(tagName(session.tag)) · \(Fmt.time(session.start)) – \(Fmt.time(session.end))")
                    }
                }
                field(model.isToday ? L("Today") : L("That day")) {
                    Text(String(format: L("Seen %1$d times, %2$@ in total"), same.count,
                                Fmt.duration(same.reduce(0) { $0 + $1.duration })))
                }
            }
            Hairline()
            VStack(alignment: .leading, spacing: 8) {
                Text(L("Tags")).fontWeight(.semibold)
                FlowLayout(spacing: 6) {
                    ForEach(tags) { tag in
                        HStack(spacing: 6) {
                            Circle().fill(Palette.color(tag)).frame(width: 8, height: 8)
                            Text(tag.displayName)
                            if !model.tagger.isManual(tag, for: event) {
                                Text(L("auto")).font(.system(size: 11)).foregroundStyle(Theme.muted)
                            }
                            Button { model.removeTag(tag, from: event) } label: {
                                Image(systemName: "xmark").font(.system(size: 8, weight: .heavy))
                                    .foregroundStyle(Theme.muted)
                                    .frame(width: 20, height: 20)
                                    .contentShape(Circle())
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel(String(format: L("Remove tag %@"), tag.displayName))
                        }
                        .padding(EdgeInsets(top: 3, leading: 10, bottom: 3, trailing: 4))
                        .overlay(Capsule().strokeBorder(Theme.line))
                    }
                    Menu {
                        ForEach(model.tags.filter { tag in tag.enabled && !tags.contains { $0.id == tag.id } }) { tag in
                            Button(tag.displayName) { model.addTag(tag, to: event) }
                        }
                    } label: {
                        Text(L("Add tag")).fontWeight(.semibold).foregroundStyle(Theme.accent)
                    }
                    .menuStyle(.borderlessButton)
                    .menuIndicator(.hidden)
                    .fixedSize()
                    .padding(.horizontal, 12)
                    .frame(height: 28)
                    .overlay(Capsule().strokeBorder(Theme.line, style: StrokeStyle(lineWidth: 1, dash: [3, 3])))
                }
            }
            if let suggestion = suggestion(for: event, tags: tags) {
                VStack(alignment: .leading, spacing: 8) {
                    Text(suggestion.text).font(.system(size: 12)).fixedSize(horizontal: false, vertical: true)
                    Button(L("Save as rule")) {
                        model.addRule(to: suggestion.tag, field: suggestion.rule.field, op: suggestion.rule.op,
                                      value: suggestion.rule.value)
                    }
                    .buttonStyle(TRButtonStyle(kind: .prominent, height: 28))
                }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Theme.soft, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            }
            Button(L("Delete this record")) { model.deleteEvent(event) }
                .buttonStyle(.plain)
                .foregroundStyle(Theme.muted)
        }
    }

    private func field<Content: View>(_ label: String, @ViewBuilder value: () -> Content) -> some View {
        GridRow {
            Text(label).foregroundStyle(Theme.muted).frame(width: 64, alignment: .leading)
            value().frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func sameItem(_ a: ActivityEvent, _ b: ActivityEvent) -> Bool {
        guard a.bundleID == b.bundleID else { return false }
        if let path = b.path, !path.isEmpty { return a.path == path }
        if let url = b.url, !url.isEmpty { return a.url == url }
        return a.title == b.title
    }

    /// After a tag is added by hand, offers to make it automatic for
    /// everything from the same site, folder or app.
    private func suggestion(for event: ActivityEvent, tags: [Tag]) -> (text: String, tag: Tag, rule: Rule)? {
        guard let tag = tags.first(where: { model.tagger.isManual($0, for: event) }), let tagID = tag.id else { return nil }
        let rule: Rule, label: String
        if let host = event.host {
            rule = Rule(tagID: tagID, field: .url, op: .contains, value: host)
            label = host
        } else if let path = event.path, !path.isEmpty {
            let folder = (path as NSString).deletingLastPathComponent
            rule = Rule(tagID: tagID, field: .path, op: .hasPrefix, value: folder)
            label = Analyzer.abbreviate(folder)
        } else {
            rule = Rule(tagID: tagID, field: .app, op: .equals, value: event.bundleID)
            label = event.appName
        }
        let exists = model.rules.contains {
            $0.tagID == tagID && $0.field == rule.field && $0.value.lowercased() == rule.value.lowercased()
        }
        guard !exists else { return nil }
        let count = model.events(in: model.weekInterval).filter(rule.matches).count
        let text = String(format: L("Tag everything from %1$@ as “%2$@”? %3$d records this week."),
                          label, tag.displayName, count)
        return (text, tag, rule)
    }
}

/// Lays children out left to right, wrapping onto new lines.
struct FlowLayout: Layout {
    var spacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        arrange(width: proposal.width ?? .infinity, subviews: subviews).size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = arrange(width: bounds.width, subviews: subviews)
        for (index, point) in result.points.enumerated() {
            subviews[index].place(at: CGPoint(x: bounds.minX + point.x, y: bounds.minY + point.y), proposal: .unspecified)
        }
    }

    private func arrange(width: CGFloat, subviews: Subviews) -> (size: CGSize, points: [CGPoint]) {
        var points: [CGPoint] = []
        var x: CGFloat = 0, y: CGFloat = 0, rowHeight: CGFloat = 0, widest: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > 0, x + size.width > width {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            points.append(CGPoint(x: x, y: y))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
            widest = max(widest, x - spacing)
        }
        return (CGSize(width: widest, height: y + rowHeight), points)
    }
}
