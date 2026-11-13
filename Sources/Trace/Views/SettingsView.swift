import AppKit
import SwiftUI
import TraceCore

struct SettingsView: View {
    @EnvironmentObject private var model: AppModel

    private enum Tab: String, CaseIterable, Identifiable {
        case general, recording, privacy, data
        var id: String { rawValue }

        var title: String {
            switch self {
            case .general: return L("General")
            case .recording: return L("What is recorded")
            case .privacy: return L("Privacy and exclusions")
            case .data: return L("Data and export")
            }
        }
    }

    @State private var tab: Tab = .general
    @State private var confirmsErase = false

    var body: some View {
        HStack(spacing: 0) {
            VStack(spacing: 2) {
                ForEach(Tab.allCases) { item in
                    let isOn = tab == item
                    Button { tab = item } label: {
                        Text(item.title)
                            .fontWeight(isOn ? .semibold : .medium)
                            .foregroundStyle(isOn ? Theme.ink : Theme.muted)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 10)
                            .frame(height: 32)
                            .background(isOn ? Theme.hover : .clear, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(isOn ? .isSelected : [])
                }
                Spacer()
            }
            .padding(EdgeInsets(top: 16, leading: 10, bottom: 16, trailing: 10))
            .frame(width: 180)
            .background(Theme.side)
            Rectangle().fill(Theme.line).frame(width: 1)

            VStack(alignment: .leading, spacing: 18) {
                Text(tab.title).font(.system(size: 18, weight: .bold))
                switch tab {
                case .general: general
                case .recording: recording
                case .privacy: privacy
                case .data: data
                }
                Spacer(minLength: 0)
                Text(L("All data stays on this Mac. Trace never connects to the network."))
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.muted)
            }
            .padding(EdgeInsets(top: 24, leading: 28, bottom: 24, trailing: 28))
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(Theme.panel)
        }
        .frame(width: 760, height: 520)
        .font(.system(size: 13))
        .foregroundStyle(Theme.ink)
    }

    // MARK: Panes

    @ViewBuilder private var general: some View {
        row(L("Appearance"), L("Light, dark, or follow the macOS setting")) {
            Segmented(options: [(Appearance.light, L("Light")), (.dark, L("Dark")), (.system, L("System"))],
                      selection: $model.appearance)
        }
        row(L("Language"), L("Interface language; takes effect at once")) {
            Picker(L("Language"), selection: $model.language) {
                Text(L("System")).tag(AppLanguage.system)
                Text("简体中文").tag(AppLanguage.zhHans)
                Text("English").tag(AppLanguage.en)
            }
            .labelsHidden()
            .fixedSize()
        }
        row(L("Launch at login"), L("Start recording from the menu bar after you log in")) {
            Toggle(L("Launch at login"), isOn: Binding(get: { model.launchAtLogin }, set: { model.setLaunchAtLogin($0) }))
                .toggleStyle(.switch)
                .labelsHidden()
        }
        row(L("Idle time"), L("With no keyboard or mouse input for this long, you count as away"), last: true) {
            Picker(L("Idle time"), selection: $model.idleMinutes) {
                ForEach([1, 3, 5, 10, 15], id: \.self) { Text(String(format: L("%d min"), $0)).tag($0) }
            }
            .labelsHidden()
            .fixedSize()
        }
    }

    @ViewBuilder private var recording: some View {
        row(L("Window titles"), L("The title of the window in front, e.g. a document or chat name")) {
            Toggle(L("Window titles"), isOn: $model.captureTitles).toggleStyle(.switch).labelsHidden()
        }
        row(L("File paths"), L("The file open in document-based apps")) {
            Toggle(L("File paths"), isOn: $model.captureFiles).toggleStyle(.switch).labelsHidden()
        }
        row(L("Web addresses"), L("The page address in browsers, stored without the query string"), last: true) {
            Toggle(L("Web addresses"), isOn: $model.captureURLs).toggleStyle(.switch).labelsHidden()
        }
        Text(L("The app in front and how long you stay are always recorded. Keystrokes and screen contents never are."))
            .font(.system(size: 12))
            .foregroundStyle(Theme.muted)
    }

    @ViewBuilder private var privacy: some View {
        row(L("Excluded apps"), L("Time in these apps is not recorded at all"), last: model.excludedApps.isEmpty) {
            Menu(L("Add app")) {
                ForEach(candidates, id: \.bundleID) { app in
                    Button(app.name) { model.excludedApps.append(app.bundleID) }
                }
            }
            .fixedSize()
        }
        ScrollView {
            VStack(spacing: 0) {
                ForEach(model.excludedApps, id: \.self) { bundleID in
                    HStack(spacing: 10) {
                        AppIcon(bundleID: bundleID, size: 22)
                        Text(Self.appName(bundleID))
                        Text(bundleID).font(Theme.mono).foregroundStyle(Theme.muted).lineLimit(1)
                        Spacer()
                        Button(L("Remove")) { model.excludedApps.removeAll { $0 == bundleID } }
                            .buttonStyle(TRButtonStyle(kind: .bordered, height: 26))
                    }
                    .padding(.vertical, 8)
                    Hairline()
                }
            }
        }
    }

    @ViewBuilder private var data: some View {
        row(L("Data location"), model.databaseURL.map { Analyzer.abbreviate($0.path) } ?? L("In memory only"), mono: true) {
            Button(L("Show in Finder")) { model.revealDatabase() }
                .buttonStyle(.trBordered)
                .disabled(model.databaseURL == nil)
        }
        row(L("Export"), L("Every record as a CSV file, one row per stay")) {
            Button(L("Export CSV")) {
                model.exportCSV(DateInterval(start: .distantPast, end: Date()), name: L("All records"))
            }
            .buttonStyle(.trBordered)
        }
        row(L("Erase records"), L("Deletes every recorded stay. Tags and rules are kept. This cannot be undone."), last: true) {
            Button(L("Erase…")) { confirmsErase = true }
                .buttonStyle(.trBordered)
                .foregroundStyle(Palette.color(4))
        }
        .confirmationDialog(L("Erase every record?"), isPresented: $confirmsErase) {
            Button(L("Erase all records"), role: .destructive) { model.eraseAllRecords() }
        } message: {
            Text(L("Deletes every recorded stay. Tags and rules are kept. This cannot be undone."))
        }
    }

    // MARK: Helpers

    private func row<Control: View>(_ title: String, _ note: String, mono: Bool = false, last: Bool = false,
                                    @ViewBuilder control: () -> Control) -> some View {
        VStack(spacing: 16) {
            HStack(spacing: 16) {
                VStack(alignment: .leading, spacing: 0) {
                    Text(title).fontWeight(.semibold)
                    Text(note).font(mono ? Theme.mono : .system(size: 12)).foregroundStyle(Theme.muted)
                        .lineLimit(2).truncationMode(.middle)
                }
                Spacer(minLength: 12)
                control()
            }
            if !last { Hairline() }
        }
    }

    private var candidates: [(name: String, bundleID: String)] {
        NSWorkspace.shared.runningApplications
            .filter { $0.activationPolicy == .regular }
            .compactMap { app in
                guard let id = app.bundleIdentifier, id != Bundle.main.bundleIdentifier,
                      !model.excludedApps.contains(id) else { return nil }
                return (app.localizedName ?? id, id)
            }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    private static func appName(_ bundleID: String) -> String {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else { return bundleID }
        return FileManager.default.displayName(atPath: url.path).replacingOccurrences(of: ".app", with: "")
    }
}
