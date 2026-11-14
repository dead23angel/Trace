import SwiftUI
import TraceCore

/// The panel behind the menu bar icon: today's total at a glance.
struct MenuBarView: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var watcher: ActivityWatcher
    @Environment(\.openWindow) private var openWindow

    private var state: (title: String, color: Color) {
        if watcher.isPaused { return (L("Paused"), Palette.color(3)) }
        if watcher.isIdle { return (L("Away"), Theme.muted) }
        return (L("Recording"), Theme.accent)
    }

    var body: some View {
        let summary = model.summary
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 8) {
                Image(systemName: "waveform.path.ecg").font(.system(size: 14, weight: .bold)).foregroundStyle(Theme.accent)
                Text("Trace").fontWeight(.bold)
                Spacer()
                Circle().fill(state.color).frame(width: 7, height: 7)
                Text(state.title).font(.system(size: 12)).foregroundStyle(Theme.muted)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(L("Tracked today")).font(.system(size: 12)).foregroundStyle(Theme.muted)
                Text(Fmt.duration(summary.total)).font(.system(size: 30, weight: .bold)).tracking(-0.6)
            }
            if summary.total > 0 {
                GeometryReader { geo in
                    let usable = geo.size.width - CGFloat(max(summary.byTag.count - 1, 0)) * 2
                    HStack(spacing: 2) {
                        ForEach(summary.byTag) { total in
                            Rectangle().fill(Palette.color(total.tag))
                                .frame(width: max(2, usable * total.seconds / summary.total))
                        }
                    }
                }
                .frame(height: 10)
                .clipShape(Capsule())
                .accessibilityHidden(true)
                VStack(spacing: 6) {
                    ForEach(summary.byTag.prefix(3)) { total in
                        HStack(spacing: 8) {
                            Swatch(total.tag, size: 9)
                            Text(tagName(total.tag))
                            Spacer()
                            Text(Fmt.duration(total.seconds)).foregroundStyle(Theme.muted)
                        }
                    }
                }
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(L("Current activity")).font(.system(size: 11)).foregroundStyle(Theme.muted)
                if let current = watcher.current {
                    Text(current.headline).fontWeight(.semibold).lineLimit(1).truncationMode(.middle)
                    if let since = watcher.currentSince {
                        Text(String(format: L("For %@"), Fmt.duration(max(0, Date().timeIntervalSince(since)))))
                            .font(.system(size: 12))
                            .foregroundStyle(Theme.muted)
                    }
                } else {
                    Text(watcher.isPaused ? L("Recording is paused") : L("Nothing in front right now"))
                        .fontWeight(.semibold)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.bg, in: RoundedRectangle(cornerRadius: 10, style: .continuous))

            if model.running != nil {
                RunningSessionPill()
            } else {
                Menu {
                    ForEach(model.tags.filter(\.enabled)) { tag in
                        Menu(tag.displayName) {
                            Button(L("Until I stop it")) { model.startSession(tag, minutes: nil) }
                            ForEach([25, 50, 60, 120], id: \.self) { minutes in
                                Button(Fmt.duration(TimeInterval(minutes * 60))) { model.startSession(tag, minutes: minutes) }
                            }
                        }
                    }
                } label: {
                    Label(L("Start a session…"), systemImage: "timer")
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
            }
            HStack(spacing: 8) {
                Button(watcher.isPaused ? L("Resume") : L("Pause 15 minutes")) {
                    if watcher.isPaused { watcher.isPaused = false } else { watcher.pause(for: 15 * 60) }
                }
                .buttonStyle(FullWidth(kind: .bordered))
                Button(L("Open Trace")) {
                    openWindow(id: "main")
                    NSApp.activate(ignoringOtherApps: true)
                }
                .buttonStyle(FullWidth(kind: .prominent))
            }
            Hairline()
            HStack {
                SettingsLink { Text(L("Settings…")) }
                Spacer()
                Button(L("Quit Trace")) { NSApp.terminate(nil) }
            }
            .buttonStyle(.plain)
            .font(.system(size: 12))
            .foregroundStyle(Theme.muted)
        }
        .padding(16)
        .frame(width: 320)
        .background(Theme.panel)
        .font(.system(size: 13))
        .foregroundStyle(Theme.ink)
        .monospacedDigit()
        .onAppear { model.goToToday(); model.reload() }
    }
}

/// A design button that stretches to fill its share of a row.
private struct FullWidth: ButtonStyle {
    let kind: TRButtonStyle.Kind

    func makeBody(configuration: Configuration) -> some View {
        let shape = RoundedRectangle(cornerRadius: 8, style: .continuous)
        configuration.label
            .fontWeight(kind == .prominent ? .semibold : .medium)
            .frame(maxWidth: .infinity, minHeight: 32)
            .foregroundStyle(kind == .prominent ? Theme.onAccent : Theme.ink)
            .background(kind == .prominent ? Theme.accent : .clear, in: shape)
            .overlay(shape.strokeBorder(kind == .prominent ? .clear : Theme.line))
            .opacity(configuration.isPressed ? 0.7 : 1)
            .contentShape(shape)
    }
}
