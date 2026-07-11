import Foundation
import MacCleanerCore
import Observation

@MainActor
@Observable
public final class CleanerStore {
    public var selectedScopes: Set<ScanScope> {
        didSet {
            guard selectedScopes != oldValue else { return }
            scanConfigurationDidChange()
        }
    }

    public var customRoots: [ScanRoot] {
        didSet {
            guard customRoots != oldValue else { return }
            scanConfigurationDidChange()
        }
    }

    public var showHiddenFiles: Bool {
        didSet {
            persistPreferences()
            reconcileSelection()
        }
    }

    public var showPackageContents: Bool {
        didSet {
            persistPreferences()
            reconcileSelection()
        }
    }

    public var showSymbolicLinks: Bool {
        didSet {
            persistPreferences()
            reconcileSelection()
        }
    }

    public var minimumItemSizeBytes: Int64 {
        didSet {
            guard minimumItemSizeBytes != oldValue else { return }
            scanConfigurationDidChange()
        }
    }

    public var maxReturnedItems: Int {
        didSet {
            guard maxReturnedItems != oldValue else { return }
            scanConfigurationDidChange()
        }
    }

    public var searchText = "" {
        didSet { reconcileSelection() }
    }

    public var categoryFilter: DiskItemCategory? {
        didSet { reconcileSelection() }
    }

    public var riskFilter: DeletionRisk? {
        didSet { reconcileSelection() }
    }

    public var selectedItemID: DiskItem.ID?
    public var expandedItemIDs: Set<DiskItem.ID> = []
    public var showingIssues = false

    public private(set) var activity: CleanerActivity = .idle
    public private(set) var reportState: ReportViewState = .initialLoading
    public private(set) var progress: ScanProgress?
    public private(set) var report: ScanReport?
    public private(set) var deletionFlow: DeletionFlow?
    public private(set) var statusMessage = "Loading…"
    public private(set) var accessibilityAnnouncement: AccessibilityAnnouncement?
    public private(set) var lastError: String?
    public private(set) var lastTrashResult: TrashOperationResult?

    @ObservationIgnored private let scanner: any FileScanning
    @ObservationIgnored private let deletionValidator: any DeletionValidating
    @ObservationIgnored private let trashService: any TrashManaging
    @ObservationIgnored private let reportPersistence: any ScanReportPersisting
    @ObservationIgnored private let preferencesPersistence: any CleanerPreferencesPersisting
    @ObservationIgnored private let homeDirectory: URL
    @ObservationIgnored private var scanTask: Task<Void, Never>?
    @ObservationIgnored private var deletionTask: Task<Void, Never>?
    @ObservationIgnored private var scanGeneration: UInt64 = 0
    @ObservationIgnored private var persistenceRevision: UInt64 = 0
    @ObservationIgnored private var didBootstrap = false
    @ObservationIgnored private var didSeedExpansion = false
    @ObservationIgnored private var lastPersistedScannedItemCount = 0

    public init(
        scanner: (any FileScanning)? = nil,
        deletionValidator: (any DeletionValidating)? = nil,
        trashService: (any TrashManaging)? = nil,
        reportPersistence: (any ScanReportPersisting)? = nil,
        preferencesPersistence: any CleanerPreferencesPersisting = UserDefaultsCleanerPreferencesStore(),
        homeDirectory: URL = CleanerStore.defaultHomeDirectory()
    ) {
        let normalizedHome = homeDirectory.standardizedFileURL
        let preferences = preferencesPersistence.load() ?? CleanerPreferences()

        self.scanner = scanner ?? FileScanner(classifier: ItemClassifier(homeDirectory: normalizedHome))
        self.deletionValidator = deletionValidator ?? FileSystemDeletionValidator(homeDirectory: normalizedHome)
        self.trashService = trashService ?? FileManagerTrashService(homeDirectory: normalizedHome)
        self.reportPersistence = reportPersistence ?? SerializedScanReportStore(persistence: .defaultStore())
        self.preferencesPersistence = preferencesPersistence
        self.homeDirectory = normalizedHome
        selectedScopes = preferences.selectedScopes
        customRoots = preferences.customRoots
        showHiddenFiles = preferences.showHiddenFiles
        showPackageContents = preferences.showPackageContents
        showSymbolicLinks = preferences.showSymbolicLinks
        minimumItemSizeBytes = preferences.minimumItemSizeBytes
        maxReturnedItems = preferences.maxReturnedItems
    }

