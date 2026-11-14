import SwiftUI

@main
struct TraceApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @StateObject private var model = AppModel()

    var body: some Scene {
        Window("Trace", id: "main") {
            RootView()
                .environmentObject(model)
                .environmentObject(model.watcher)
                .frame(minWidth: 1080, minHeight: 680)
                // Rebuild the whole tree when the language changes so every
                // string is looked up again.
                .id(model.language)
                .task { Screenshots.runIfRequested(model: model) }
        }
        .defaultSize(width: 1360, height: 900)
        .windowStyle(.hiddenTitleBar)

        MenuBarExtra {
            MenuBarView()
                .environmentObject(model)
                .environmentObject(model.watcher)
                .id(model.language)
        } label: {
            MenuBarLabel()
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsView()
                .environmentObject(model)
                .environmentObject(model.watcher)
                .id(model.language)
        }
    }
}

/// The menu bar icon. It is always there, so it is also where the app
/// learns how to open its main window when the Dock icon is clicked.
private struct MenuBarLabel: View {
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Image(systemName: "waveform.path.ecg")
            .onAppear { AppDelegate.shared?.openMain = { openWindow(id: "main") } }
            .task {
                // The delegate may finish launching after this view appears.
                try? await Task.sleep(for: .seconds(0.5))
                AppDelegate.shared?.openMain = { openWindow(id: "main") }
            }
    }
}
