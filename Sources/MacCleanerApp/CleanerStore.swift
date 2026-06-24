import AppKit
import Foundation
import MacCleanerCore
import Observation
import UniformTypeIdentifiers

@MainActor
@Observable
final class CleanerStore {
    var selectedScopes: Set<ScanScope> = ScanScope.defaultSelection
    var customRoots: [ScanRoot] = []
    var includeHiddenFiles = false
    var includePackageContents = true
    var includeSymlinkTargets = false
    var minimumItemSizeBytes: Int64 = 10 * 1_024 * 1_024
    var maxReturnedItems = 5_000
    var searchText = ""
    var categoryFilter: DiskItemCategory?
    var riskFilter: DeletionRisk?
    var ageFilter: ItemAgeFilter = .any
    var selectedItemIDs: Set<DiskItem.ID> = []
    var pendingDeletionPlan: DeletionPlan?
    var isScanning = false
    var isDeleting = false
    var progress: ScanProgress?
    var report: ScanReport?
    var statusMessage = "Ready"
    var lastError: String?
    var lastTrashResult: TrashOperationResult?
    var expandedItemIDs: Set<DiskItem.ID> = []
    var fullDiskAccessStatus: FullDiskAccessStatus = .unknown

    private let scanner: FileScanner
    private let trashService: any TrashManaging
    private let reportPersistence: ScanReportPersistence
    private let homeDirectory: URL
    private let fullDiskAccessProbe: FullDiskAccessProbe
    private var scanTask: Task<Void, Never>?
    private var deletedItemIDs: Set<DiskItem.ID> = []
    private var didAutoStartScan = false
    private var didSeedExpansion = false
    private var lastPersistedScannedItemCount = 0

    init(
        scanner: FileScanner? = nil,
        trashService: any TrashManaging = FileManagerTrashService(),
        reportPersistence: ScanReportPersistence = .defaultStore(),
        homeDirectory: URL = CleanerStore.defaultHomeDirectory(),
        fullDiskAccessProbe: FullDiskAccessProbe = FullDiskAccessProbe()
    ) {
        let normalizedHomeDirectory = homeDirectory.standardizedFileURL
        self.scanner = scanner ?? FileScanner(classifier: ItemClassifier(homeDirectory: normalizedHomeDirectory))
        self.trashService = trashService
        self.reportPersistence = reportPersistence
        self.homeDirectory = normalizedHomeDirectory
        self.fullDiskAccessProbe = fullDiskAccessProbe
        loadSavedReport()
        refreshFullDiskAccessStatus()
        updateLoadedReportStatusForCurrentAccess()
    }

    var activeRoots: [ScanRoot] {
        let scopedRoots = ScanScope.scanPriority
            .filter { selectedScopes.contains($0) }
            .flatMap { $0.roots(homeDirectory: homeDirectory) }
        let roots = scopedRoots + customRoots
        var seen: Set<String> = []

        return roots.filter { root in
            let path = root.url.standardizedFileURL.path
            guard FileManager.default.fileExists(atPath: path) else {
                return false
            }
            return seen.insert(path).inserted
        }
    }

    var filteredItems: [DiskItem] {
        guard let report else {
            return []
        }

        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()

        return report.items.filter { item in
            if deletedItemIDs.contains(item.id) {
                return false
            }

            if let categoryFilter, item.category != categoryFilter {
                return false
            }

            if let riskFilter, item.risk != riskFilter {
                return false
            }

            if !ageFilter.includes(item) {
                return false
            }

            if !query.isEmpty {
                let searchable = "\(item.name) \(item.path) \(item.category.displayName) \(item.kind.displayName)".lowercased()
                guard searchable.contains(query) else {
                    return false
                }
            }

            return true
        }
    }

    var resultTree: [DiskItemTreeNode] {
        DiskItemTreeBuilder.build(from: filteredItems)
    }

    var selectedItems: [DiskItem] {
        filteredItems.filter { selectedItemIDs.contains($0.id) }
    }

    var selectedDeletionPlan: DeletionPlan {
        DeletionPlan(items: selectedItems)
    }

    var smartCleanupPlan: SmartCleanupPlan {
        SmartCleanupPlan(items: filteredItems)
    }

    var canSelectSafePicks: Bool {
        !smartCleanupPlan.isEmpty
    }

    var canRequestDeletionForSelection: Bool {
        pendingDeletionPlan == nil && !isDeleting && !selectedDeletionPlan.isEmpty
    }

