import AppKit
import MacCleanerCore
import MacCleanerFeatures
import SwiftUI

struct SidebarView: View {
    @Bindable var store: CleanerStore

    var body: some View {
        List {
            Section("Scopes") {
                ForEach(ScanScope.allCases) { scope in
                    Toggle(isOn: binding(for: scope)) {
                        Label(scope.title, systemImage: scope.systemImage)
                    }
                    .toggleStyle(.checkbox)
                    .disabled(!store.canEditConfiguration)
                }
            }

            Section("Custom") {
                Button {
                    store.addCustomFolders(FolderPicker.chooseFolders())
                } label: {
                    Label("Add Folder", systemImage: "folder.badge.plus")
                }
                .disabled(!store.canEditConfiguration)

                ForEach(store.customRoots) { root in
                    CustomRootRow(root: root) {
                        store.removeCustomRoot(root)
                    }
                }
            }
            .disabled(!store.canEditConfiguration)

            Section("Options") {
                Toggle("Show Hidden Files", isOn: $store.showHiddenFiles)
                    .toggleStyle(.checkbox)

                Toggle("Show Package Contents", isOn: $store.showPackageContents)
                    .toggleStyle(.checkbox)

                Toggle("Show Symlinks", isOn: $store.showSymbolicLinks)
                    .toggleStyle(.checkbox)

                Picker("Minimum Size", selection: $store.minimumItemSizeBytes) {
                    Text("1 MB").tag(Int64(1 * 1_024 * 1_024))
                    Text("10 MB").tag(Int64(10 * 1_024 * 1_024))
                    Text("100 MB").tag(Int64(100 * 1_024 * 1_024))
                    Text("1 GB").tag(Int64(1_024 * 1_024 * 1_024))
                }

                Picker("Rows", selection: $store.maxReturnedItems) {
                    Text("1,000").tag(1_000)
                    Text("5,000").tag(5_000)
                    Text("10,000").tag(10_000)
                }
            }
            .disabled(!store.canEditConfiguration)
        }
        .listStyle(.sidebar)
    }

    private func binding(for scope: ScanScope) -> Binding<Bool> {
        Binding(
            get: { store.selectedScopes.contains(scope) },
            set: { store.setScope(scope, enabled: $0) }
        )
    }
}

private struct CustomRootRow: View {
    let root: ScanRoot
    let onRemove: () -> Void

    var body: some View {
        HStack {
            Label {
                Text(root.title)
                    .lineLimit(1)
            } icon: {
                Image(systemName: "folder")
            }

            Spacer(minLength: 8)

            Button(action: onRemove) {
                Image(systemName: "minus.circle")
            }
            .buttonStyle(.plain)
            .frame(minWidth: 44, minHeight: 44)
            .accessibilityLabel("Remove folder at \(root.url.path)")
            .accessibilityInputLabels(["Remove folder at \(root.url.path)"])
        }
        .help(root.url.path)
    }
}

@MainActor
private enum FolderPicker {
    static func chooseFolders() -> [URL] {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = false
        panel.prompt = "Add"
        return panel.runModal() == .OK ? panel.urls : []
    }
}