    public var activeRoots: [ScanRoot] {
        ScanScope.scanPriority
            .filter { selectedScopes.contains($0) }
            .flatMap { $0.roots(homeDirectory: homeDirectory) }
            + customRoots
    }

    public var filteredItems: [DiskItem] {
        guard let report else {
            return []
        }

        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()

        return report.items.filter { item in
            guard showHiddenFiles || !item.isHidden else {
                return false
            }

            if !showPackageContents,
               let packageRootPath = item.packageRootPath,
               packageRootPath != item.path {
                return false
            }

            guard showSymbolicLinks || item.kind != .symbolicLink else {
                return false
            }

            if let categoryFilter, item.category != categoryFilter {
                return false
            }

            if let riskFilter, item.risk != riskFilter {
                return false
            }

            if !query.isEmpty {
                let searchable = "\(item.name) \(item.path) \(item.category.displayName) \(item.kind.displayName) \(item.classificationRationale)".lowercased()
                guard searchable.contains(query) else {
                    return false
                }
            }

            return true
        }
    }

    public var resultTree: [DiskItemTreeNode] {
        DiskItemTreeBuilder.build(from: filteredItems)
    }

    public var selectedItem: DiskItem? {
        guard let selectedItemID else {
            return nil
        }

        return filteredItems.first { $0.id == selectedItemID }
    }

    public var totalVisibleBytes: Int64 {
        resultTree.reduce(0) { $0 + $1.item.byteSize }
    }

    public var hasScanResults: Bool {
        report != nil
    }

    public var isScanning: Bool {
        activity.isScanning
    }

    public var isDeleting: Bool {
        switch activity {
        case .validating, .revalidating, .cancelingDeletion, .movingToTrash:
            true
        case .idle, .scanning:
            false
        }
    }

    public var isMovingToTrash: Bool {
        activity.isMovingToTrash
    }

    public var canEditConfiguration: Bool {
        !isScanning && !isDeleting && deletionFlow == nil
    }

    public var canScan: Bool {
        activity == .idle && deletionFlow == nil && !activeRoots.isEmpty
    }

    public var canStopScan: Bool {
        isScanning && progress != nil
    }

    public var canDismissDeletion: Bool {
        deletionFlow != nil && !isMovingToTrash
    }

    public var isDeletionPresented: Bool {
        deletionFlow != nil
    }

    public var canConfirmDeletion: Bool {
        if case .confirming = deletionFlow, activity == .idle {
            return true
        }
        return false
    }

    public var isReportReadOnly: Bool {
        reportState.isReadOnly || report?.isActionable != true
    }

    public func setScope(_ scope: ScanScope, enabled: Bool) {
        guard canEditConfiguration else {
            return
        }

        if enabled {
            selectedScopes.insert(scope)
        } else {
            selectedScopes.remove(scope)
        }
    }

    public func addCustomFolders(_ urls: [URL]) {
        guard canEditConfiguration else {
            return
        }

        var updatedRoots = customRoots
        for url in urls {
            let root = ScanRoot(
                title: url.lastPathComponent,
                url: url,
                categoryHint: nil,
                riskHint: nil
            )
            if !updatedRoots.contains(where: { $0.url.standardizedFileURL == root.url }) {
                updatedRoots.append(root)
            }
        }
        customRoots = updatedRoots
    }

