import MacCleanerFeatures
import SwiftUI

struct SettingsView: View {
    @Bindable var store: CleanerStore

    var body: some View {
        Form {
            Section("Scan") {
                Toggle("Show Hidden Files", isOn: $store.showHiddenFiles)
                Toggle("Show Package Contents", isOn: $store.showPackageContents)
                Toggle("Show Symlinks", isOn: $store.showSymbolicLinks)
            }

            Section("Results") {
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
        }
        .formStyle(.grouped)
        .padding()
        .frame(width: 420)
        .disabled(!store.canEditConfiguration)
    }
}
