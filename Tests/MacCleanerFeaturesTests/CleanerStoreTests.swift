import Foundation
@testable import MacCleanerCore
@testable import MacCleanerFeatures
import XCTest

@MainActor
final class CleanerStoreTests: XCTestCase {
    nonisolated(unsafe) private var tempRoot: URL!

    override func setUpWithError() throws {
        tempRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("MacCleanerFeaturesTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempRoot, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        if let tempRoot {
            try? FileManager.default.removeItem(at: tempRoot)
        }
    }

    func testSavedReportIsReadOnlyAndAutomaticallyRefreshes() async throws {
        let item = makeItem(name: "saved.bin")
        let savedReport = makeReport(items: [item], freshness: .savedSnapshot)
        let scanner = SleepingScanner()
        let persistence = MemoryReportStore(loadedReport: savedReport)
        let store = makeStore(scanner: scanner, persistence: persistence)

        await store.bootstrap()

        guard case .savedSnapshot = store.reportState else {
            return XCTFail("Expected the decoded report to be presented as a saved snapshot")
        }
        XCTAssertTrue(store.isReportReadOnly)
        XCTAssertTrue(store.isScanning)

        store.requestDeletion(item)
        XCTAssertNil(store.deletionFlow, "Saved results must not enter deletion validation")

        store.stopScan()
        try await waitUntil { !store.isScanning }
    }

    func testLateProgressFromSupersededGenerationCannotOverwriteNewerScan() async throws {
        let first = makeReport(items: [makeItem(name: "first.bin")])
        let late = makeReport(items: [makeItem(name: "late.bin")], isComplete: false)
        let second = makeReport(items: [makeItem(name: "second.bin")])
        let scanner = LateProgressScanner(first: first, late: late, second: second)
        let store = makeStore(scanner: scanner)

        await store.bootstrap()
        try await waitUntil { store.report?.scanID == first.scanID && !store.isScanning }

        store.startScan()
        try await Task.sleep(for: .milliseconds(220))

        XCTAssertEqual(store.report?.scanID, first.scanID, "Late generation-one progress must be ignored")
        XCTAssertNotEqual(store.report?.scanID, late.scanID)

        try await waitUntil { store.report?.scanID == second.scanID && !store.isScanning }
    }

    func testFilteringAlwaysReconcilesSelectionToAVisibleItem() async throws {
        let documents = makeItem(name: "notes.mov", category: .documents)
        let cache = makeItem(name: "render-cache.bin", category: .cache)
        let store = makeStore(scanner: QueueScanner(reports: [makeReport(items: [documents, cache])]))

        await store.bootstrap()
        try await waitUntil { !store.isScanning }
        store.selectedItemID = documents.id

        store.searchText = "render-cache"

        XCTAssertEqual(store.selectedItemID, cache.id)
        XCTAssertEqual(store.selectedItem?.id, cache.id)
        XCTAssertFalse(store.filteredItems.contains(where: { $0.id == documents.id }))
    }

    func testVisibilityOptionsHideRowsWithoutChangingAggregatedReport() async throws {
        let hidden = makeItem(name: ".hidden.bin", isHidden: true)
        let packageRoot = tempRoot.appendingPathComponent("Editor.app", isDirectory: true)
        let packageChild = makeItem(
            name: "payload.bin",
            packageRootPath: packageRoot.path
        )
        let symlink = makeItem(name: "alias", kind: .symbolicLink, eligible: false)
        let report = makeReport(items: [hidden, packageChild, symlink])
        let store = makeStore(scanner: QueueScanner(reports: [report]))

        await store.bootstrap()
        try await waitUntil { !store.isScanning }

        store.showHiddenFiles = false
        store.showPackageContents = false
        store.showSymbolicLinks = false

        XCTAssertTrue(store.filteredItems.isEmpty)
        XCTAssertEqual(store.report?.items.count, 3)

        store.showHiddenFiles = true
        store.showPackageContents = true
        store.showSymbolicLinks = true
        XCTAssertEqual(store.filteredItems.count, 3)
    }