    var totalVisibleBytes: Int64 {
        resultTree.reduce(0) { $0 + $1.item.byteSize }
    }

    var hasScanResults: Bool {
        report != nil
    }

    var fullDiskAccessIssueCount: Int {
        report?.issues.filter(\.isLikelyPermissionIssue).count ?? 0
    }

    var shouldShowFullDiskAccessNotice: Bool {
        switch fullDiskAccessStatus {
        case .likelyDenied:
            return true
        case .unknown:
            return fullDiskAccessIssueCount > 0
        case .likelyGranted:
            return false
        }
    }

    var runningApplicationPath: String {
        Bundle.main.bundleURL.standardizedFileURL.path
    }

    var installedApplicationPath: String {
        CleanerStore.installedApplicationURL.path
    }

    var isRunningFromInstalledApplication: Bool {
        runningApplicationPath == installedApplicationPath
    }

    var canScan: Bool {
        !isScanning && !activeRoots.isEmpty
    }

    var hasActiveFilters: Bool {
        categoryFilter != nil || riskFilter != nil || ageFilter != .any || !searchText.isEmpty
    }

    func setScope(_ scope: ScanScope, enabled: Bool) {
        if enabled {
            selectedScopes.insert(scope)
        } else {
            selectedScopes.remove(scope)
        }
    }

    func addCustomFolder() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = false
        panel.prompt = "Add"

        guard panel.runModal() == .OK else {
            return
        }

