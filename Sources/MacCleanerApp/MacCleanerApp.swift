import MacCleanerCore
import SwiftUI

@main
struct MacCleanerApp: App {
    @State private var store = CleanerStore()

    var body: some Scene {
        WindowGroup {
            ContentView(store: store)
                .frame(minWidth: 1_050, minHeight: 680)
        }
        .commands {
            CommandGroup(after: .appInfo) {
                Button("Scan") {
                    store.startScan()
                }
                .keyboardShortcut("r", modifiers: [.command])
                .disabled(store.isScanning)

                Button("Stop Scan") {
                    store.stopScan()
                }
                .keyboardShortcut(".", modifiers: [.command])
                .disabled(!store.isScanning)
            }
        }

        Settings {
            SettingsView(store: store)
        }
    }
}