    func testChangedItemRequiresSecondConfirmationAndCommittedTrashCannotDismiss() async throws {
        let item = makeItem(name: "delete-me.bin")
        let initialReport = makeReport(items: [item])
        let refreshedReport = makeReport(items: [])
        let firstRequest = makeRequest(item: item, scanID: initialReport.scanID, verifiedBytes: 100)
        let changedRequest = makeRequest(item: item, scanID: initialReport.scanID, verifiedBytes: 120)
        let validator = StubDeletionValidator(
            preflightRequest: firstRequest,
            revalidations: [.changed(changedRequest), .unchanged(changedRequest)]
        )
        let trash = BlockingTrashService()
        let persistence = MemoryReportStore()
        let store = makeStore(
            scanner: QueueScanner(reports: [initialReport, refreshedReport]),
            validator: validator,
            trash: trash,
            persistence: persistence
        )

        await store.bootstrap()
        try await waitUntil { !store.isScanning }
        store.requestDeletion(item)
        try await waitUntil { store.canConfirmDeletion }

        store.confirmDeletion()
        try await waitUntil {
            if case .confirming(_, let requiresSecondConfirmation) = store.deletionFlow {
                return requiresSecondConfirmation
            }
            return false
        }
        XCTAssertFalse(store.canScan)

        store.confirmDeletion()
        try await waitUntil {
            let hasPendingRequest = await trash.hasPendingRequest()
            return store.isMovingToTrash && hasPendingRequest
        }
        store.dismissDeletion()
        XCTAssertTrue(store.isDeletionPresented)
        XCTAssertTrue(store.isMovingToTrash)

        await trash.complete()
        try await waitUntil { !store.isDeleting && !store.isScanning }

        XCTAssertNil(store.deletionFlow)
        XCTAssertEqual(store.report?.items.count, 0)
        let requestCount = await trash.completedRequestCount()
        let saveCount = await persistence.completedSaveCount()
        XCTAssertEqual(requestCount, 1)
        XCTAssertGreaterThanOrEqual(saveCount, 2)
    }

    func testPreferencesAndCustomRootsPersistImmediately() {
        let preferences = MemoryPreferencesStore()
        let store = makeStore(preferences: preferences)
        let custom = tempRoot.appendingPathComponent("Custom", isDirectory: true)

        store.setScope(.documents, enabled: false)
        store.showHiddenFiles = true
        store.showPackageContents = false
        store.showSymbolicLinks = true
        store.minimumItemSizeBytes = 123
        store.maxReturnedItems = 456
        store.addCustomFolders([custom])

        let saved = preferences.value
        XCTAssertFalse(saved?.selectedScopeIDs.contains(ScanScope.documents.rawValue) == true)
        XCTAssertEqual(saved?.showHiddenFiles, true)
        XCTAssertEqual(saved?.showPackageContents, false)
        XCTAssertEqual(saved?.showSymbolicLinks, true)
        XCTAssertEqual(saved?.minimumItemSizeBytes, 123)
        XCTAssertEqual(saved?.maxReturnedItems, 456)
        XCTAssertEqual(saved?.customRoots.map(\.url), [custom.standardizedFileURL])
    }

    func testScanAffectingSettingsImmediatelyStaleResultsAndRefresh() async throws {
        let item = makeItem(name: "old-result.bin")
        let first = makeReport(items: [item])
        let scanner = QueueScanner(reports: [first])
        let store = makeStore(scanner: scanner)

        await store.bootstrap()
        try await waitUntil { !store.isScanning }
        XCTAssertTrue(store.report?.isActionable == true)

        store.minimumItemSizeBytes += 1

        XCTAssertTrue(store.isScanning)
        XCTAssertEqual(store.reportState, .configurationChanged)
        XCTAssertFalse(store.report?.isActionable == true)
        XCTAssertFalse(store.canScan)
        store.requestDeletion(item)
        XCTAssertNil(store.deletionFlow)

        store.stopScan()
        try await waitUntil { !store.isScanning }
    }

    func testCanceledValidationBlocksScanUntilNoncooperativeValidatorFinishes() async throws {
        let item = makeItem(name: "verify.bin")
        let report = makeReport(items: [item])
        let request = makeRequest(item: item, scanID: report.scanID, verifiedBytes: item.byteSize)
        let validator = BlockingPreflightValidator(request: request)
        let store = makeStore(
            scanner: QueueScanner(reports: [report]),
            validator: validator
        )

        await store.bootstrap()
        try await waitUntil { !store.isScanning }
        store.requestDeletion(item)
        try await waitUntil { await validator.hasPendingPreflight() }

        store.dismissDeletion()

        XCTAssertNil(store.deletionFlow)
        XCTAssertTrue(store.isDeleting)
        XCTAssertFalse(store.canScan)

        await validator.completePreflight()
        try await waitUntil { !store.isDeleting }
        XCTAssertTrue(store.canScan)
    }

    func testCompletedScanWaitsForFinalPersistenceBeforeBecomingIdle() async throws {
        let report = makeReport(items: [makeItem(name: "saved.bin")])
        let persistence = BlockingReportStore()
        let store = makeStore(
            scanner: QueueScanner(reports: [report]),
            persistence: persistence
        )

        await store.bootstrap()
        try await waitUntil { await persistence.hasPendingSave() }

        XCTAssertTrue(store.isScanning)
        XCTAssertFalse(store.canScan)
        XCTAssertTrue(store.report?.isActionable == true)

        await persistence.completeSave()
        try await waitUntil { !store.isScanning }
        XCTAssertTrue(store.canScan)
    }

