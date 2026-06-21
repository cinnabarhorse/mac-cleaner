import MacCleanerCore
import SwiftUI

struct ContentView: View {
    @Bindable var store: CleanerStore

    var body: some View {
        NavigationSplitView {
            SidebarView(store: store)
                .navigationSplitViewColumnWidth(min: 260, ideal: 300, max: 360)
        } content: {
            ResultsPane(store: store)
                .navigationSplitViewColumnWidth(min: 480, ideal: 620)
        } detail: {
            DetailPane(store: store)
                .navigationSplitViewColumnWidth(min: 320, ideal: 420)
        }
        .toolbar {
            ToolbarItemGroup {
                Button {
                    store.addCustomFolder()
                } label: {
                    Label("Add Folder", systemImage: "folder.badge.plus")
                }

                Button {
                    store.isScanning ? store.stopScan() : store.startScan()
                } label: {
                    Label(store.isScanning ? "Stop" : "Scan", systemImage: store.isScanning ? "stop.fill" : "magnifyingglass")
                }
                .disabled(!store.isScanning && !store.canScan)
            }
        }
        .sheet(item: $store.pendingDeletionItem) { item in
            DeleteConfirmationView(
                item: item,
                isDeleting: store.isDeleting,
                onCancel: { store.pendingDeletionItem = nil },
                onConfirm: { store.movePendingItemToTrash() }
            )
        }
    }
}
