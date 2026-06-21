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

                ScanToolbarButton(store: store)
            }
        }
        .task {
            store.autoStartScanIfNeeded()
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

private struct ScanToolbarButton: View {
    @Bindable var store: CleanerStore

    private var isDisabled: Bool {
        !store.isScanning && !store.canScan
    }

    private var tint: Color {
        store.isScanning ? .red : .blue
    }

    var body: some View {
        Button {
            store.isScanning ? store.stopScan() : store.startScan()
        } label: {
            Label(store.isScanning ? "Stop" : "Scan", systemImage: store.isScanning ? "stop.fill" : "magnifyingglass")
                .labelStyle(.titleAndIcon)
                .font(.headline)
                .foregroundStyle(.white)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(tint)
                }
                .opacity(isDisabled ? 0.45 : 1)
        }
        .buttonStyle(.plain)
        .disabled(isDisabled)
        .accessibilityLabel(store.isScanning ? "Stop Scan" : "Scan")
    }
}
