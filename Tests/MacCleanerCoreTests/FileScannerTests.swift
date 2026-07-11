import Foundation
@testable import MacCleanerCore
import XCTest

final class FileScannerTests: XCTestCase {
    private var tempRoot: URL!

    override func setUpWithError() throws {
        tempRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("MacCleanerTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempRoot, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        if let tempRoot {
            try? FileManager.default.removeItem(at: tempRoot)
        }
    }

    func testScannerAggregatesFoldersAndSortsLargestFirst() async throws {
        let alpha = tempRoot.appendingPathComponent("Alpha", isDirectory: true)
        let beta = tempRoot.appendingPathComponent("Beta", isDirectory: true)
        try FileManager.default.createDirectory(at: alpha, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: beta, withIntermediateDirectories: true)
        try writeFile(alpha.appendingPathComponent("large.bin"), byteCount: 2 * 1_024 * 1_024)
        try writeFile(beta.appendingPathComponent("medium.bin"), byteCount: 1 * 1_024 * 1_024)
        try writeFile(tempRoot.appendingPathComponent("small.bin"), byteCount: 512 * 1_024)

        let report = try await makeScanner().scan(
            roots: [ScanRoot(title: "Fixture", url: tempRoot, categoryHint: .documents, riskHint: .high)],
            options: ScanOptions(minimumItemSizeBytes: 0)
        )

        let root = try XCTUnwrap(report.items.first { $0.path == tempRoot.path })
        let alphaItem = try XCTUnwrap(report.items.first { $0.path == alpha.path })
        let betaItem = try XCTUnwrap(report.items.first { $0.path == beta.path })

        XCTAssertGreaterThan(root.byteSize, alphaItem.byteSize)
        XCTAssertGreaterThan(alphaItem.byteSize, betaItem.byteSize)
        XCTAssertEqual(root.fileCount, 3)
        XCTAssertEqual(root.childFolderCount, 2)
        XCTAssertFalse(root.isDeletableCandidate)
        XCTAssertEqual(report.items.first?.path, root.path)

        let tree = DiskItemTreeBuilder.build(from: report.items)
        let rootNode = try XCTUnwrap(tree.first { $0.item.path == tempRoot.path })
        let alphaNode = try XCTUnwrap(rootNode.children.first { $0.item.path == alpha.path })
        XCTAssertNotNil(alphaNode.children.first { $0.item.name == "large.bin" })
    }

    func testMinimumSizeFilterRemovesSmallFiles() async throws {
        let small = tempRoot.appendingPathComponent("small.bin")
        let large = tempRoot.appendingPathComponent("large.bin")
        try writeFile(small, byteCount: 16 * 1_024)
        try writeFile(large, byteCount: 2 * 1_024 * 1_024)

        let report = try await makeScanner().scan(
            roots: [ScanRoot(title: "Fixture", url: tempRoot, categoryHint: .downloads, riskHint: .medium)],
            options: ScanOptions(minimumItemSizeBytes: 1 * 1_024 * 1_024)
        )

        XCTAssertNil(report.items.first { $0.path == small.path })
        XCTAssertNotNil(report.items.first { $0.path == large.path })
    }

    func testSymlinkIsReportedButNeverDeletableOrTraversed() async throws {
        let target = tempRoot.appendingPathComponent("target.bin")
        let link = tempRoot.appendingPathComponent("target-link.bin")
        try writeFile(target, byteCount: 128 * 1_024)
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: target)

        let report = try await makeScanner().scan(
            roots: [ScanRoot(title: "Fixture", url: tempRoot, categoryHint: .downloads, riskHint: .medium)],
            options: ScanOptions(minimumItemSizeBytes: 1 * 1_024 * 1_024)
        )