    public func removeCustomRoot(_ root: ScanRoot) {
        guard canEditConfiguration else {
            return
        }
        customRoots.removeAll { $0.id == root.id }
    }

    public func setExpanded(_ itemID: DiskItem.ID, isExpanded: Bool) {
        if isExpanded {
            expandedItemIDs.insert(itemID)
        } else {
            expandedItemIDs.remove(itemID)
        }
    }

    public func expandVisibleTree() {
        expandedItemIDs.formUnion(expandableIDs(in: resultTree))
    }

    public func collapseVisibleTree() {
        expandedItemIDs.subtract(expandableIDs(in: resultTree))
    }

    public func bootstrap() async {
        guard !didBootstrap else {
            return
        }
        didBootstrap = true

        do {
            if let savedReport = try await reportPersistence.load() {
                report = savedReport
                reportState = .savedSnapshot(
                    savedAt: savedReport.finishedAt,
                    wasComplete: savedReport.isComplete
                )
                let completionLabel = savedReport.isComplete ? "scan" : "partial scan"
                statusMessage = "Loaded a read-only saved \(completionLabel) from \(savedReport.finishedAt.formatted(date: .abbreviated, time: .shortened)). Refreshing…"
                lastPersistedScannedItemCount = savedReport.scannedItemCount
                seedExpansionIfNeeded(for: savedReport)
                reconcileSelection()
            } else {
                reportState = .noReport
                statusMessage = "Ready"
            }
        } catch {
            lastError = "Could not load the previous scan: \(error.localizedDescription)"
            reportState = .failed(message: lastError ?? "Could not load the previous scan.")
            statusMessage = "Previous scan could not be loaded. Refreshing…"
        }

        startScan()
    }

    public func startScan() {
        guard canScan else {
            if activeRoots.isEmpty {
                reportState = report == nil ? .noReport : reportState
                statusMessage = "Select at least one location to scan."
            }
            return
        }

        scanTask?.cancel()
        scanGeneration &+= 1
        let generation = scanGeneration
        let roots = activeRoots

        lastError = nil
        progress = ScanProgress(
            currentPath: "Preparing scan",
            scannedItemCount: 0,
            scannedByteCount: 0
        )
        expandedItemIDs.removeAll()
        didSeedExpansion = false
        lastPersistedScannedItemCount = 0
        activity = .scanning(generation: generation)
        statusMessage = "Scanning \(roots.count) location\(roots.count == 1 ? "" : "s")…"
        announce("Scan started.")

        let options = ScanOptions(
            includeHiddenFiles: showHiddenFiles,
            includePackageContents: showPackageContents,
            includeSymlinkTargets: showSymbolicLinks,
            minimumItemSizeBytes: minimumItemSizeBytes,
            maxReturnedItems: maxReturnedItems,
            snapshotItemInterval: 5_000,
            snapshotInterval: 1
        )

        let store = self
        scanTask = Task { [scanner] in
            do {
                let scanReport = try await scanner.scan(roots: roots, options: options) { scanProgress in
                    await store.applyProgress(scanProgress, generation: generation)
                }
                await store.finishScan(scanReport, generation: generation)
            } catch is CancellationError {
                await store.finishStoppedScan(generation: generation)
            } catch {
                await store.finishFailedScan(error, generation: generation)
            }
        }
    }

    public func stopScan() {
        guard canStopScan else {
            return
        }
        scanTask?.cancel()
    }

