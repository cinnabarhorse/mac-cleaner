import MacCleanerCore
import MacCleanerFeatures
import SwiftUI

@main
struct MacCleanerApp: App {
    @State private var store = CleanerStore()

    var body: some Scene {
        Window("Mac Cleaner", id: "main") {
            ContentView(store: store)
                .frame(minWidth: 1_050, minHeight: 680)
        }
        .commands {
            CommandGroup(replacing: .newItem) {}

            CommandMenu("Cleaner") {
                Button("Scan") {
                    store.startScan()
                }
                .keyboardShortcut("r", modifiers: [.command])
                .disabled(!store.canScan)

                Button("Stop Scan") {
                    store.stopScan()
                }
                .keyboardShortcut(".", modifiers: [.command])
                .disabled(!store.canStopScan)
            }
        }

        Settings {
            SettingsView(store: store)
        }
    }
}
