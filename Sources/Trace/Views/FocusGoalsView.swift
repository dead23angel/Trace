import SwiftUI
import TraceCore

extension TagRole {
    var title: String {
        switch self {
        case .focus: return L("Focus")
        case .neutral: return L("Neutral")
        case .distraction: return L("Distraction")
        }
    }
}

extension Goal {
    /// "at least 4h", "at most 1h".
    var summary: String {
        String(format: kind == .atLeast ? L("at least %@") : L("at most %@"), Fmt.duration(seconds))
    }
}

// MARK: Goals

/// Daily goals as progress rings, with the day's streak.
struct GoalsCard: View {
    @EnvironmentObject private var model: AppModel
    /// On the overview: adds a way to the Focus page.
    var showsFocusLink = false
    @State private var editing: Tag?
    @State private var adding = false

    var body: some View {
        Card(padding: .hv(20, 14)) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 10) {
                    Text(L("Goals")).font(.system(size: 14, weight: .semibold))
                        .help(L("A goal is a daily target for a tag, such as Study for at least 2 hours."))
                    Spacer(minLength: 0)
                    Button(model.goals.isEmpty ? L("Set a daily goal") : L("Add goal")) { adding = true }
                        .buttonStyle(TRButtonStyle(kind: model.goals.isEmpty ? .prominent : .bordered, height: 28))
                        .popover(isPresented: $adding) {
                            GoalEditor(tag: nil) { adding = false }.environmentObject(model)
                        }
                    if showsFocusLink {
                        Button { model.pane = .focus } label: {
                            Label(L("Start a session"), systemImage: "timer")
                        }
                        .buttonStyle(TRButtonStyle(kind: .bordered, height: 28))
                    }
                }
                if !model.goals.isEmpty {
                    FlowLayout(spacing: 22) {
                        ForEach(model.goals) { goal in
                            if let tag = model.tags.first(where: { $0.id == goal.tagID }) {
                                Button { editing = tag } label: { GoalRing(goal: goal, tag: tag) }
                                    .buttonStyle(.plain)
                                    .popover(isPresented: Binding(get: { editing?.id == tag.id }, set: { if !$0 { editing = nil } })) {
                                        GoalEditor(tag: tag) { editing = nil }.environmentObject(model)
                                    }
                            }
                        }
                    }
                }
            }
        }
    }
}

private struct GoalRing: View {
    @EnvironmentObject private var model: AppModel
    let goal: Goal
    let tag: Tag

    var body: some View {
        let spent = model.summary.byTag.first { $0.tag?.id == tag.id }?.seconds ?? 0
        let fraction = min(spent / max(goal.seconds, 1), 1)
        let over = goal.kind == .atMost && spent > goal.seconds
        let done = goal.kind == .atLeast && spent >= goal.seconds
        let color = over ? Palette.color(4) : Palette.color(tag)
        let streak = model.streak(for: goal)
        HStack(spacing: 10) {
            ZStack {
                Circle().stroke(Theme.bg, lineWidth: 6)
                Circle().trim(from: 0, to: max(fraction, 0.002))
                    .stroke(color, style: StrokeStyle(lineWidth: 6, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                if done {
                    Image(systemName: "checkmark").font(.system(size: 12, weight: .bold)).foregroundStyle(color)
                } else if over {
                    Image(systemName: "exclamationmark").font(.system(size: 12, weight: .bold)).foregroundStyle(color)
                } else {
                    Text("\(Int((fraction * 100).rounded()))").font(.system(size: 11, weight: .bold))
                }
            }
            .frame(width: 40, height: 40)
            VStack(alignment: .leading, spacing: 0) {
                Text(tag.displayName).fontWeight(.semibold).lineLimit(1).fixedSize()
                Text("\(Fmt.duration(spent)) / \(goal.summary)")
                    .font(.system(size: 12))
                    .foregroundStyle(over ? color : Theme.muted)
                    .lineLimit(1)
                    .fixedSize()
                if streak >= 2 {
                    Text(String(format: L("%d days in a row"), streak))
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Theme.accent)
                }
            }
        }
        .contentShape(Rectangle())
        .help(L("Click to change this goal"))
        .accessibilityElement(children: .combine)
    }
}

/// Sets, changes or removes the daily goal of a tag.
struct GoalEditor: View {
    @EnvironmentObject private var model: AppModel
    /// The tag whose goal is edited, or nil to pick one.
    let tag: Tag?
    let done: () -> Void

    @State private var tagID: Int64?
    @State private var kind: Goal.Kind = .atLeast
    @State private var minutes = 120

