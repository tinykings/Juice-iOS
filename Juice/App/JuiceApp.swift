import AppIntents
import SwiftUI

@main
struct JuiceApp: App {
    @StateObject private var store = TaskStore.shared
    @AppStorage(ThemeChoice.storageKey) private var theme = ThemeChoice.system
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(store)
                .tint(Palette.accent)
                .preferredColorScheme(theme.colorScheme)
        }
        .onChange(of: scenePhase) { _, phase in
            guard phase == .active else { return }
            Task {
                await store.refresh()
                // Siri's "Complete <task> in Juice" offers the current tasks.
                JuiceShortcuts.updateAppShortcutParameters()
            }
        }
    }
}