    private func makeStore(
        scanner: any FileScanning = QueueScanner(reports: []),
        validator: (any DeletionValidating)? = nil,
        trash: any TrashManaging = ImmediateTrashService(),
        persistence: any ScanReportPersisting = MemoryReportStore(),
        preferences: any CleanerPreferencesPersisting = MemoryPreferencesStore()
    ) -> CleanerStore {
        CleanerStore(
            scanner: scanner,
            deletionValidator: validator,
            trashService: trash,
            reportPersistence: persistence,
            preferencesPersistence: preferences,
            homeDirectory: tempRoot
        )
    }

    private func makeItem(
        name: String,
        kind: DiskItemKind = .file,
        category: DiskItemCategory = .downloads,
        isHidden: Bool = false,
        packageRootPath: String? = nil,
        eligible: Bool = true
    ) -> DiskItem {
        let url = tempRoot.appendingPathComponent(name, isDirectory: kind == .folder || kind == .package)
        return DiskItem(
            url: url,
            kind: kind,
            category: category,
            risk: category == .cache ? .low : .medium,
            byteSize: 100,
            fileCount: kind == .file || kind == .symbolicLink ? 1 : 2,
            childFolderCount: kind == .folder || kind == .package ? 1 : 0,
            modifiedAt: nil,
            lastAccessedAt: nil,
            rootPath: tempRoot.path,
            fileIdentity: FileIdentity(deviceID: 1, fileID: UInt64(name.utf8.reduce(0) { $0 + UInt64($1) })),
            canonicalPath: url.path,
            coverage: .complete,
            deletionEligibility: eligible ? .eligible : .blocked("Read only"),
            classificationRationale: "Test classification.",
            applicationProfile: nil,
            packageRootPath: packageRootPath,
            isHidden: isHidden
        )
    }

    private func makeReport(
        items: [DiskItem],
        freshness: ScanReportFreshness = .current,
        isComplete: Bool = true
    ) -> ScanReport {
        ScanReport(
            roots: [ScanRoot(title: "Fixture", url: tempRoot)],
            items: items,
            issues: [],
            totalBytes: items.reduce(0) { $0 + $1.byteSize },
            scannedItemCount: items.count,
            scannedFileCount: items.count,
            scannedFolderCount: 0,
            startedAt: Date(),
            finishedAt: Date(),
            isComplete: isComplete,
            freshness: freshness
        )
    }

    private func makeRequest(
        item: DiskItem,
        scanID: UUID,
        verifiedBytes: Int64
    ) -> ValidatedTrashRequest {
        ValidatedTrashRequest(
            summary: DeletionPreflightSummary(
                url: item.url,
                canonicalPath: item.canonicalPath,
                kind: item.kind,
                category: item.category,
                risk: item.risk,
                classificationRationale: item.classificationRationale,
                scannedByteSize: item.byteSize,
                verifiedByteSize: verifiedBytes,
                fileCount: 1,
                folderCount: 0,
                fingerprint: "fingerprint-\(verifiedBytes)",
                identity: item.fileIdentity!
            ),
            scanID: scanID,
            scanRootPath: item.rootPath,
            configuredRoots: [ScanRoot(title: "Fixture", url: tempRoot)]
        )
    }

    private func waitUntil(
        timeout: Duration = .seconds(3),
        condition: @escaping @MainActor () async -> Bool
    ) async throws {
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: timeout)
        while !(await condition()) {
            guard clock.now < deadline else {
                throw TestFailure.timedOut
            }
            try await Task.sleep(for: .milliseconds(10))
        }
    }
}

private enum TestFailure: Error {
    case timedOut
}

private actor QueueScanner: FileScanning {
    private var reports: [ScanReport]

    init(reports: [ScanReport]) {
        self.reports = reports
    }

    func scan(
        roots: [ScanRoot],
        options: ScanOptions,
        progress: ScanProgressHandler?
    ) async throws -> ScanReport {
        guard !reports.isEmpty else {
            try await Task.sleep(for: .seconds(30))
            throw CancellationError()
        }
        return reports.removeFirst()
    }
}

private actor SleepingScanner: FileScanning {
    func scan(
        roots: [ScanRoot],
        options: ScanOptions,
        progress: ScanProgressHandler?
    ) async throws -> ScanReport {
        try await Task.sleep(for: .seconds(30))
        throw CancellationError()
    }
}

