import SwiftUI
import TraceCore

/// Time and distinct apps per tag over the current week.
struct TagWeekStats {
    var seconds: [Int64: TimeInterval] = [:]
    var apps: [Int64: Set<String>] = [:]
}

struct TagsView: View {
    @EnvironmentObject private var model: AppModel
    @State private var stats = TagWeekStats()
    @State private var showsForm = false

    private let columns = [GridItem(.adaptive(minimum: 230), spacing: 12, alignment: .top)]

    var body: some View {
        let presets = model.tags.filter(\.isPreset)
        let customs = model.tags.filter { !$0.isPreset }
        Page {
            PageHeader(title: L("Tags"),
                       subtitle: L("A record can carry several tags; automatic ones can always be changed")) {
                Button(L("New tag")) { showsForm = true }.buttonStyle(.trProminent)
            }
            VStack(alignment: .leading, spacing: 10) {
                SectionTitle(title: L("Preset tags"),
                             note: L("Matched from the category each app declares to macOS and from well-known sites"))
                LazyVGrid(columns: columns, spacing: 12) {
                    ForEach(presets) { tag in TagCard(tag: tag, stats: stats) }
                }
            }
            VStack(alignment: .leading, spacing: 10) {
                SectionTitle(title: L("Custom tags"),
                             note: L("Name it, pick a colour, apply it by hand or add a rule to apply it automatically"))
                LazyVGrid(columns: columns, spacing: 12) {
                    ForEach(customs) { tag in TagCard(tag: tag, stats: stats) }
                    Button { showsForm = true } label: {
                        Text(L("New tag"))
                            .fontWeight(.semibold)
                            .foregroundStyle(Theme.accent)
                            .frame(maxWidth: .infinity, minHeight: 124)
                            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .strokeBorder(Theme.line, style: StrokeStyle(lineWidth: 1, dash: [4, 4])))
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
            if showsForm {
                NewTagForm { showsForm = false }
            }
        }
        .task(id: model.revision) { stats = load() }
    }

    private func load() -> TagWeekStats {
        var stats = TagWeekStats()
        let week = model.weekInterval
        for event in model.events(in: week) {
            let seconds = Analyzer.clipped(event, to: week)
            for tag in model.tagger.tags(for: event) {
                guard let id = tag.id else { continue }
                stats.seconds[id, default: 0] += seconds
                stats.apps[id, default: []].insert(event.bundleID)
            }
        }
        return stats
    }
}

private struct TagCard: View {
    @EnvironmentObject private var model: AppModel
    let tag: Tag
    let stats: TagWeekStats

    @State private var editsGoal = false

    private var rules: [Rule] { model.rules.filter { $0.tagID == tag.id } }
    private var goal: Goal? { model.goals.first { $0.tagID == tag.id } }

    private func chip(_ text: String, symbol: String) -> some View {
        HStack(spacing: 4) {
            Image(systemName: symbol).font(.system(size: 9, weight: .semibold))
            Text(text).font(.system(size: 11, weight: .medium)).lineLimit(1)
        }
        .foregroundStyle(Theme.muted)
        .padding(.horizontal, 7)
        .frame(height: 20)
        .background(Theme.bg, in: Capsule())
        .contentShape(Capsule())
    }

    var body: some View {
        let id = tag.id ?? 0
        Card(padding: .hv(16, 14)) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    Swatch(tag, size: 12, round: true)
                    Text(tag.displayName).font(.system(size: 15, weight: .bold)).lineLimit(1)
                    Spacer()
                    if tag.isPreset {
                        Toggle(tag.displayName, isOn: Binding(get: { tag.enabled }, set: { model.setTag(tag, enabled: $0) }))
                            .toggleStyle(.switch)
                            .controlSize(.small)
                            .labelsHidden()
                    } else {
                        Menu {
                            Button(L("Edit rules")) { model.pane = .rules }
                            Button(L("Delete tag"), role: .destructive) { model.deleteTag(tag) }
                        } label: {
                            Image(systemName: "ellipsis").font(.system(size: 12, weight: .bold)).foregroundStyle(Theme.muted)
                        }
                        .menuStyle(.borderlessButton)
                        .menuIndicator(.hidden)
                        .frame(width: 28, height: 28)
                        .overlay(RoundedRectangle(cornerRadius: 7, style: .continuous).strokeBorder(Theme.line))
                        .accessibilityLabel(String(format: L("Edit tag %@"), tag.displayName))
                    }
                }
                Text(ruleSummary)
                    .font(tag.isPreset ? .system(size: 12) : Theme.mono)
                    .foregroundStyle(Theme.muted)
                    .lineLimit(2)
                    .frame(maxWidth: .infinity, minHeight: 34, alignment: .topLeading)
                HStack(spacing: 6) {
                    Menu {
                        ForEach(TagRole.allCases, id: \.self) { role in
                            Button(role.title) { model.setRole(role, for: tag) }
                        }
                    } label: {
                        chip(tag.role.title, symbol: tag.role == .focus ? "scope" : (tag.role == .distraction ? "moon.zzz" : "circle.dashed"))
                    }
                    .menuStyle(.button)
                    .buttonStyle(.plain)
                    .menuIndicator(.hidden)
                    .fixedSize()
                    .help(L("How this tag counts when judging focus"))
                    Button { editsGoal = true } label: {
                        chip(goal?.summary ?? L("Set goal"), symbol: "target")
                    }
                    .buttonStyle(.plain)
                    .popover(isPresented: $editsGoal) {
                        GoalEditor(tag: tag) { editsGoal = false }.environmentObject(model)
                    }
                    Spacer(minLength: 0)
                }
                Hairline()
                HStack {
                    Text(footnote).foregroundStyle(Theme.muted)
                    Spacer()
                    Text(L("This week") + " " + Fmt.duration(stats.seconds[id] ?? 0)).fontWeight(.semibold)
                }
                .font(.system(size: 12))
            }
            .opacity(tag.enabled ? 1 : 0.5)
        }
    }

    private var footnote: String {
        if tag.isPreset {
            return String(format: L("Matched %d apps"), stats.apps[tag.id ?? 0]?.count ?? 0)
        }
        return rules.isEmpty ? L("Manual only") : String(format: L("Automatic · %d rules"), rules.count)
    }

    private var ruleSummary: String {
        if rules.isEmpty { return L("No rules") }
        if !tag.isPreset, let rule = rules.first {
            return "\(rule.field.displayName) \(rule.op.displayName) \(rule.value)"
        }
        return rules.prefix(5).map(\.shortValue).joined(separator: L(", "))
    }
}