    public func requestDeletion(_ item: DiskItem) {
        guard activity == .idle, deletionFlow == nil else {
            return
        }

        guard let currentReport = report,
              reportState == .current,
              currentReport.isActionable,
              currentReport.items.contains(where: { $0.id == item.id }) else {
            blockDeletion(for: item, message: "Refresh the scan before moving anything to Trash.")
            return
        }

        guard item.deletionEligibility.isEligible else {
            blockDeletion(
                for: item,
                message: item.deletionEligibility.reason ?? "This item cannot be moved to Trash."
            )
            return
        }

        activity = .validating(itemID: item.id)
        deletionFlow = .verifying(item)
        lastError = nil
        lastTrashResult = nil
        statusMessage = "Verifying \(item.name)…"
        let scanID = currentReport.scanID

        let store = self
        deletionTask = Task { [deletionValidator] in
            do {
                let request = try await deletionValidator.preflight(item: item, in: currentReport)
                store.finishPreflight(request, item: item, scanID: scanID)
            } catch is CancellationError {
                store.finishCancelledDeletion()
            } catch {
                store.finishFailedDeletion(error, item: item)
            }
        }
    }

    public func confirmDeletion() {
        guard case .confirming(let request, _) = deletionFlow,
              activity == .idle else {
            return
        }

        activity = .revalidating(itemID: request.summary.url.path)
        deletionFlow = .revalidating(request)
        statusMessage = "Checking for changes…"

        let store = self
        deletionTask = Task { [deletionValidator] in
            do {
                let result = try await deletionValidator.revalidate(request)
                await store.finishRevalidation(result)
            } catch is CancellationError {
                store.finishCancelledDeletion()
            } catch {
                store.finishFailedRevalidation(error, request: request)
            }
        }
    }

    public func dismissDeletion() {
        guard canDismissDeletion else {
            return
        }

        switch activity {
        case .validating(let itemID), .revalidating(let itemID):
            activity = .cancelingDeletion(itemID: itemID)
            deletionFlow = nil
            statusMessage = "Canceling the safety check…"
            deletionTask?.cancel()
        case .idle:
            deletionTask = nil
            deletionFlow = nil
            statusMessage = reportState == .current ? "Ready" : statusMessage
        case .scanning, .cancelingDeletion, .movingToTrash:
            break
        }
    }

    public func deletionBlockReason(for item: DiskItem) -> String? {
        if isReportReadOnly {
            return "Refresh the scan before moving anything to Trash."
        }

        if activity != .idle {
            return "Wait for the current operation to finish."
        }

        if deletionFlow != nil {
            return "Finish the current Trash confirmation first."
        }

        return item.deletionEligibility.reason
    }

    private func applyProgress(_ scanProgress: ScanProgress, generation: UInt64) async {
        guard activity == .scanning(generation: generation) else {
            return
        }

        progress = scanProgress
        if let partialReport = scanProgress.partialReport {
            report = partialReport
            reportState = .livePartial
            seedExpansionIfNeeded(for: partialReport)
            reconcileSelection()
            statusMessage = "Scanning… found \(partialReport.items.count.formatted()) large items after \(scanProgress.scannedItemCount.formatted()) scanned."

            if partialReport.scannedItemCount - lastPersistedScannedItemCount >= 25_000 {
                lastPersistedScannedItemCount = partialReport.scannedItemCount
                await persistReport(partialReport, context: .scanning(generation: generation))
            }
        } else {
            statusMessage = "Scanning \(scanProgress.currentPath) • \(scanProgress.scannedItemCount.formatted()) items…"
        }
    }

    private func finishScan(_ scanReport: ScanReport, generation: UInt64) async {
        guard activity == .scanning(generation: generation) else {
            return
        }

        report = scanReport
        reportState = .current
        progress = nil
        seedExpansionIfNeeded(for: scanReport)
        reconcileSelection()
        statusMessage = "Saving the completed scan…"
        await persistReport(scanReport, context: .scanning(generation: generation))

        guard activity == .scanning(generation: generation) else {
            return
        }

        activity = .idle
        scanTask = nil
        statusMessage = scanReport.issues.isEmpty
            ? "Found \(scanReport.items.count.formatted()) large items."
            : "Found \(scanReport.items.count.formatted()) large items with \(scanReport.issues.count.formatted()) scan issue\(scanReport.issues.count == 1 ? "" : "s")."
        announce(statusMessage)
    }

