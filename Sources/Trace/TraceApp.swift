import SwiftUI

@main
struct TraceApp: App {
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
        }
        .defaultSize(width: 1360, height: 900)
        .windowStyle(.hiddenTitleBar)

        MenuBarExtra {
            MenuBarView()
                .environmentObject(model)
                .environmentObject(model.watcher)
                .id(model.language)
        } label: {
            Image(systemName: "waveform.path.ecg")
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