extension Rule {
    /// Names for the preset apps, used when the app is not installed.
    private static let knownApps = [
        "com.figma.Desktop": "Figma", "company.thebrowser.Browser": "Arc", "com.bohemiancoding.sketch3": "Sketch",
        "com.googlecode.iterm2": "iTerm", "com.tinyspeck.slackmacgap": "Slack", "com.tencent.xinWeChat": "WeChat",
        "us.zoom.xos": "Zoom", "com.microsoft.teams2": "Teams", "com.electron.lark": "Lark",
        "com.valvesoftware.steam": "Steam", "com.epicgames.EpicGamesLauncher": "Epic Games",
        "org.mozilla.firefox": "Firefox", "com.kingsoft.wpsoffice.mac": "WPS Office", "dev.zed.Zed": "Zed",
        "com.brave.Browser": "Brave", "net.battle.app": "Battle.net", "com.mojang.minecraftlauncher": "Minecraft",
        "com.todesktop.230313mzl4w4u92": "Cursor", "com.tencent.qq": "QQ", "com.tencent.meeting": "Tencent Meeting", "com.microsoft.VSCode": "VS Code", "com.apple.MobileSMS": "Messages",
    ]

    /// The value in a readable form: categories without their prefix, bundle
    /// identifiers as the app's name when it is installed.
    var shortValue: String {
        switch field {
        case .category: return value.replacingOccurrences(of: "public.app-category.", with: "")
        case .app:
            if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: value) {
                return FileManager.default.displayName(atPath: url.path).replacingOccurrences(of: ".app", with: "")
            }
            return Self.knownApps[value] ?? value.split(separator: ".").last.map(String.init) ?? value
        default: return value
        }
    }
}

struct NewTagForm: View {
    @EnvironmentObject private var model: AppModel
    var done: () -> Void = {}
    @State private var name = ""
    @State private var colorIndex = 6
    @State private var field: RuleField = .path
    @State private var op: RuleOp = .contains
    @State private var value = ""
    @FocusState private var nameFocused: Bool

    var body: some View {
        Card(padding: .hv(20, 18)) {
            HStack(alignment: .bottom, spacing: 14) {
                labeled(L("Name")) {
                    TextField(L("e.g. Thesis"), text: $name)
                        .textFieldStyle(.plain)
                        .focused($nameFocused)
                        .padding(.horizontal, 10)
                        .frame(width: 160, height: 32)
                        .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(Theme.line))
                }
                labeled(L("Colour")) {
                    HStack(spacing: 6) {
                        ForEach(Palette.colors.indices, id: \.self) { index in
                            Button { colorIndex = index } label: {
                                Circle().fill(Palette.color(index)).frame(width: 18, height: 18)
                                    .padding(3)
                                    .overlay(Circle().strokeBorder(colorIndex == index ? Theme.ink : .clear, lineWidth: 2))
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("\(L("Colour")) \(index + 1)")
                            .accessibilityAddTraits(colorIndex == index ? .isSelected : [])
                        }
                    }
                    .frame(height: 32)
                }
                labeled(L("Apply automatically when (leave empty to tag by hand only)")) {
                    RuleFields(field: $field, op: $op, value: $value)
                }
                Button(L("Save")) {
                    model.addTag(name: name, colorIndex: colorIndex, field: field, op: op, value: value)
                    name = ""
                    value = ""
                    done()
                }
                .buttonStyle(TRButtonStyle(kind: .prominent, height: 32))
                .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                Button(L("Cancel"), action: done).buttonStyle(TRButtonStyle(kind: .bordered, height: 32))
            }
        }
        .onAppear { nameFocused = true }
    }

    private func labeled<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.system(size: 12)).foregroundStyle(Theme.muted).lineLimit(1)
            content()
        }
    }
}

/// Field, comparison and value of one rule, as three inline controls.
struct RuleFields: View {
    @Binding var field: RuleField
    @Binding var op: RuleOp
    @Binding var value: String
    var onSubmit: () -> Void = {}

    var body: some View {
        HStack(spacing: 6) {
            Picker(L("Field"), selection: $field) {
                ForEach(RuleField.allCases, id: \.self) { Text($0.displayName).tag($0) }
            }
            .labelsHidden()
            .fixedSize()
            Picker(L("Match"), selection: $op) {
                ForEach(RuleOp.allCases, id: \.self) { Text($0.displayName).tag($0) }
            }
            .labelsHidden()
            .fixedSize()
            TextField(field.placeholder, text: $value)
                .textFieldStyle(.plain)
                .font(Theme.mono)
                .onSubmit(onSubmit)
                .padding(.horizontal, 10)
                .frame(minWidth: 140, maxWidth: .infinity)
                .frame(height: 32)
                .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(Theme.line))
        }
    }
}
