import MacCleanerCore
import SwiftUI

struct ResultsPane: View {
    @Bindable var store: CleanerStore

    var body: some View {
        VStack(spacing: 0) {
            SummaryStrip(store: store)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)

            Divider()

            FilterBar(store: store)
                .padding(.horizontal, 14)
                .padding(.vertical, 8)

            Divider()

            content
        }
        .searchable(text: $store.searchText, prompt: "Search Results")
    }

    @ViewBuilder
    private var content: some View {
        if store.isScanning && !store.hasScanResults {
            VStack {
                ProgressView()
                Text(store.statusMessage)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if !store.hasScanResults {
            EmptyScanView(store: store)
        } else if store.filteredItems.isEmpty {
            ContentUnavailableView("No Matching Items", systemImage: "line.3.horizontal.decrease.circle", description: Text("Adjust filters or scan options."))
        } else {
            List(selection: $store.selectedItemIDs) {
                ForEach(store.resultTree) { node in
                    ResultTreeRow(store: store, node: node)
                }
            }
            .listStyle(.inset)
        }
    }
}

private struct EmptyScanView: View {
    @Bindable var store: CleanerStore

    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 44, weight: .regular))
                .foregroundStyle(.secondary)

            Text("No Scan Results")
                .font(.title3)
                .fontWeight(.semibold)

            Text(store.canScan ? "Scanning starts automatically. You can also start it manually." : "Select at least one existing location to scan.")
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            Button {
                store.startScan()
            } label: {
                Label("Scan Now", systemImage: "magnifyingglass")
            }
            .buttonStyle(.borderedProminent)
            .tint(.accentColor)
            .controlSize(.large)
            .disabled(!store.canScan)
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct SummaryStrip: View {
    @Bindable var store: CleanerStore

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 16) {
                MetricView(title: "Visible", value: ByteFormat.string(from: store.totalVisibleBytes))
                MetricView(title: "Items", value: store.filteredItems.count.formatted())

                if let report = store.report {
                    MetricView(title: "Scanned", value: report.scannedItemCount.formatted())
                    MetricView(title: "Issues", value: report.issues.count.formatted())
                }

                Spacer()

                if store.isScanning {
                    ProgressView()
                        .controlSize(.small)
                }
            }

            HStack {
                Text(store.statusMessage)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)

                if let lastError = store.lastError {
                    Text(lastError)
                        .foregroundStyle(.red)
                        .lineLimit(1)
                }
            }
            .font(.caption)
        }
    }
}

private struct MetricView: View {
    let title: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.headline)
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
        .frame(minWidth: 72, alignment: .leading)
    }
}

private struct FilterBar: View {
    @Bindable var store: CleanerStore

    var body: some View {
        HStack {
            Picker("Category", selection: $store.categoryFilter) {
                Text("All Categories").tag(DiskItemCategory?.none)
                ForEach(DiskItemCategory.allCases) { category in
                    Label(category.displayName, systemImage: category.systemImage)
                        .tag(Optional(category))
                }
            }
            .pickerStyle(.menu)
            .frame(maxWidth: 210)

            Picker("Risk", selection: $store.riskFilter) {
                Text("All Risks").tag(DeletionRisk?.none)
                ForEach(DeletionRisk.allCases) { risk in
                    Label(risk.displayName, systemImage: risk.systemImage)
                        .tag(Optional(risk))
                }
            }
            .pickerStyle(.menu)
            .frame(maxWidth: 170)

            Button {
                store.categoryFilter = nil
                store.riskFilter = nil
                store.searchText = ""
            } label: {
                Label("Clear", systemImage: "xmark.circle")
            }
            .disabled(store.categoryFilter == nil && store.riskFilter == nil && store.searchText.isEmpty)

            Divider()
                .frame(height: 16)

            Button {
                store.expandVisibleTree()
            } label: {
                Label("Expand All", systemImage: "plus.square.on.square")
            }
            .disabled(store.resultTree.isEmpty)

            Button {
                store.collapseVisibleTree()
            } label: {
                Label("Collapse All", systemImage: "minus.square")
            }
            .disabled(store.resultTree.isEmpty)

            Spacer()
        }
    }
}

