import SwiftUI
import TraceCore

extension Pane {
    var title: String {
        switch self {
        case .overview: return L("Overview")
        case .timeline: return L("Timeline")
        case .reports: return L("Reports")
        case .tags: return L("Tags")
        case .rules: return L("Rules")
        }
    }

    var icon: String {
        switch self {
        case .overview: return "square.grid.2x2"
        case .timeline: return "list.bullet.indent"
        case .reports: return "chart.bar"
        case .tags: return "tag"
        case .rules: return "line.3.horizontal.decrease"
        }
    }
}

struct RootView: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var watcher: ActivityWatcher

    var body: some View {
        HStack(spacing: 0) {
            Sidebar()
                .frame(width: 220)
                .background(Theme.side)
            Rectangle().fill(Theme.line).frame(width: 1)
            VStack(spacing: 0) {
                if !watcher.isTrusted && !model.showsOnboarding { PermissionBanner() }
                Group {
                    switch model.pane {
                    case .overview: OverviewView()
                    case .timeline: TimelineView()
                    case .reports: ReportsView()
                    case .tags: TagsView()
                    case .rules: RulesView()
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            }
            .background(Theme.bg)
        }
        .font(.system(size: 13))
        .foregroundStyle(Theme.ink)
        .monospacedDigit()
        .ignoresSafeArea()
        .sheet(isPresented: $model.showsOnboarding) {
            OnboardingView()
                .environmentObject(model)
                .environmentObject(watcher)
                .interactiveDismissDisabled()
        }
    }
}

/// Standard padding and scrolling for a page.
struct Page<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) { content }
                .padding(EdgeInsets(top: 20, leading: 28, bottom: 28, trailing: 28))
        }
    }
}

private struct Sidebar: View {
    @EnvironmentObject private var model: AppModel

    private var deviceLabel: String {
        switch model.deviceFilter {
        case nil: return L("All Macs")
        case "": return model.deviceName
        case let id?: return model.devices.first { $0.id == id }?.name ?? id
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack(spacing: 10) {
                BrandMark()
                Text("Trace").font(.system(size: 16, weight: .bold)).tracking(-0.2)
            }
            .padding(.horizontal, 8)

            VStack(spacing: 2) {
                ForEach(Pane.allCases) { pane in
                    let isOn = model.pane == pane
                    Button { model.pane = pane } label: {
                        HStack(spacing: 10) {
                            Image(systemName: pane.icon)
                                .font(.system(size: 13, weight: .medium))
                                .foregroundStyle(Theme.accent)
                                .frame(width: 16)
                            Text(pane.title)
                                .fontWeight(isOn ? .semibold : .medium)
                                .foregroundStyle(isOn ? Theme.ink : Theme.muted)
                            Spacer()
                        }
                        .padding(.horizontal, 8)
                        .frame(height: 32)
                        .background(isOn ? Theme.hover : .clear, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(isOn ? .isSelected : [])
                }
            }

            if !model.devices.isEmpty {
                Menu {
                    Button(L("All Macs")) { model.deviceFilter = nil }
                    Divider()
                    Button(model.deviceName + " · " + L("this Mac")) { model.deviceFilter = "" }
                    ForEach(model.devices) { device in
                        Button(device.name) { model.deviceFilter = device.id }
                    }
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: "laptopcomputer").font(.system(size: 12, weight: .medium)).frame(width: 16)
                        Text(deviceLabel).fontWeight(.medium).lineLimit(1)
                        Spacer(minLength: 4)
                        Image(systemName: "chevron.up.chevron.down").font(.system(size: 9, weight: .bold))
                    }
                    .foregroundStyle(Theme.muted)
                    .padding(.horizontal, 8)
                    .frame(height: 30)
                    .overlay(RoundedRectangle(cornerRadius: 7, style: .continuous).strokeBorder(Theme.line))
                    .contentShape(Rectangle())
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .buttonStyle(.plain)
                .accessibilityLabel(L("Show records from"))
            }

            if !model.summary.byTag.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text(model.isToday ? L("TODAY") : Fmt.day(model.day))
                        .font(.system(size: 11, weight: .semibold))
                        .tracking(0.4)
                        .foregroundStyle(Theme.muted)
                        .padding(.horizontal, 8)
                    ForEach(model.summary.byTag.prefix(8)) { total in
                        HStack(spacing: 10) {
                            Swatch(total.tag)
                            Text(tagName(total.tag)).lineLimit(1)
                            Spacer(minLength: 4)
                            Text(Fmt.duration(total.seconds)).foregroundStyle(Theme.muted)
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                    }
                }
            }

            Spacer(minLength: 0)

            VStack(spacing: 8) {
                SettingsLink {
                    HStack(spacing: 10) {
                        Image(systemName: "slider.horizontal.3").font(.system(size: 13, weight: .medium)).frame(width: 16)
                        Text(L("Settings")).fontWeight(.medium)
                        Spacer()
                    }
                    .foregroundStyle(Theme.muted)
                    .padding(.horizontal, 8)
                    .frame(height: 32)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                RecordingStatus()
            }
        }
        .padding(EdgeInsets(top: 46, leading: 12, bottom: 16, trailing: 12))
    }
}

/// Bottom of the sidebar: whether Trace is recording, and what.
struct RecordingStatus: View {
    @EnvironmentObject private var watcher: ActivityWatcher

    private var state: (title: String, color: Color) {
        if watcher.isPaused { return (L("Paused"), Palette.color(3)) }
        if watcher.isIdle { return (L("Away"), Theme.muted) }
        return (L("Recording"), Theme.accent)
    }

    var body: some View {
        HStack(spacing: 8) {
            Circle().fill(state.color).frame(width: 8, height: 8)
            VStack(alignment: .leading, spacing: 0) {
                Text(state.title).fontWeight(.semibold)
                if let current = watcher.current {
                    Text(current.headline)
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.muted)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }
            Spacer(minLength: 4)
            IconButton(symbol: watcher.isPaused ? "play.fill" : "pause.fill",
                       label: watcher.isPaused ? L("Resume recording") : L("Pause recording")) {
                watcher.isPaused.toggle()
            }
        }
        .padding(10)
        .background(Theme.panel, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(Theme.line))
    }
}

/// Explains why Accessibility access is needed and how to grant it.
struct PermissionBanner: View {
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "lock.shield").font(.system(size: 20)).foregroundStyle(Theme.accent)
            VStack(alignment: .leading, spacing: 2) {
                Text(L("Accessibility permission needed")).fontWeight(.semibold)
                Text(L("Trace uses it to read window titles, file paths and page URLs. It never records keystrokes or screen contents."))
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.muted)
                    .lineLimit(2)
            }
            .layoutPriority(1)
            Spacer(minLength: 12)
            Button(L("Open System Settings")) {
                AXReader.requestTrust()
                AXReader.openSettings()
            }
            .buttonStyle(.trProminent)
        }
        .padding(14)
        .background(Theme.soft, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .padding(EdgeInsets(top: 20, leading: 28, bottom: 0, trailing: 28))
    }
}
