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

                Button("Move Selected to Trash") {
                    store.requestDeletionForSelection()
                }
                .keyboardShortcut(.delete, modifiers: [])
                .disabled(!store.canRequestDeletionForSelection)

                Divider()

                Button("Select Safe Picks") {
                    store.selectSafePicks()
                }
                .keyboardShortcut("s", modifiers: [.command, .shift])
                .disabled(!store.canSelectSafePicks)

                Button("Export Markdown Report") {
                    store.exportReport(as: .markdown)
                }
                .disabled(store.report == nil)

                Button("Export CSV Report") {
                    store.exportReport(as: .csv)
                }
                .disabled(store.report == nil)
            }
        }

        Settings {
            SettingsView(store: store)
        }
    }
}