private struct ResultTreeRow: View {
    @Bindable var store: CleanerStore
    let node: DiskItemTreeNode

    var body: some View {
        if node.hasChildren {
            DisclosureGroup(isExpanded: expandedBinding) {
                ForEach(node.children) { child in
                    ResultTreeRow(store: store, node: child)
                }
            } label: {
                rowLabel
            }
            .tag(node.id)
        } else {
            rowLabel
                .padding(.leading, 18)
                .tag(node.id)
        }
    }

    private var expandedBinding: Binding<Bool> {
        Binding {
            store.expandedItemIDs.contains(node.id)
        } set: { isExpanded in
            store.setExpanded(node.id, isExpanded: isExpanded)
        }
    }

    private var rowLabel: some View {
        ResultRow(
            item: node.item,
            childCount: node.children.count,
            isSelected: store.selectedItemIDs.contains(node.id),
            onToggleSelection: {
                store.toggleSelection(node.id)
            }
        )
        .contextMenu {
            Button {
                store.revealInFinder(node.item)
            } label: {
                Label("Reveal in Finder", systemImage: "finder")
            }

            Button {
                store.copyPath(node.item)
            } label: {
                Label("Copy Path", systemImage: "doc.on.doc")
            }

            if node.item.isDeletableCandidate {
                Divider()
                Button(role: .destructive) {
                    if store.selectedItemIDs.contains(node.id), store.selectedDeletionPlan.items.count > 1 {
                        store.requestDeletionForSelection()
                    } else {
                        store.requestDeletion(node.item)
                    }
                } label: {
                    Label(trashMenuTitle, systemImage: "trash")
                }
            }
        }
    }

    private var trashMenuTitle: String {
        if store.selectedItemIDs.contains(node.id), store.selectedDeletionPlan.items.count > 1 {
            return "Move Selected to Trash"
        }

        return "Move to Trash"
    }
}

private struct ResultRow: View {
    let item: DiskItem
    let childCount: Int
    let isSelected: Bool
    let onToggleSelection: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Button(action: onToggleSelection) {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(isSelected ? Color.accentColor : Color.secondary)
                    .font(.system(size: 16, weight: .medium))
                    .frame(width: 18, height: 18)
            }
            .buttonStyle(.plain)
            .help(isSelected ? "Deselect" : "Select")
            .accessibilityLabel(isSelected ? "Deselect \(item.name)" : "Select \(item.name)")

            Image(systemName: item.category.systemImage)
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(categoryColor)
                .frame(width: 24)

            VStack(alignment: .leading, spacing: 3) {
                HStack {
                    Text(item.name)
                        .font(.headline)
                        .lineLimit(1)

                    Image(systemName: item.kind.systemImage)
                        .foregroundStyle(.secondary)
                        .help(item.kind.displayName)

                    if childCount > 0 {
                        Text(childCount.formatted())
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }
                }

                Text(item.path)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            Spacer(minLength: 16)

            Text(ByteFormat.string(from: item.byteSize))
                .font(.system(.body, design: .monospaced))
                .lineLimit(1)
                .frame(width: 96, alignment: .trailing)

            RiskBadge(risk: item.risk)
                .frame(width: 104, alignment: .trailing)
        }
        .padding(.vertical, 4)
        .padding(.horizontal, 6)
        .background(isSelected ? Color.accentColor.opacity(0.16) : Color.clear, in: RoundedRectangle(cornerRadius: 8))
        .contentShape(Rectangle())
    }

    private var categoryColor: Color {
        switch item.category {
        case .cache, .logs: .teal
        case .developerData, .codex: .indigo
        case .applicationSupport: .blue
        case .media, .capCut, .finalCut: .pink
        case .documents, .downloads: .orange
        case .backups: .purple
        case .trash: .gray
        case .system: .red
        case .other: .secondary
        }
    }
}
