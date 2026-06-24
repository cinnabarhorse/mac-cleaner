import AppKit
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
        .onDeleteCommand {
            store.requestDeletionForSelection()
        }
        .background {
            DeleteKeyMonitorView(isEnabled: store.canRequestDeletionForSelection) {
                store.requestDeletionForSelection()
            }
            .frame(width: 0, height: 0)
        }
        .sheet(item: $store.pendingDeletionPlan) { plan in
            DeleteConfirmationView(
                plan: plan,
                isDeleting: store.isDeleting,
                onCancel: { store.pendingDeletionPlan = nil },
                onConfirm: { store.movePendingItemsToTrash() }
            )
        }
    }
}

private struct DeleteKeyMonitorView: NSViewRepresentable {
    let isEnabled: Bool
    let action: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context: Context) -> NSView {
        context.coordinator.isEnabled = isEnabled
        context.coordinator.action = action
        context.coordinator.install()
        return NSView(frame: .zero)
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        context.coordinator.isEnabled = isEnabled
        context.coordinator.action = action
    }

    static func dismantleNSView(_ nsView: NSView, coordinator: Coordinator) {
        coordinator.uninstall()
    }

    final class Coordinator {
        var isEnabled = false
        var action: () -> Void = {}
        private var monitor: Any?

        func install() {
            guard monitor == nil else {
                return
            }

            monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
                guard let self, self.isEnabled, Self.isDeleteKey(event), !Self.isTextEditing else {
                    return event
                }

                self.action()
                return nil
            }
        }

        func uninstall() {
            if let monitor {
                NSEvent.removeMonitor(monitor)
            }
            monitor = nil
        }

        private static func isDeleteKey(_ event: NSEvent) -> Bool {
            let deleteKeyCode: UInt16 = 51
            let forwardDeleteKeyCode: UInt16 = 117
            let relevantModifiers = event.modifierFlags.intersection([.command, .option, .control])
            return relevantModifiers.isEmpty && (event.keyCode == deleteKeyCode || event.keyCode == forwardDeleteKeyCode)
        }

        private static var isTextEditing: Bool {
            MainActor.assumeIsolated {
                guard let firstResponder = NSApp.keyWindow?.firstResponder else {
                    return false
                }

                return firstResponder is NSTextView || firstResponder is NSTextField
            }
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