        let linkItem = try XCTUnwrap(report.items.first { $0.path == link.path })
        XCTAssertEqual(linkItem.kind, .symbolicLink)
        XCTAssertFalse(linkItem.isDeletableCandidate)
        XCTAssertEqual(report.scannedFileCount, 2)
    }

    func testDirectorySymlinkOutsideRootIsNeverTraversed() async throws {
        let scanRoot = tempRoot.appendingPathComponent("Scan", isDirectory: true)
        let outside = tempRoot.appendingPathComponent("Outside", isDirectory: true)
        let link = scanRoot.appendingPathComponent("Outside Link", isDirectory: true)
        try FileManager.default.createDirectory(at: scanRoot, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: outside, withIntermediateDirectories: true)
        let outsideFile = outside.appendingPathComponent("outside.bin")
        try writeFile(outsideFile, byteCount: 1 * 1_024 * 1_024)
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: outside)

        let report = try await makeScanner().scan(
            roots: [ScanRoot(title: "Fixture", url: scanRoot, categoryHint: .downloads, riskHint: .medium)],
            options: ScanOptions(minimumItemSizeBytes: 0)
        )

        let linkItem = try XCTUnwrap(report.items.first { $0.path == link.path })
        XCTAssertEqual(linkItem.kind, .symbolicLink)
        XCTAssertFalse(linkItem.isDeletableCandidate)
        XCTAssertNil(report.items.first { $0.path == outsideFile.path })
        XCTAssertEqual(report.scannedFileCount, 1)
        XCTAssertLessThan(report.totalBytes, 1 * 1_024 * 1_024)
    }

    func testKnownAppProfileBuildsExpectedRoots() {
        let roots = KnownAppProfile.codex.roots(homeDirectory: tempRoot)
        let paths = Set(roots.map(\.url.path))

        XCTAssertTrue(paths.contains(tempRoot.appendingPathComponent(".codex", isDirectory: true).path))
        XCTAssertTrue(paths.contains(tempRoot.appendingPathComponent("Library/Application Support/Codex", isDirectory: true).path))
        XCTAssertTrue(roots.allSatisfy { $0.categoryHint == nil && $0.riskHint == nil })
    }

    func testClassifierProtectsSystemScope() {
        let classifier = ItemClassifier(homeDirectory: tempRoot)
        let root = ScanRoot(
            title: "System Caches",
            url: URL(fileURLWithPath: "/Library/Caches", isDirectory: true),
            categoryHint: .cache,
            riskHint: .protected,
            isSystemScope: true
        )

        let classification = classifier.classify(
            url: URL(fileURLWithPath: "/Library/Caches/com.example"),
            kind: .folder,
            root: root
        )

        XCTAssertEqual(classification.risk, .protected)
        XCTAssertFalse(classification.isDeletableCandidate)
    }

    func testScanReportRemovesDeletedItems() async throws {
        let file = tempRoot.appendingPathComponent("large.bin")
        try writeFile(file, byteCount: 1 * 1_024 * 1_024)

        let report = try await makeScanner().scan(
            roots: [ScanRoot(title: "Fixture", url: tempRoot, categoryHint: .downloads, riskHint: .medium)],
            options: ScanOptions(minimumItemSizeBytes: 0)
        )

        let item = try XCTUnwrap(report.items.first { $0.path == file.path })
        let filtered = report.removingItems(withIDs: [item.id])

        XCTAssertNil(filtered.items.first { $0.id == item.id })
        XCTAssertLessThan(filtered.items.count, report.items.count)
        XCTAssertEqual(filtered.freshness, .stale)
        XCTAssertFalse(filtered.isActionable)
    }

    func testScannerEmitsPartialSnapshots() async throws {
        let file = tempRoot.appendingPathComponent("large.bin")
        try writeFile(file, byteCount: 1 * 1_024 * 1_024)
        let collector = SnapshotCollector()

        _ = try await makeScanner().scan(
            roots: [ScanRoot(title: "Fixture", url: tempRoot, categoryHint: .downloads, riskHint: .medium)],
            options: ScanOptions(minimumItemSizeBytes: 0, snapshotItemInterval: 1, snapshotInterval: 0.1)
        ) { progress in
            if let partialReport = progress.partialReport {
                await collector.append(partialReport)
            }
        }

        let snapshots = await collector.snapshots
        XCTAssertFalse(snapshots.isEmpty)
        XCTAssertTrue(snapshots.contains { report in
            report.items.contains { $0.path == file.path }
        })
        XCTAssertEqual(Set(snapshots.map(\.scanID)).count, 1)
        XCTAssertTrue(snapshots.allSatisfy { !$0.isComplete && !$0.isActionable })
    }

    func testNestedRootsAreEnumeratedOnceAndEveryConfiguredRootIsProtected() async throws {
        let caches = tempRoot.appendingPathComponent("Library/Caches", isDirectory: true)
        let nested = caches.appendingPathComponent("CapCut", isDirectory: true)
        try FileManager.default.createDirectory(at: nested, withIntermediateDirectories: true)
        try writeFile(nested.appendingPathComponent("payload.bin"), byteCount: 1 * 1_024 * 1_024)

        let homeRoot = ScanRoot(title: "Home", url: tempRoot, riskHint: .high)
        let cacheRoot = ScanRoot(title: "Caches", url: caches, categoryHint: .cache, riskHint: .low)
        let nestedRoot = ScanRoot(title: "CapCut", url: nested, categoryHint: .capCut, riskHint: .high)
        let options = ScanOptions(minimumItemSizeBytes: 0)
        let first = try await makeScanner().scan(roots: [homeRoot, cacheRoot, nestedRoot], options: options)
        let second = try await makeScanner().scan(roots: [nestedRoot, cacheRoot, homeRoot], options: options)

        XCTAssertEqual(first.totalBytes, second.totalBytes)
        XCTAssertEqual(first.scannedFileCount, 1)
        XCTAssertEqual(second.scannedFileCount, 1)
        XCTAssertFalse(try XCTUnwrap(first.items.first { $0.path == caches.path }).isDeletableCandidate)
        XCTAssertFalse(try XCTUnwrap(first.items.first { $0.path == nested.path }).isDeletableCandidate)
        let library = tempRoot.appendingPathComponent("Library", isDirectory: true)
        let libraryItem = try XCTUnwrap(first.items.first { $0.path == library.path })
        XCTAssertFalse(libraryItem.isDeletableCandidate)
        XCTAssertEqual(libraryItem.deletionEligibility.reason, "This folder contains a configured scan root.")
        XCTAssertEqual(first.items.map(\.path).sorted(), second.items.map(\.path).sorted())
    }

    func testHiddenAndPackageContentsAlwaysContributeToAggregation() async throws {
        let package = tempRoot.appendingPathComponent("Fixture.app", isDirectory: true)
        let contents = package.appendingPathComponent("Contents", isDirectory: true)
        let hidden = contents.appendingPathComponent(".payload.bin")
        try FileManager.default.createDirectory(at: contents, withIntermediateDirectories: true)
        try writeFile(hidden, byteCount: 1 * 1_024 * 1_024)

        let report = try await makeScanner().scan(
            roots: [ScanRoot(title: "Fixture", url: tempRoot, categoryHint: .downloads, riskHint: .medium)],
            options: ScanOptions(
                includeHiddenFiles: false,
                includePackageContents: false,
                minimumItemSizeBytes: 0
            )
        )

        let rootItem = try XCTUnwrap(report.items.first { $0.path == tempRoot.path })
        let packageItem = try XCTUnwrap(report.items.first { $0.path == package.path })
        let hiddenItem = try XCTUnwrap(report.items.first { $0.path == hidden.path })
        XCTAssertGreaterThan(rootItem.byteSize, 0)
        XCTAssertEqual(rootItem.byteSize, packageItem.byteSize)
        XCTAssertTrue(hiddenItem.isHidden)
        XCTAssertEqual(hiddenItem.packageRootPath, package.path)
        XCTAssertFalse(hiddenItem.isDeletableCandidate)
        XCTAssertEqual(packageItem.kind, .package)
        XCTAssertTrue(packageItem.isDeletableCandidate)
    }

    func testHardLinksCountAllocatedBytesOnlyOnce() async throws {
        let original = tempRoot.appendingPathComponent("original.bin")
        let alias = tempRoot.appendingPathComponent("alias.bin")
        try writeFile(original, byteCount: 1 * 1_024 * 1_024)
        try FileManager.default.linkItem(at: original, to: alias)

        let report = try await makeScanner().scan(
            roots: [ScanRoot(title: "Fixture", url: tempRoot, categoryHint: .downloads, riskHint: .medium)],
            options: ScanOptions(minimumItemSizeBytes: 0)
        )
        let rootItem = try XCTUnwrap(report.items.first { $0.path == tempRoot.path })
        let linkedItems = report.items.filter { $0.path == original.path || $0.path == alias.path }

        XCTAssertEqual(linkedItems.count, 2)
        XCTAssertEqual(rootItem.byteSize, linkedItems.reduce(0) { $0 + $1.byteSize })
        XCTAssertEqual(report.totalBytes, rootItem.byteSize)
        XCTAssertTrue(linkedItems.contains { $0.byteSize == 0 })
    }

    func testHardLinkObservationsMergeRiskAndRootProtectionConservatively() async throws {
        let caches = tempRoot.appendingPathComponent("Library/Caches", isDirectory: true)
        let documents = tempRoot.appendingPathComponent("Documents", isDirectory: true)
        try FileManager.default.createDirectory(at: caches, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: documents, withIntermediateDirectories: true)

        let cacheLink = caches.appendingPathComponent("shared.bin")
        let documentLink = documents.appendingPathComponent("shared.bin")
        try writeFile(cacheLink, byteCount: 1 * 1_024 * 1_024)
        try FileManager.default.linkItem(at: cacheLink, to: documentLink)

        let report = try await makeScanner().scan(
            roots: [
                ScanRoot(title: "Caches", url: caches, categoryHint: .cache, riskHint: .low),
                ScanRoot(title: "Documents", url: documents, categoryHint: .documents, riskHint: .high),
                ScanRoot(title: "Protected Link", url: documentLink, categoryHint: .documents, riskHint: .high)
            ],
            options: ScanOptions(minimumItemSizeBytes: 0)
        )

        let linkedItems = report.items.filter { $0.path == cacheLink.path || $0.path == documentLink.path }
        XCTAssertEqual(linkedItems.count, 2)
        XCTAssertTrue(linkedItems.allSatisfy { $0.risk == .high })
        XCTAssertTrue(linkedItems.allSatisfy { !$0.isDeletableCandidate })
        XCTAssertTrue(linkedItems.allSatisfy { $0.classificationRationale.contains("hard-linked") || $0.path == documentLink.path })
    }

    func testScanPlanResolvesSymlinkRootIdentityAgainstTarget() throws {
        let target = tempRoot.appendingPathComponent("Target", isDirectory: true)
        let link = tempRoot.appendingPathComponent("Alias", isDirectory: true)
        try FileManager.default.createDirectory(at: target, withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: target)

        let plan = ScanPlan(roots: [ScanRoot(title: "Alias", url: link)])
        let plannedRoot = try XCTUnwrap(plan.enumerationRoots.first)

        XCTAssertEqual(plannedRoot.canonicalPath, target.path)
        XCTAssertEqual(plannedRoot.identity, plan.rules.first?.identity)
    }

    func testContentCategoryKeepsAppCacheLowRiskWhenProfileIsSeparate() throws {
        let cacheURL = tempRoot.appendingPathComponent("Library/Caches/CapCut/cache.bin")
        let root = try XCTUnwrap(KnownAppProfile.capCut.roots(homeDirectory: tempRoot).first {
            $0.url.path == tempRoot.appendingPathComponent("Library/Caches/CapCut").path
        })
        let classification = ItemClassifier(homeDirectory: tempRoot).classify(
            url: cacheURL,
            kind: .file,
            matchingRoots: [root]
        )

        XCTAssertEqual(classification.category, .cache)
        XCTAssertEqual(classification.risk, .low)
        XCTAssertEqual(classification.applicationProfile, "CapCut")
        XCTAssertTrue(classification.rationale.contains("Cache"))
    }

    func testExplicitRiskHintCanOnlyRaiseInferredRisk() {
        let cacheURL = tempRoot.appendingPathComponent("Library/Caches/Explicit/cache.bin")
        let root = ScanRoot(
            title: "Explicit High-Risk Scope",
            url: tempRoot.appendingPathComponent("Library/Caches/Explicit"),
            categoryHint: .cache,
            riskHint: .high
        )

        let classification = ItemClassifier(homeDirectory: tempRoot).classify(
            url: cacheURL,
            kind: .file,
            matchingRoots: [root]
        )

        XCTAssertEqual(classification.category, .cache)
        XCTAssertEqual(classification.risk, .high)
    }

    func testApplicationSupportLibraryAndProjectUseContentFirstRisk() {
        let classifier = ItemClassifier(homeDirectory: tempRoot)
        let profileRoot = ScanRoot(
            title: "CapCut",
            url: tempRoot.appendingPathComponent("Library/Application Support/CapCut")
        )
        let support = classifier.classify(
            url: profileRoot.url.appendingPathComponent("state.db"),
            kind: .file,
            matchingRoots: [profileRoot]
        )
        let library = classifier.classify(
            url: tempRoot.appendingPathComponent("Libraries/Photos.photoslibrary"),
            kind: .package,
            matchingRoots: []
        )
        let project = classifier.classify(
            url: tempRoot.appendingPathComponent("Projects/MacCleaner/Sources/App.swift"),
            kind: .file,
            matchingRoots: []
        )
        let downloadedProject = classifier.classify(
            url: tempRoot.appendingPathComponent("Downloads/Example.xcodeproj"),
            kind: .package,
            matchingRoots: []
        )
        let downloadedLibrary = classifier.classify(
            url: tempRoot.appendingPathComponent("Downloads/Photos.photoslibrary"),
            kind: .package,
            matchingRoots: []
        )

        XCTAssertEqual(support.category, .applicationSupport)
        XCTAssertEqual(support.risk, .medium)
        XCTAssertEqual(support.applicationProfile, "CapCut")
        XCTAssertEqual(library.category, .libraries)
        XCTAssertEqual(library.risk, .high)
        XCTAssertEqual(project.category, .projectData)
        XCTAssertEqual(project.risk, .high)
        XCTAssertEqual(downloadedProject.category, .projectData)
        XCTAssertEqual(downloadedProject.risk, .high)
        XCTAssertEqual(downloadedLibrary.category, .libraries)
        XCTAssertEqual(downloadedLibrary.risk, .high)
    }

    func testContentFirstRiskMatrix() {
        let classifier = ItemClassifier(homeDirectory: tempRoot)
        let cases: [(String, DiskItemCategory, DeletionRisk)] = [
            ("Library/Caches/cache.bin", .cache, .low),
            ("Library/Logs/app.log", .logs, .low),
            ("Library/Developer/Xcode/DerivedData/App/index", .developerData, .low),
            ("Projects/App/build/output.bin", .developerData, .low),
            ("Library/Application Support/App/state.db", .applicationSupport, .medium),
            ("Library/Developer/Tool/state.db", .developerData, .medium),
            ("Downloads/archive.zip", .downloads, .medium),
            ("Backups/archive.bin", .backups, .medium),
            (".codex/sessions/session.jsonl", .codex, .medium),
            ("Documents/notes.txt", .documents, .high),
            ("Movies/clip.mov", .media, .high),
            ("Libraries/Photos.photoslibrary", .libraries, .high),
            ("Projects/App/Sources/App.swift", .projectData, .high)
        ]

        for (relativePath, expectedCategory, expectedRisk) in cases {
            let classification = classifier.classify(
                url: tempRoot.appendingPathComponent(relativePath),
                kind: .file,
                matchingRoots: []
            )
            XCTAssertEqual(classification.category, expectedCategory, relativePath)
            XCTAssertEqual(classification.risk, expectedRisk, relativePath)
        }

        let outside = classifier.classify(
            url: tempRoot.deletingLastPathComponent().appendingPathComponent("outside.bin"),
            kind: .file,
            matchingRoots: []
        )
        let applications = classifier.classify(
            url: tempRoot.appendingPathComponent("Applications/Example.app"),
            kind: .package,
            matchingRoots: []
        )
        XCTAssertEqual(outside.risk, .protected)
        XCTAssertFalse(outside.isDeletableCandidate)
        XCTAssertEqual(applications.risk, .protected)
        XCTAssertFalse(applications.isDeletableCandidate)
    }

    func testScannerHonorsCancellationBeforeEnumeration() async {
        let scanner = makeScanner()
        let root = tempRoot!
        let task = Task {
            try await scanner.scan(
                roots: [ScanRoot(title: "Fixture", url: root)],
                options: ScanOptions(minimumItemSizeBytes: 0)
            )
        }
        task.cancel()

        do {
            _ = try await task.value
            XCTFail("Expected cancellation")
        } catch is CancellationError {
            // Expected.
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testScannerHonorsCancellationDuringEnumeration() async throws {
        for index in 0..<150 {
            try writeFile(tempRoot.appendingPathComponent("item-\(index).bin"), byteCount: 1)
        }

        do {
            _ = try await makeScanner().scan(
                roots: [ScanRoot(title: "Fixture", url: tempRoot)],
                options: ScanOptions(minimumItemSizeBytes: 0)
            ) { progress in
                if progress.scannedItemCount >= 100 {
                    withUnsafeCurrentTask { $0?.cancel() }
                }
            }
            XCTFail("Expected cancellation during enumeration")
        } catch is CancellationError {
            // Expected.
        }
    }

    func testUnreadableDescendantMarksAncestorsIncomplete() async throws {
        let unreadable = tempRoot.appendingPathComponent("Unreadable", isDirectory: true)
        try FileManager.default.createDirectory(at: unreadable, withIntermediateDirectories: true)
        try writeFile(unreadable.appendingPathComponent("payload.bin"), byteCount: 1_024)
        try FileManager.default.setAttributes([.posixPermissions: 0], ofItemAtPath: unreadable.path)
        defer {
            try? FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: unreadable.path)
        }

        let report = try await makeScanner().scan(
            roots: [ScanRoot(title: "Fixture", url: tempRoot)],
            options: ScanOptions(minimumItemSizeBytes: 0)
        )

        let rootItem = try XCTUnwrap(report.items.first { $0.path == tempRoot.path })
        let unreadableItem = try XCTUnwrap(report.items.first { $0.path == unreadable.path })
        XCTAssertFalse(report.issues.isEmpty)
        XCTAssertFalse(rootItem.coverage.isComplete)
        XCTAssertFalse(unreadableItem.coverage.isComplete)
        XCTAssertFalse(rootItem.isDeletableCandidate)
        XCTAssertFalse(unreadableItem.isDeletableCandidate)
    }

    func testSimulatedMountBoundaryIsSkippedAndMarksCoverageIncomplete() async throws {
        let mounted = tempRoot.appendingPathComponent("Mounted", isDirectory: true)
        let payload = mounted.appendingPathComponent("payload.bin")
        try FileManager.default.createDirectory(at: mounted, withIntermediateDirectories: true)
        try writeFile(payload, byteCount: 1 * 1_024 * 1_024)
        let mountedPath = mounted.path
        let scanner = FileScanner(
            classifier: ItemClassifier(homeDirectory: tempRoot),
            identityProvider: { url in
                guard let identity = FileSystemSafety.identity(at: url) else { return nil }
                if FileSystemSafety.isPath(url.standardizedFileURL.path, insideOrEqualTo: mountedPath) {
                    return FileIdentity(deviceID: identity.deviceID &+ 1, fileID: identity.fileID)
                }
                return identity
            }
        )

        let report = try await scanner.scan(
            roots: [ScanRoot(title: "Fixture", url: tempRoot)],
            options: ScanOptions(minimumItemSizeBytes: 0)
        )

        let rootItem = try XCTUnwrap(report.items.first { $0.path == tempRoot.path })
        let mountedItem = try XCTUnwrap(report.items.first { $0.path == mounted.path })
        XCTAssertFalse(rootItem.coverage.isComplete)
        XCTAssertFalse(mountedItem.coverage.isComplete)
        XCTAssertFalse(mountedItem.isDeletableCandidate)
        XCTAssertNil(report.items.first { $0.path == payload.path })
        XCTAssertEqual(report.totalBytes, 0)
        XCTAssertTrue(report.issues.contains { $0.path == mounted.path && $0.message.contains("Mounted volume") })
    }

    private func makeScanner() -> FileScanner {
        FileScanner(classifier: ItemClassifier(homeDirectory: tempRoot))
    }

    private func writeFile(_ url: URL, byteCount: Int) throws {
        let data = Data(repeating: 0x2A, count: byteCount)
        try data.write(to: url, options: .atomic)
    }
}

private actor SnapshotCollector {
    private(set) var snapshots: [ScanReport] = []

    func append(_ report: ScanReport) {
        snapshots.append(report)
    }
}