private actor LateProgressScanner: FileScanning {
    private let first: ScanReport
    private let late: ScanReport
    private let second: ScanReport
    private var callCount = 0

    init(first: ScanReport, late: ScanReport, second: ScanReport) {
        self.first = first
        self.late = late
        self.second = second
    }

    func scan(
        roots: [ScanRoot],
        options: ScanOptions,
        progress: ScanProgressHandler?
    ) async throws -> ScanReport {
        callCount += 1
        if callCount == 1 {
            Task {
                try? await Task.sleep(for: .milliseconds(150))
                await progress?(ScanProgress(
                    currentPath: late.items.first?.path ?? "late",
                    scannedItemCount: 1,
                    scannedByteCount: late.totalBytes,
                    partialReport: late
                ))
            }
            return first
        }

        try await Task.sleep(for: .milliseconds(400))
        return second
    }
}

private actor StubDeletionValidator: DeletionValidating {
    private let preflightRequest: ValidatedTrashRequest
    private var revalidations: [DeletionRevalidation]

    init(
        preflightRequest: ValidatedTrashRequest,
        revalidations: [DeletionRevalidation]
    ) {
        self.preflightRequest = preflightRequest
        self.revalidations = revalidations
    }

    func preflight(item: DiskItem, in report: ScanReport) async throws -> ValidatedTrashRequest {
        preflightRequest
    }

    func revalidate(_ request: ValidatedTrashRequest) async throws -> DeletionRevalidation {
        revalidations.removeFirst()
    }
}

private actor BlockingPreflightValidator: DeletionValidating {
    private let request: ValidatedTrashRequest
    private var continuation: CheckedContinuation<ValidatedTrashRequest, Never>?

    init(request: ValidatedTrashRequest) {
        self.request = request
    }

    func hasPendingPreflight() -> Bool { continuation != nil }

    func preflight(item: DiskItem, in report: ScanReport) async throws -> ValidatedTrashRequest {
        await withCheckedContinuation { continuation in
            self.continuation = continuation
        }
    }

    func revalidate(_ request: ValidatedTrashRequest) async throws -> DeletionRevalidation {
        .unchanged(request)
    }

    func completePreflight() {
        continuation?.resume(returning: request)
        continuation = nil
    }
}

private actor BlockingTrashService: TrashManaging {
    private var continuation: CheckedContinuation<TrashOperationResult, Never>?
    private(set) var requestCount = 0

    func hasPendingRequest() -> Bool {
        continuation != nil
    }

    func completedRequestCount() -> Int {
        requestCount
    }

    func moveToTrash(_ request: ValidatedTrashRequest) async throws -> TrashOperationResult {
        requestCount += 1
        return await withCheckedContinuation { continuation in
            self.continuation = continuation
        }
    }

    func complete() {
        continuation?.resume(returning: TrashOperationResult(items: []))
        continuation = nil
    }
}

private actor ImmediateTrashService: TrashManaging {
    func moveToTrash(_ request: ValidatedTrashRequest) async throws -> TrashOperationResult {
        TrashOperationResult(items: [])
    }
}

private actor MemoryReportStore: ScanReportPersisting {
    private let loadedReport: ScanReport?
    private var saves: [(revision: UInt64, report: ScanReport)] = []

    init(loadedReport: ScanReport? = nil) {
        self.loadedReport = loadedReport
    }

    func completedSaveCount() -> Int { saves.count }

    func load() async throws -> ScanReport? {
        loadedReport
    }

    func save(_ report: ScanReport, revision: UInt64) async throws -> Bool {
        guard revision > (saves.last?.revision ?? 0) else {
            return false
        }
        saves.append((revision, report))
        return true
    }

    func delete(revision: UInt64) async throws -> Bool {
        true
    }
}

private actor BlockingReportStore: ScanReportPersisting {
    private var continuation: CheckedContinuation<Bool, Never>?

    func hasPendingSave() -> Bool { continuation != nil }

    func load() async throws -> ScanReport? { nil }

    func save(_ report: ScanReport, revision: UInt64) async throws -> Bool {
        await withCheckedContinuation { continuation in
            self.continuation = continuation
        }
    }

    func delete(revision: UInt64) async throws -> Bool { true }

    func completeSave() {
        continuation?.resume(returning: true)
        continuation = nil
    }
}

private final class MemoryPreferencesStore: CleanerPreferencesPersisting, @unchecked Sendable {
    private let lock = NSLock()
    private var storedValue: CleanerPreferences?

    init(value: CleanerPreferences? = nil) {
        storedValue = value
    }

    var value: CleanerPreferences? {
        lock.withLock { storedValue }
    }

    func load() -> CleanerPreferences? {
        value
    }

    func save(_ preferences: CleanerPreferences) {
        lock.withLock { storedValue = preferences }
    }
}