    private var chosen: Tag? { tag ?? model.tags.first { $0.id == tagID } }
    private var existing: Goal? { model.goals.first { $0.tagID == chosen?.id } }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(L("Daily goal")).font(.system(size: 14, weight: .semibold))
            if tag == nil {
                Picker(L("Tag"), selection: $tagID) {
                    ForEach(model.tags.filter(\.enabled)) { tag in Text(tag.displayName).tag(tag.id) }
                }
            } else if let tag {
                HStack(spacing: 6) {
                    Swatch(tag, size: 10, round: true)
                    Text(tag.displayName).fontWeight(.semibold)
                }
            }
            Picker(L("Each day"), selection: $kind) {
                Text(L("At least")).tag(Goal.Kind.atLeast)
                Text(L("At most")).tag(Goal.Kind.atMost)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            Stepper(value: $minutes, in: 15...960, step: 15) {
                Text(Fmt.duration(TimeInterval(minutes * 60))).fontWeight(.semibold).monospacedDigit()
            }
            HStack {
                if existing != nil {
                    Button(L("Remove goal"), role: .destructive) {
                        if let chosen { model.removeGoal(for: chosen) }
                        done()
                    }
                }
                Spacer()
                Button(L("Cancel"), action: done)
                Button(L("Save")) {
                    if let chosen { model.setGoal(for: chosen, kind: kind, minutes: minutes) }
                    done()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(chosen == nil)
            }
        }
        .padding(16)
        .frame(width: 280)
        .onAppear {
            if tagID == nil {
                tagID = tag?.id ?? model.tags.first { tag in tag.enabled && !model.goals.contains { $0.tagID == tag.id } }?.id
            }
            load()
        }
        .onChange(of: tagID) { load() }
    }

    private func load() {
        guard let existing else { return }
        kind = existing.kind
        minutes = existing.minutes
    }
}

// MARK: Focus

/// How focused the day was: deep work, switching, and what interrupted.
struct FocusCard: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        let focus = model.focus
        let scale = DayScale(day: model.day, first: model.summary.first, last: model.summary.last)
        let hours = Array(scale.hours.lowerBound..<scale.hours.upperBound)
        let peak = max(focus.switchesByHour.values.max() ?? 0, 1)
        Card {
            VStack(alignment: .leading, spacing: 12) {
                SectionTitle(title: L("Focus"), note: L("Deep work: 25 minutes or more of focus work in one go"))
                HStack(alignment: .top, spacing: 8) {
                    stat(L("Deep work"), Fmt.duration(focus.deepSeconds),
                         focus.deepCount == 0 ? L("none yet")
                         : String(format: L("%1$d stretches, longest %2$@"), focus.deepCount, Fmt.duration(focus.longestDeep)))
                    stat(L("Share of the day"), "\(Int((focus.deepShare * 100).rounded()))%", L("of tracked time"))
                    stat(L("Distraction"), Fmt.duration(focus.distractionSeconds), L("on distraction tags"))
                }
                Hairline()
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text(L("App switches per hour")).font(.system(size: 12)).foregroundStyle(Theme.muted)
                        Spacer()
                        Text(String(format: L("%d in all"), focus.switches)).font(.system(size: 12)).foregroundStyle(Theme.muted)
                    }
                    HStack(alignment: .bottom, spacing: 3) {
                        ForEach(hours, id: \.self) { hour in
                            let count = focus.switchesByHour[hour] ?? 0
                            VStack(spacing: 3) {
                                RoundedRectangle(cornerRadius: 2, style: .continuous)
                                    .fill(count == 0 ? Theme.bg : Theme.accent.opacity(0.35 + 0.65 * Double(count) / Double(peak)))
                                    .frame(height: max(3, 36 * CGFloat(count) / CGFloat(peak)))
                                Text(hour % 2 == 0 ? String(format: "%02d", hour) : " ")
                                    .font(.system(size: 9)).foregroundStyle(Theme.muted).fixedSize()
                            }
                            .frame(maxWidth: .infinity)
                            .help("\(String(format: "%02d:00", hour)) · \(count)")
                        }
                    }
                    .frame(height: 52, alignment: .bottom)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(L("App switches per hour"))
                }
                if !focus.interrupters.isEmpty {
                    Hairline()
                    VStack(alignment: .leading, spacing: 6) {
                        Text(L("What pulled you out of focus")).font(.system(size: 12)).foregroundStyle(Theme.muted)
                        ForEach(focus.interrupters.prefix(3)) { item in
                            HStack(spacing: 8) {
                                AppIcon(bundleID: item.bundleID, size: 18)
                                Text(item.appName).lineLimit(1)
                                Spacer()
                                Text(String(format: L("%d times"), item.count)).foregroundStyle(Theme.muted)
                            }
                        }
                    }
                }
            }
        }
    }

    private func stat(_ title: String, _ value: String, _ note: String) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(title).font(.system(size: 12)).foregroundStyle(Theme.muted)
            Text(value).font(.system(size: 18, weight: .bold)).lineLimit(1).minimumScaleFactor(0.7)
            Text(note).font(.system(size: 11)).foregroundStyle(Theme.muted).lineLimit(2).fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