    private func finishStoppedScan(generation: UInt64) async {
        guard activity == .scanning(generation: generation) else {
            return
        }

        if let report {
            let staleReport = report.markingStale()
            self.report = staleReport
            reportState = .stopped
            await persistReport(staleReport, context: .scanning(generation: generation))
        } else {
            reportState = .noReport
        }
        progress = nil
        activity = .idle
        scanTask = nil
        reconcileSelection()
        statusMessage = "Scan stopped. Partial results are read-only."
        announce(statusMessage)
    }

    private func finishFailedScan(_ error: Error, generation: UInt64) async {
        guard activity == .scanning(generation: generation) else {
            return
        }

        progress = nil
        activity = .idle
        scanTask = nil
        lastError = error.localizedDescription
        reportState = .failed(message: error.localizedDescription)
        statusMessage = "Scan failed."
        announce("Scan failed. \(error.localizedDescription)")
    }

    private func finishPreflight(
        _ request: ValidatedTrashRequest,
        item: DiskItem,
        scanID: UUID
    ) {
        guard activity == .validating(itemID: item.id),
              report?.scanID == scanID,
              reportState == .current else {
            finishCancellationIfNeeded()
            return
        }

        activity = .idle
        deletionTask = nil
        deletionFlow = .confirming(request: request, requiresSecondConfirmation: false)
        statusMessage = "Verified \(item.name). Review before moving it to Trash."
        announce("Verification complete. Review \(item.name) before moving it to Trash.")
    }

    private func finishRevalidation(_ result: DeletionRevalidation) async {
        guard case let .revalidating(originalRequest) = deletionFlow,
              activity == .revalidating(itemID: originalRequest.summary.url.path) else {
            finishCancellationIfNeeded()
            return
        }

        switch result {
        case let .changed(updatedRequest):
            activity = .idle
            deletionTask = nil
            deletionFlow = .confirming(
                request: updatedRequest,
                requiresSecondConfirmation: true
            )
            statusMessage = "The item changed. Review the updated details and confirm again."
            announce(statusMessage)

        case let .unchanged(validatedRequest):
            await moveValidatedRequestToTrash(validatedRequest)
        }
    }

    private func moveValidatedRequestToTrash(_ request: ValidatedTrashRequest) async {
        activity = .movingToTrash(itemID: request.summary.url.path)
        deletionFlow = .moving(request)
        statusMessage = "Moving \(request.summary.url.lastPathComponent) to Trash…"
        announce("Moving to Trash. This operation can no longer be canceled.")

        do {
            let result = try await trashService.moveToTrash(request)
            guard case let .moving(activeRequest) = deletionFlow,
                  activeRequest.summary.url.path == request.summary.url.path else {
                return
            }

            if let report {
                let staleReport = report.removingSubtree(at: request.summary.url).markingStale()
                self.report = staleReport
                reportState = .staleAfterTrash
                reconcileSelection()
                await persistReport(staleReport, context: .movingToTrash(itemID: request.summary.url.path))
            }

            lastTrashResult = result
            deletionTask = nil
            deletionFlow = nil
            activity = .idle
            statusMessage = "Moved \(request.summary.url.lastPathComponent) to Trash. Refreshing…"
            startScan()
            announce("Moved \(request.summary.url.lastPathComponent) to Trash. Refreshing the scan.")
        } catch {
            finishFailedRevalidation(error, request: request)
        }
    }

    private func finishCancelledDeletion() {
        guard !isMovingToTrash else {
            return
        }
        activity = .idle
        deletionTask = nil
        deletionFlow = nil
        statusMessage = reportState == .current ? "Ready" : statusMessage
    }

