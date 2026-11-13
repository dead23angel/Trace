import AppKit
import SwiftUI
import TraceCore

struct SettingsView: View {
    @EnvironmentObject private var model: AppModel

    private enum Tab: String, CaseIterable, Identifiable {
        case general, recording, privacy, sync, data
        var id: String { rawValue }

        var title: String {
            switch self {
            case .general: return L("General")
            case .recording: return L("What is recorded")
            case .privacy: return L("Privacy and exclusions")
            case .sync: return L("Sync")
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
                case .sync: sync
                case .data: data
                }
                Spacer(minLength: 0)
                Text(model.syncFolder == nil
                     ? L("All data stays on this Mac. Trace never connects to the network.")
                     : L("Trace itself never connects to the network. Records are also written to your sync folder."))
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
        row(L("Web addresses"), L("The page address in browsers, stored without the query string")) {
            Toggle(L("Web addresses"), isOn: $model.captureURLs).toggleStyle(.switch).labelsHidden()
        }
        row(L("Sound and calls"), L("Which apps are playing sound or using the microphone, also in the background. Not what is played or said."), last: true) {
            Toggle(L("Sound and calls"), isOn: $model.captureBackground).toggleStyle(.switch).labelsHidden()
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

    @ViewBuilder private var sync: some View {
        let iCloud = model.iCloudFolder
        let usesICloud = model.syncFolder != nil && model.syncFolder == iCloud?.path
        row(L("Sync with iCloud"),
            iCloud == nil ? L("iCloud Drive is not turned on for this Mac. Turn it on in System Settings, or use another folder below.")
                          : L("Keeps your records backed up in iCloud Drive and in step across your Macs. Nothing to set up."),
            last: model.syncFolder == nil) {
            Toggle(L("Sync with iCloud"), isOn: Binding(
                get: { usesICloud },
                set: { on in
                    if on, let iCloud { model.enableSync(folder: iCloud) } else { model.disableSync() }
                }))
                .toggleStyle(.switch)
                .labelsHidden()
                .disabled(iCloud == nil || (model.syncFolder != nil && !usesICloud))
        }
        if let folder = model.syncFolder {
            row(usesICloud ? L("Stored in") : L("Sync folder"), Analyzer.abbreviate(folder), mono: true) {
                Button(L("Show in Finder")) {
                    NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: folder)])
                }
                .buttonStyle(.trBordered)
            }
            row(L("Status"), syncStatus) {
                Button(model.isSyncing ? L("Syncing…") : L("Sync now")) { model.syncNow() }
                    .buttonStyle(.trBordered)
                    .disabled(model.isSyncing)
            }
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Text(L("Macs")).fontWeight(.semibold)
                    Text(L("Click a name to change it, for example Home and Lab"))
                        .font(.system(size: 12)).foregroundStyle(Theme.muted)
                }
                deviceRow(name: $model.deviceName, placeholder: Host.current().localizedName ?? "Mac",
                          note: L("this Mac")) { model.syncNow() }
                ForEach(model.devices) { device in
                    DeviceNameRow(device: device)
                }
            }
            if !usesICloud {
                Hairline()
                row(L("Stop syncing"), L("Removes the other Macs' records from this Mac. The files in the folder are kept."), last: true) {
                    Button(L("Stop syncing")) { model.disableSync() }.buttonStyle(.trBordered)
                }
            }
        } else {
            if let error = model.syncError {
                Text(error).font(.system(size: 12)).foregroundStyle(Palette.color(4))
            }
            Text(L("Sync is off until you turn it on. Your records are then also stored in iCloud Drive as readable files, in a folder named Trace. Turning it off removes the other Macs' records from this Mac and leaves the files in place."))
                .font(.system(size: 12))
                .foregroundStyle(Theme.muted)
                .fixedSize(horizontal: false, vertical: true)
            Button(L("Use another folder instead…")) { model.chooseSyncFolder() }
                .buttonStyle(.trLink)
                .font(.system(size: 12))
        }
    }

    private var syncStatus: String {
        if let error = model.syncError { return error }
        if let last = model.lastSync { return String(format: L("Last synced %@"), Fmt.time(last)) }
        return model.isSyncing ? L("Syncing…") : L("Not synced yet")
    }

    private func deviceRow(name: Binding<String>, placeholder: String, note: String,
                           commit: @escaping () -> Void) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "laptopcomputer").foregroundStyle(Theme.muted).frame(width: 20)
            TextField(placeholder, text: name)
                .textFieldStyle(.plain)
                .onSubmit(commit)
                .padding(.horizontal, 8)
                .frame(width: 220, height: 26)
                .overlay(RoundedRectangle(cornerRadius: 6, style: .continuous).strokeBorder(Theme.line))
            Spacer()
            Text(note).font(.system(size: 12)).foregroundStyle(Theme.muted)
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

/// One other Mac in the Sync pane, with a name that can be changed here.
private struct DeviceNameRow: View {
    @EnvironmentObject private var model: AppModel
    let device: SyncedDevice
    @State private var name = ""

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "laptopcomputer").foregroundStyle(Theme.muted).frame(width: 20)
            TextField(device.name, text: $name)
                .textFieldStyle(.plain)
                .onSubmit { model.renameDevice(device, to: name) }
                .padding(.horizontal, 8)
                .frame(width: 220, height: 26)
                .overlay(RoundedRectangle(cornerRadius: 6, style: .continuous).strokeBorder(Theme.line))
            if name != device.displayName {
                Button(L("Save")) { model.renameDevice(device, to: name) }
                    .buttonStyle(TRButtonStyle(kind: .bordered, height: 26))
            }
            Spacer()
            Text(device.lastSeen.map { String(format: L("last synced %@"), Fmt.dateTime($0)) } ?? "")
                .font(.system(size: 12))
                .foregroundStyle(Theme.muted)
        }
        .onAppear { name = device.displayName }
        .onChange(of: device.displayName) { name = device.displayName }
    }
}
