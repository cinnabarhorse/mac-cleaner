import MacCleanerCore
import SwiftUI

struct DetailPane: View {
    @Bindable var store: CleanerStore

    var body: some View {
        Group {
            if store.selectedItems.count == 1, let item = store.selectedItems.first {
                ItemDetailView(store: store, item: item)
            } else if !store.selectedItems.isEmpty {
                MultiSelectionDetailView(store: store)
            } else {
                ContentUnavailableView("No Item Selected", systemImage: "sidebar.right", description: Text("Select a result to inspect details."))
            }
        }
    }
}

private struct MultiSelectionDetailView: View {
    @Bindable var store: CleanerStore

    private var plan: DeletionPlan {
        store.selectedDeletionPlan
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                header
                actions
                metadata
                selectedItems
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Image(systemName: "checklist")
                    .font(.title2)
                    .foregroundStyle(.tint)

                Text("\(store.selectedItems.count.formatted()) Items Selected")
                    .font(.title2)
                    .fontWeight(.semibold)
                    .lineLimit(2)
            }

            Text("\(plan.items.count.formatted()) item\(plan.items.count == 1 ? "" : "s") can be moved to Trash.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var actions: some View {
        HStack {
            Button {
                copySelectedPaths()
            } label: {
                Label("Copy Paths", systemImage: "doc.on.doc")
            }

            Spacer()

            Button(role: .destructive) {
                store.requestDeletionForSelection()
            } label: {
                Label("Move to Trash", systemImage: "trash")
            }
            .disabled(!store.canRequestDeletionForSelection)
            .help(plan.isEmpty ? "No selected items can be moved to Trash" : "Move selected items to Trash")
        }
    }

    private var metadata: some View {
        VStack(alignment: .leading, spacing: 10) {
            MetadataTextRow(label: "Selected", value: store.selectedItems.count.formatted())
            MetadataTextRow(label: "Movable", value: plan.items.count.formatted())
            MetadataTextRow(label: "Size", value: ByteFormat.string(from: plan.totalBytes))

            if let highestRisk = plan.highestRisk {
                MetadataAccessoryRow(label: "Risk") {
                    RiskBadge(risk: highestRisk)
                }
            }
        }
    }

    private var selectedItems: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Selected Items")
                .font(.headline)

            ForEach(store.selectedItems.prefix(10)) { item in
                VStack(alignment: .leading, spacing: 2) {
                    Text(item.name)
                        .fontWeight(.semibold)
                    Text(item.path)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                .font(.caption)
            }

            if store.selectedItems.count > 10 {
                Text("\((store.selectedItems.count - 10).formatted()) more")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func copySelectedPaths() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(store.selectedItems.map(\.path).joined(separator: "\n"), forType: .string)
        store.statusMessage = "Copied selected paths."
    }
}

private struct ItemDetailView: View {
    @Bindable var store: CleanerStore
    let item: DiskItem

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                header
                actions
                metadata

                if let report = store.report, !report.issues.isEmpty {
                    issues(report.issues)
                }
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Image(systemName: item.category.systemImage)
                    .font(.title2)
                    .foregroundStyle(.tint)

                Text(item.name)
                    .font(.title2)
                    .fontWeight(.semibold)
                    .lineLimit(2)
                    .textSelection(.enabled)
            }

            Text(item.path)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(3)
                .textSelection(.enabled)
        }
    }

    private var actions: some View {
        HStack {
            Button {
                store.revealInFinder(item)
            } label: {
                Label("Reveal", systemImage: "finder")
            }

            Button {
                store.copyPath(item)
            } label: {
                Label("Copy Path", systemImage: "doc.on.doc")
            }

            Spacer()

            Button(role: .destructive) {
                store.requestDeletion(item)
            } label: {
                Label("Move to Trash", systemImage: "trash")
            }
            .disabled(!item.isDeletableCandidate || store.isDeleting)
            .help(trashHelpText)
        }
    }

    private var trashHelpText: String {
        if item.isDeletableCandidate {
            return "Move to Trash"
        }

        if item.risk == .protected {
            return "Protected"
        }

        return "Scan root"
    }

    private var metadata: some View {
        VStack(alignment: .leading, spacing: 10) {
            MetadataTextRow(label: "Size", value: ByteFormat.string(from: item.byteSize))
            MetadataTextRow(label: "Kind", value: item.kind.displayName)
            MetadataTextRow(label: "Category", value: item.category.displayName)
            MetadataAccessoryRow(label: "Risk") {
                RiskBadge(risk: item.risk)
            }
            MetadataTextRow(label: "Files", value: item.fileCount.formatted())
            MetadataTextRow(label: "Folders", value: item.childFolderCount.formatted())
            MetadataTextRow(label: "Root", value: item.rootPath)

            if let modifiedAt = item.modifiedAt {
                MetadataTextRow(label: "Modified", value: modifiedAt.formatted(date: .abbreviated, time: .shortened))
            }

            if let lastAccessedAt = item.lastAccessedAt {
                MetadataTextRow(label: "Accessed", value: lastAccessedAt.formatted(date: .abbreviated, time: .shortened))
            }
        }
    }

    private func issues(_ issues: [ScanIssue]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Scan Issues")
                .font(.headline)

            ForEach(issues.prefix(8)) { issue in
                VStack(alignment: .leading, spacing: 2) {
                    Text(issue.path)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Text(issue.message)
                        .foregroundStyle(.secondary)
                }
                .font(.caption)
            }
        }
    }
}

private struct MetadataTextRow: View {
    let label: String
    let value: String

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(label)
                .foregroundStyle(.secondary)
                .frame(width: 72, alignment: .leading)

            Text(value)
                .textSelection(.enabled)
                .lineLimit(3)
                .truncationMode(.middle)

            Spacer(minLength: 0)
        }
        .font(.body)
    }
}

private struct MetadataAccessoryRow<Accessory: View>: View {
    let label: String
    @ViewBuilder let accessory: () -> Accessory

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(label)
                .foregroundStyle(.secondary)
                .frame(width: 72, alignment: .leading)

            accessory()

            Spacer(minLength: 0)
        }
        .font(.body)
    }
}

struct RiskBadge: View {
    let risk: DeletionRisk

    var body: some View {
        Label(risk.displayName, systemImage: risk.systemImage)
            .font(.caption)
            .foregroundStyle(color)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(color.opacity(0.12), in: Capsule())
            .lineLimit(1)
    }

    private var color: Color {
        switch risk {
        case .low: .green
        case .medium: .yellow
        case .high: .orange
        case .protected: .red
        }
    }
}