        for url in panel.urls {
            let root = ScanRoot(title: url.lastPathComponent, url: url, categoryHint: nil, riskHint: .medium)
            if !customRoots.contains(where: { $0.url == root.url }) {
                customRoots.append(root)
            }
        }
    }

    func removeCustomRoot(_ root: ScanRoot) {
        customRoots.removeAll { $0.id == root.id }
    }

    func setExpanded(_ itemID: DiskItem.ID, isExpanded: Bool) {
        if isExpanded {
            expandedItemIDs.insert(itemID)
        } else {
            expandedItemIDs.remove(itemID)
        }
    }

    func expandVisibleTree() {
        expandedItemIDs.formUnion(expandableIDs(in: resultTree))
    }

    func collapseVisibleTree() {
        expandedItemIDs.subtract(expandableIDs(in: resultTree))
    }

    func toggleSelection(_ itemID: DiskItem.ID) {
        if selectedItemIDs.contains(itemID) {
            selectedItemIDs.remove(itemID)
        } else {
            selectedItemIDs.insert(itemID)
        }
    }

    func selectSafePicks() {
        let plan = smartCleanupPlan
        guard !plan.isEmpty else {
            statusMessage = "No safe picks found."
            return
        }

        selectedItemIDs = Set(plan.items.map(\.id))
        statusMessage = "Selected \(plan.items.count.formatted()) safe pick\(plan.items.count == 1 ? "" : "s") worth \(ByteFormat.string(from: plan.totalBytes))."
    }

    func clearFilters() {
        categoryFilter = nil
        riskFilter = nil
        ageFilter = .any
        searchText = ""
    }

    func autoStartScanIfNeeded() {
        guard !didAutoStartScan else {
            return
        }

        didAutoStartScan = true

        if report != nil {
            return
        }

        startScan()
    }

    func startScan() {
        scanTask?.cancel()
        refreshFullDiskAccessStatus()
        deletedItemIDs.removeAll()
        lastError = nil
        lastTrashResult = nil
        progress = nil
        expandedItemIDs.removeAll()
        selectedItemIDs.removeAll()
        didSeedExpansion = false
        lastPersistedScannedItemCount = 0

        let roots = activeRoots
        guard !roots.isEmpty else {
            report = emptyReport()
            statusMessage = "No selected locations exist."
            return
        }

        let options = ScanOptions(
            includeHiddenFiles: includeHiddenFiles,
            includePackageContents: includePackageContents,
            includeSymlinkTargets: includeSymlinkTargets,
            minimumItemSizeBytes: minimumItemSizeBytes,
            maxReturnedItems: maxReturnedItems,
            snapshotItemInterval: 500
        )

        isScanning = true
        statusMessage = "Scanning \(roots.count) location\(roots.count == 1 ? "" : "s")..."

        scanTask = Task { [scanner] in
            do {
                let scanReport = try await scanner.scan(roots: roots, options: options) { [weak self] scanProgress in
                    await self?.updateProgress(scanProgress)
                }

                finishScan(scanReport)
            } catch is CancellationError {
                finishStoppedScan()
            } catch {
                finishFailedScan(error)
            }
        }
    }

    func stopScan() {
        scanTask?.cancel()
    }

    func revealInFinder(_ item: DiskItem) {
        NSWorkspace.shared.activateFileViewerSelecting([item.url])
    }

    func copyPath(_ item: DiskItem) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(item.path, forType: .string)
        statusMessage = "Copied path."
    }

    func exportReport(as format: ScanReportExportFormat) {
        guard let report else {
            statusMessage = "No scan report to export."
            return
        }

        let panel = NSSavePanel()
        panel.canCreateDirectories = true
        panel.nameFieldStringValue = defaultExportFileName(for: report, format: format)
        if let contentType = UTType(filenameExtension: format.fileExtension) {
            panel.allowedContentTypes = [contentType]
        }

        guard panel.runModal() == .OK, let url = panel.url else {
            return
        }

        do {
            let export = ScanReportExporter.export(report, as: format)
            try export.write(to: url, atomically: true, encoding: .utf8)
            statusMessage = "Exported \(format.displayName) report."
        } catch {
            lastError = "Could not export report: \(error.localizedDescription)"
        }
    }

    func openFullDiskAccessSettings() {
        let urls = [
            URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles"),
            URL(string: "x-apple.systempreferences:com.apple.Settings.PrivacySecurity.extension?Privacy_AllFiles")
        ].compactMap(\.self)

        for url in urls where NSWorkspace.shared.open(url) {
            statusMessage = "Opened Full Disk Access settings. If Mac Cleaner is already enabled, remove and add it again."
            return
        }

        lastError = "Could not open Full Disk Access settings."
    }

    func revealInstalledApplication() {
        NSWorkspace.shared.activateFileViewerSelecting([CleanerStore.installedApplicationURL])
    }

    func refreshFullDiskAccessStatus() {
        fullDiskAccessStatus = fullDiskAccessProbe.evaluate(homeDirectory: homeDirectory)
    }

    func requestDeletion(_ item: DiskItem) {
        requestDeletion(items: [item])
    }

    func requestDeletionForSelection() {
        requestDeletion(items: selectedItems)
    }

    func requestDeletion(items: [DiskItem]) {
        let plan = DeletionPlan(items: items)
        guard !plan.isEmpty else {
            statusMessage = "No deletable items selected."
            return
        }

        pendingDeletionPlan = plan
    }

    func movePendingItemsToTrash() {
        guard let plan = pendingDeletionPlan else {
            return
        }

        moveToTrash(plan.items)
    }

    func moveToTrash(_ item: DiskItem) {
        moveToTrash([item])
    }

    func moveToTrash(_ items: [DiskItem]) {
        let plan = DeletionPlan(items: items)
        guard !plan.isEmpty else {
            lastError = "This item is protected."
            pendingDeletionPlan = nil
            return
        }

        isDeleting = true
        lastError = nil
        statusMessage = "Moving \(plan.items.count.formatted()) item\(plan.items.count == 1 ? "" : "s") to Trash..."

        Task { [trashService] in
            do {
                let result = try await trashService.moveToTrash(plan.items.map(\.url))
                finishTrashMove(items: plan.items, result: result)
            } catch {
                finishFailedTrashMove(error)
            }
        }
    }

    private func updateProgress(_ scanProgress: ScanProgress) {
        progress = scanProgress

        if let partialReport = scanProgress.partialReport {
            report = partialReport
            seedExpansionIfNeeded(for: partialReport)
            savePartialReportIfNeeded(partialReport)
            reconcileSelection(with: partialReport.items)
            statusMessage = "Scanning... found \(partialReport.items.count.formatted()) large items after \(scanProgress.scannedItemCount.formatted()) scanned."
        } else {
            statusMessage = "Scanning \(scanProgress.currentPath) • \(scanProgress.scannedItemCount.formatted()) items..."
        }
    }

    private func finishScan(_ scanReport: ScanReport) {
        refreshFullDiskAccessStatus()
        report = scanReport
        seedExpansionIfNeeded(for: scanReport)
        saveReport(scanReport)
        isScanning = false
        reconcileSelection(with: scanReport.items)
        statusMessage = "Found \(scanReport.items.count.formatted()) large items."
        scanTask = nil
    }

    private func finishStoppedScan() {
        if let report {
            saveReport(report)
        }
        isScanning = false
        statusMessage = "Scan stopped."
        scanTask = nil
    }

    private func finishFailedScan(_ error: Error) {
        isScanning = false
        lastError = error.localizedDescription
        statusMessage = "Scan failed."
        scanTask = nil
    }

    private func finishTrashMove(items: [DiskItem], result: TrashOperationResult) {
        let movedItemIDs = Set(items.map(\.id))
        deletedItemIDs.formUnion(movedItemIDs)
        report = report?.removingItems(withIDs: deletedItemIDs)
        if let report {
            saveReport(report)
        }
        pendingDeletionPlan = nil
        isDeleting = false
        lastTrashResult = result
        selectedItemIDs.subtract(movedItemIDs)
        reconcileSelection(with: filteredItems)
        statusMessage = "Moved \(items.count.formatted()) item\(items.count == 1 ? "" : "s") to Trash."
    }

    private func finishFailedTrashMove(_ error: Error) {
        pendingDeletionPlan = nil
        isDeleting = false
        lastError = error.localizedDescription
        statusMessage = "Move to Trash failed."
    }

    private func emptyReport() -> ScanReport {
        let now = Date()
        return ScanReport(
            roots: [],
            items: [],
            issues: [],
            totalBytes: 0,
            scannedItemCount: 0,
            scannedFileCount: 0,
            scannedFolderCount: 0,
            startedAt: now,
            finishedAt: now
        )
    }

    private static func defaultHomeDirectory() -> URL {
        let environment = ProcessInfo.processInfo.environment
        if let override = environment["MAC_CLEANER_HOME"], !override.isEmpty {
            return URL(fileURLWithPath: override, isDirectory: true)
        }

        return FileManager.default.homeDirectoryForCurrentUser
    }

    private static var installedApplicationURL: URL {
        URL(fileURLWithPath: "/Applications/Mac Cleaner.app", isDirectory: true)
    }

    private func defaultExportFileName(for report: ScanReport, format: ScanReportExportFormat) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd-HHmmss"
        return "mac-cleaner-\(formatter.string(from: report.finishedAt)).\(format.fileExtension)"
    }

    private func loadSavedReport() {
        do {
            guard let savedReport = try reportPersistence.load() else {
                return
            }

            report = savedReport
            seedExpansionIfNeeded(for: savedReport)
            reconcileSelection(with: savedReport.items)
            let scanLabel = savedReport.isComplete ? "previous scan" : "saved partial scan"
            statusMessage = "Loaded \(scanLabel) from \(savedReport.finishedAt.formatted(date: .abbreviated, time: .shortened))."
            lastPersistedScannedItemCount = savedReport.scannedItemCount
        } catch {
            lastError = "Could not load previous scan: \(error.localizedDescription)"
        }
    }

    private func updateLoadedReportStatusForCurrentAccess() {
        guard fullDiskAccessStatus == .likelyGranted, fullDiskAccessIssueCount > 0 else {
            return
        }

        statusMessage = "Full Disk Access is active. Scan again to refresh old permission issues."
    }

    private func saveReport(_ report: ScanReport) {
        do {
            try reportPersistence.save(report)
            lastPersistedScannedItemCount = report.scannedItemCount
        } catch {
            lastError = "Could not save scan: \(error.localizedDescription)"
        }
    }

    private func savePartialReportIfNeeded(_ report: ScanReport) {
        guard report.scannedItemCount - lastPersistedScannedItemCount >= 25_000 else {
            return
        }

        let reportPersistence = reportPersistence
        lastPersistedScannedItemCount = report.scannedItemCount

        Task.detached(priority: .utility) {
            try? reportPersistence.save(report)
        }
    }

    private func seedExpansionIfNeeded(for report: ScanReport) {
        guard !didSeedExpansion else {
            return
        }

        let tree = DiskItemTreeBuilder.build(from: report.items)
        guard !tree.isEmpty else {
            return
        }

        expandedItemIDs.formUnion(tree.filter(\.hasChildren).map(\.id))
        didSeedExpansion = true
    }

    private func expandableIDs(in nodes: [DiskItemTreeNode]) -> Set<DiskItem.ID> {
        var ids: Set<DiskItem.ID> = []

        func visit(_ node: DiskItemTreeNode) {
            guard node.hasChildren else {
                return
            }

            ids.insert(node.id)
            node.children.forEach(visit)
        }

        nodes.forEach(visit)
        return ids
    }

    private func reconcileSelection(with items: [DiskItem]) {
        let itemIDs = Set(items.map(\.id))
        selectedItemIDs.formIntersection(itemIDs)

        if selectedItemIDs.isEmpty, let firstItem = items.first {
            selectedItemIDs = [firstItem.id]
        }
    }
}
