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
        store.isScanning ? .red : .accentColor
    }

    private var title: String {
        store.isScanning ? "Stop" : "Scan"
    }

    private var systemImage: String {
        store.isScanning ? "stop.fill" : "magnifyingglass"
    }

    var body: some View {
        Button {
            store.isScanning ? store.stopScan() : store.startScan()
        } label: {
            Label(title, systemImage: systemImage)
                .labelStyle(.titleAndIcon)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(tint)
                .padding(.horizontal, 10)
                .frame(height: 28)
                .background {
                    Capsule(style: .continuous)
                        .fill(tint.opacity(0.12))
                }
                .overlay {
                    Capsule(style: .continuous)
                        .strokeBorder(tint.opacity(0.24), lineWidth: 0.75)
                }
                .opacity(isDisabled ? 0.45 : 1)
        }
        .buttonStyle(.plain)
        .disabled(isDisabled)
        .fixedSize()
        .accessibilityLabel(store.isScanning ? "Stop Scan" : "Scan")
    }
}
