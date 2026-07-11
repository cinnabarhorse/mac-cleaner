import AppKit
import MacCleanerCore
import MacCleanerFeatures
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
        if store.reportState == .initialLoading {
            StatusUnavailableView(
                title: "Loading Previous Scan",
                message: "Checking for a saved snapshot…",
                showsProgress: true
            )
        } else if store.isScanning && !store.hasScanResults {
            StatusUnavailableView(title: "Scanning", message: store.statusMessage, showsProgress: true)
        } else if !store.hasScanResults {
            if case let .failed(message) = store.reportState {
                ScanFailureView(store: store, message: message)
            } else {
                EmptyScanView(store: store)
            }
        } else if store.filteredItems.isEmpty {
            if store.report?.items.isEmpty == true, store.reportState == .current {
                ContentUnavailableView(
                    "No Large Items Found",
                    systemImage: "checkmark.circle",
                    description: Text("The scan completed, but no items met the selected minimum size.")
                )
            } else {
                ContentUnavailableView(
                    "No Matching Items",
                    systemImage: "line.3.horizontal.decrease.circle",
                    description: Text("Adjust the search, filters, or visibility options.")
                )
            }
        } else {
            List(selection: $store.selectedItemID) {
                ForEach(store.resultTree) { node in
                    ResultTreeRow(store: store, node: node)
                }
            }
            .listStyle(.inset)
            .accessibilityLabel("Scan results")
        }
    }
}

private struct StatusUnavailableView: View {
    let title: String
    let message: String
    let showsProgress: Bool

    var body: some View {
        VStack(spacing: 12) {
            if showsProgress {
                ProgressView()
            }
            Text(title)
                .font(.title3.weight(.semibold))
            Text(message)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct ScanFailureView: View {
    @Bindable var store: CleanerStore
    let message: String

    var body: some View {
        VStack(spacing: 14) {
            ContentUnavailableView(
                "Scan Failed",
                systemImage: "exclamationmark.triangle",
                description: Text(message)
            )
            Button("Try Again") { store.startScan() }
                .buttonStyle(.borderedProminent)
                .disabled(!store.canScan)
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct EmptyScanView: View {
    @Bindable var store: CleanerStore

    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: "magnifyingglass")
                .font(.largeTitle)
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            Text("No Scan Results")
                .font(.title3.weight(.semibold))
            Text(store.canScan ? "Start a scan to inspect disk usage." : "Select at least one location to scan.")
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button {
                store.startScan()
            } label: {
                Label("Scan Now", systemImage: "magnifyingglass")
            }
            .buttonStyle(.borderedProminent)
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
                    Button {
                        store.showingIssues = true
                    } label: {
                        MetricView(title: "Issues", value: report.issues.count.formatted())
                    }
                    .buttonStyle(.plain)
                    .disabled(report.issues.isEmpty)
                    .accessibilityLabel("Show \(report.issues.count) scan issue\(report.issues.count == 1 ? "" : "s")")
                }

                Spacer()
                if store.isScanning {
                    ProgressView()
                        .controlSize(.small)
                        .accessibilityLabel("Scan in progress")
                }
            }

            HStack(spacing: 10) {
                Text(store.statusMessage)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)

                if store.isReportReadOnly, store.report != nil {
                    Label(reportStateLabel, systemImage: "lock")
                        .foregroundStyle(.orange)
                        .lineLimit(1)
                }

                if let lastError = store.lastError {
                    Text(lastError)
                        .foregroundStyle(.red)
                        .lineLimit(1)
                }
            }
            .font(.caption)
        }
    }

    private var reportStateLabel: String {
        switch store.reportState {
        case .savedSnapshot(_, let wasComplete): wasComplete ? "Saved snapshot — read only" : "Saved partial scan — read only"
        case .livePartial: "Partial results — read only"
        case .stopped: "Stopped scan — read only"
        case .configurationChanged: "Settings changed — read only"
        case .staleAfterTrash: "Refreshing stale totals"
        case .failed: "Results may be incomplete"
        case .initialLoading, .noReport, .current: "Read only"
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

            Divider().frame(height: 16)

            Button { store.expandVisibleTree() } label: {
                Label("Expand All", systemImage: "plus.square.on.square")
            }
            .disabled(store.resultTree.isEmpty)

            Button { store.collapseVisibleTree() } label: {
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

    @ViewBuilder
    var body: some View {
        if node.hasChildren {
            DisclosureGroup(isExpanded: expandedBinding) {
                ForEach(node.children) { child in
                    ResultTreeRow(store: store, node: child)
                }
            } label: {
                ResultRow(item: node.item, childCount: node.children.count)
            }
            .tag(node.id)
            .contextMenu { contextMenu }
        } else {
            ResultRow(item: node.item, childCount: 0)
                .padding(.leading, 18)
                .tag(node.id)
                .contextMenu { contextMenu }
        }
    }

    private var expandedBinding: Binding<Bool> {
        Binding(
            get: { store.expandedItemIDs.contains(node.id) },
            set: { store.setExpanded(node.id, isExpanded: $0) }
        )
    }

    @ViewBuilder
    private var contextMenu: some View {
        Button {
            ResultActions.revealInFinder(node.item)
        } label: {
            Label("Reveal in Finder", systemImage: "finder")
        }

        Button {
            ResultActions.copyPath(node.item)
        } label: {
            Label("Copy Path", systemImage: "doc.on.doc")
        }

        if node.item.isDeletableCandidate {
            Divider()
            Button(role: .destructive) {
                store.requestDeletion(node.item)
            } label: {
                Label("Move to Trash", systemImage: "trash")
            }
            .disabled(store.deletionBlockReason(for: node.item) != nil)
        }
    }
}

private struct ResultRow: View {
    let item: DiskItem
    let childCount: Int

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
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(item.name), \(ByteFormat.string(from: item.byteSize)), \(item.risk.displayName) risk")
    }

    private var categoryColor: Color {
        switch item.category {
        case .cache, .logs: .teal
        case .developerData, .codex: .indigo
        case .applicationSupport: .blue
        case .media, .capCut, .finalCut: .pink
        case .documents, .downloads, .libraries, .projectData: .orange
        case .backups: .purple
        case .trash: .gray
        case .system: .red
        case .other: .secondary
        }
    }
}

struct ScanIssuesView: View {
    let issues: [ScanIssue]
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("Scan Issues")
                    .font(.title2.weight(.semibold))
                Spacer()
                Button("Done") { dismiss() }
                    .keyboardShortcut(.defaultAction)
            }

            if issues.isEmpty {
                ContentUnavailableView("No Scan Issues", systemImage: "checkmark.circle")
            } else {
                Label(
                    "Unreadable locations make affected folders ineligible for Trash. Grant Full Disk Access in System Settings if these locations should be scanned.",
                    systemImage: "hand.raised"
                )
                .foregroundStyle(.secondary)

                List(issues) { issue in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(issue.path)
                            .font(.body.monospaced())
                            .textSelection(.enabled)
                        Text(issue.message)
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                    }
                    .padding(.vertical, 4)
                    .accessibilityElement(children: .combine)
                }
            }
        }
        .padding(20)
        .frame(minWidth: 680, minHeight: 440)
    }
}

@MainActor
private enum ResultActions {
    static func revealInFinder(_ item: DiskItem) {
        NSWorkspace.shared.activateFileViewerSelecting([item.url])
    }

    static func copyPath(_ item: DiskItem) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(item.path, forType: .string)
        AccessibilityAnnouncer.announce("Copied path.")
    }
}