    private func finishFailedDeletion(_ error: Error, item: DiskItem) {
        if finishCancellationIfNeeded() { return }
        guard case .verifying(let activeItem) = deletionFlow,
              activeItem.id == item.id,
              !isMovingToTrash else {
            return
        }
        activity = .idle
        deletionTask = nil
        blockDeletion(for: item, message: error.localizedDescription)
    }

    private func finishFailedRevalidation(_ error: Error, request: ValidatedTrashRequest) {
        if finishCancellationIfNeeded() { return }
        let isActiveRequest: Bool
        switch deletionFlow {
        case .revalidating(let activeRequest), .moving(let activeRequest):
            isActiveRequest = activeRequest.summary.url.path == request.summary.url.path
        case .verifying, .confirming, .blocked, nil:
            isActiveRequest = false
        }
        guard isActiveRequest else {
            return
        }
        let item = report?.items.first { $0.path == request.summary.url.path }
        activity = .idle
        deletionTask = nil
        if let item {
            blockDeletion(for: item, message: error.localizedDescription)
        } else {
            deletionFlow = nil
            lastError = error.localizedDescription
            statusMessage = "Move to Trash failed."
        }
    }

    private func blockDeletion(for item: DiskItem, message: String) {
        activity = .idle
        deletionFlow = .blocked(item: item, message: message)
        lastError = message
        statusMessage = "Trash operation blocked."
        announce("Trash operation blocked. \(message)")
    }

    @discardableResult
    private func finishCancellationIfNeeded() -> Bool {
        guard case .cancelingDeletion = activity else { return false }
        activity = .idle
        deletionTask = nil
        deletionFlow = nil
        statusMessage = reportState == .current ? "Ready" : statusMessage
        return true
    }

    private func persistReport(_ report: ScanReport, context: CleanerActivity? = nil) async {
        persistenceRevision &+= 1
        let revision = persistenceRevision
        do {
            let saved = try await reportPersistence.save(report, revision: revision)
            guard context == nil || activity == context else { return }
            if saved {
                lastPersistedScannedItemCount = max(lastPersistedScannedItemCount, report.scannedItemCount)
            }
        } catch {
            guard context == nil || activity == context else { return }
            lastError = "Could not save the scan: \(error.localizedDescription)"
            announce(lastError ?? "Could not save the scan.")
        }
    }

    private func scanConfigurationDidChange() {
        persistPreferences()
        guard didBootstrap else { return }

        if let report {
            self.report = report.markingStale()
            reportState = .configurationChanged
            reconcileSelection()
        }

        if canScan {
            statusMessage = "Scan settings changed. Refreshing…"
            startScan()
        } else if activeRoots.isEmpty {
            statusMessage = "Scan settings changed. Select at least one location to refresh."
        }
    }

    private func persistPreferences() {
        preferencesPersistence.save(CleanerPreferences(
            selectedScopeIDs: Set(selectedScopes.map(\.rawValue)),
            customRoots: customRoots,
            showHiddenFiles: showHiddenFiles,
            showPackageContents: showPackageContents,
            showSymbolicLinks: showSymbolicLinks,
            minimumItemSizeBytes: minimumItemSizeBytes,
            maxReturnedItems: maxReturnedItems
        ))
    }

    private func announce(_ message: String) {
        accessibilityAnnouncement = AccessibilityAnnouncement(message: message)
    }

    private func reconcileSelection() {
        let visibleIDs = Set(filteredItems.map(\.id))
        if let selectedItemID, visibleIDs.contains(selectedItemID) {
            return
        }
        selectedItemID = filteredItems.first?.id
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
            for child in node.children {
                visit(child)
            }
        }

        for node in nodes {
            visit(node)
        }
        return ids
    }

    public static func defaultHomeDirectory() -> URL {
        let environment = ProcessInfo.processInfo.environment
        if let override = environment["MAC_CLEANER_HOME"], !override.isEmpty {
            return URL(fileURLWithPath: override, isDirectory: true)
        }

        return FileManager.default.homeDirectoryForCurrentUser
    }
}
