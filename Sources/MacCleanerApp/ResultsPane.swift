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
            ContentUnavailableView("No Scan Results", systemImage: "magnifyingglass", description: Text("Ready to scan selected locations."))
        } else if store.filteredItems.isEmpty {
            ContentUnavailableView("No Matching Items", systemImage: "line.3.horizontal.decrease.circle", description: Text("Adjust filters or scan options."))
        } else {
            List(store.filteredItems, selection: $store.selectedItemID) { item in
                ResultRow(item: item)
                    .tag(item.id)
                    .contextMenu {
                        Button {
                            store.revealInFinder(item)
                        } label: {
                            Label("Reveal in Finder", systemImage: "finder")
                        }

                        Button {
                            store.copyPath(item)
                        } label: {
                            Label("Copy Path", systemImage: "doc.on.doc")
                        }

                        if item.isDeletableCandidate {
                            Divider()
                            Button(role: .destructive) {
                                store.requestDeletion(item)
                            } label: {
                                Label("Move to Trash", systemImage: "trash")
                            }
                        }
                    }
            }
            .listStyle(.inset)
        }
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

            Spacer()
        }
    }
}

private struct ResultRow: View {
    let item: DiskItem

    var body: some View {
        HStack(spacing: 12) {
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
