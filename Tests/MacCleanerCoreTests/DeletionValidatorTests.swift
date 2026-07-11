import Foundation
import MacCleanerCore
import XCTest

final class DeletionValidatorTests: XCTestCase {
    private var tempRoot: URL!
    private var extraCleanupURLs: [URL] = []

    override func setUpWithError() throws {
        tempRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("MacCleanerDeletionTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempRoot, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        for url in extraCleanupURLs { try? FileManager.default.removeItem(at: url) }
        if let tempRoot { try? FileManager.default.removeItem(at: tempRoot) }
    }

    func testPreflightRejectsFileReplacementAtSamePath() async throws {
        let file = tempRoot.appendingPathComponent("cache.bin")
        try writeFile(file, byteCount: 128 * 1_024)
        let report = try await scan()
        let item = try XCTUnwrap(report.items.first { $0.path == file.path })

        try FileManager.default.removeItem(at: file)
        try writeFile(file, byteCount: 64 * 1_024)

        do {
            _ = try await validator().preflight(item: item, in: report)
            XCTFail("Expected identity validation to fail")
        } catch let error as DeletionValidationError {
            XCTAssertEqual(error, .identityChanged)
        }
    }

    func testPreflightRejectsAncestorReplacedByOutsideSymlink() async throws {
        let container = tempRoot.appendingPathComponent("Container", isDirectory: true)
        let file = container.appendingPathComponent("cache.bin")
        try FileManager.default.createDirectory(at: container, withIntermediateDirectories: true)
        try writeFile(file, byteCount: 128 * 1_024)
        let report = try await scan()
        let item = try XCTUnwrap(report.items.first { $0.path == file.path })

        let outside = tempRoot.deletingLastPathComponent()
            .appendingPathComponent("MacCleanerOutside-\(UUID().uuidString)", isDirectory: true)
        extraCleanupURLs.append(outside)
        try FileManager.default.createDirectory(at: outside, withIntermediateDirectories: true)
        try writeFile(outside.appendingPathComponent("cache.bin"), byteCount: 128 * 1_024)
        try FileManager.default.removeItem(at: container)
        try FileManager.default.createSymbolicLink(at: container, withDestinationURL: outside)

        do {
            _ = try await validator().preflight(item: item, in: report)
            XCTFail("Expected containment validation to fail")
        } catch let error as DeletionValidationError {
            XCTAssertEqual(error, .outsideScanRoot)
        }
    }

    func testFolderChangeRequiresAnotherConfirmationThenStabilizes() async throws {
        let folder = tempRoot.appendingPathComponent("CacheFolder", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try writeFile(folder.appendingPathComponent("first.bin"), byteCount: 64 * 1_024)
        let report = try await scan()
        let item = try XCTUnwrap(report.items.first { $0.path == folder.path })
        let validator = validator()
        let initial = try await validator.preflight(item: item, in: report)

        try writeFile(folder.appendingPathComponent("second.bin"), byteCount: 96 * 1_024)
        let changed = try await validator.revalidate(initial)

        XCTAssertTrue(changed.requiresAnotherConfirmation)
        XCTAssertGreaterThan(changed.request.summary.verifiedByteSize, initial.summary.verifiedByteSize)
        XCTAssertGreaterThan(changed.request.summary.fileCount, initial.summary.fileCount)

        let stable = try await validator.revalidate(changed.request)
        XCTAssertFalse(stable.requiresAnotherConfirmation)
    }

    func testPackageContentsAreReadOnlyButWholePackageCanPreflight() async throws {
        let package = tempRoot.appendingPathComponent("Fixture.app", isDirectory: true)
        let contents = package.appendingPathComponent("Contents", isDirectory: true)
        let internalFile = contents.appendingPathComponent("payload.bin")
        try FileManager.default.createDirectory(at: contents, withIntermediateDirectories: true)
        try writeFile(internalFile, byteCount: 128 * 1_024)
        let report = try await scan()
        let packageItem = try XCTUnwrap(report.items.first { $0.path == package.path })
        let internalItem = try XCTUnwrap(report.items.first { $0.path == internalFile.path })
        let validator = validator()

        XCTAssertFalse(internalItem.isDeletableCandidate)
        do {
            _ = try await validator.preflight(item: internalItem, in: report)
            XCTFail("Expected package-internal preflight to fail")
        } catch let error as DeletionValidationError {
            guard case .itemNotEligible = error else {
                return XCTFail("Unexpected error: \(error)")
            }
        }

        let request = try await validator.preflight(item: packageItem, in: report)
        XCTAssertEqual(request.summary.kind, .package)
        XCTAssertEqual(request.summary.fileCount, 1)
        XCTAssertGreaterThan(request.summary.verifiedByteSize, 0)
    }

    func testIncompleteCoverageCannotPreflight() async throws {
        let file = tempRoot.appendingPathComponent("cache.bin")
        try writeFile(file, byteCount: 128 * 1_024)
        let scanned = try await scan()
        let item = try XCTUnwrap(scanned.items.first { $0.path == file.path })
        let blockedItem = DiskItem(
            url: item.url,
            kind: item.kind,
            category: item.category,
            risk: item.risk,
            byteSize: item.byteSize,
            fileCount: item.fileCount,
            childFolderCount: item.childFolderCount,
            modifiedAt: item.modifiedAt,
            lastAccessedAt: item.lastAccessedAt,
            rootPath: item.rootPath,
            fileIdentity: item.fileIdentity,
            canonicalPath: item.canonicalPath,
            coverage: .incomplete([file.path]),
            deletionEligibility: .eligible,
            classificationRationale: item.classificationRationale
        )
        let report = ScanReport(
            roots: scanned.roots,
            items: [blockedItem],
            issues: [ScanIssue(path: file.path, message: "Permission denied")],
            totalBytes: scanned.totalBytes,
            scannedItemCount: scanned.scannedItemCount,
            scannedFileCount: scanned.scannedFileCount,
            scannedFolderCount: scanned.scannedFolderCount,
            startedAt: scanned.startedAt,
            finishedAt: scanned.finishedAt,
            scanID: scanned.scanID
        )

        do {
            _ = try await validator().preflight(item: blockedItem, in: report)
            XCTFail("Expected incomplete coverage to fail")
        } catch let error as DeletionValidationError {
            guard case .itemNotEligible = error else {
                return XCTFail("Unexpected error: \(error)")
            }
        }
    }

    func testPreflightRejectsFolderContainingConfiguredRoot() async throws {
        let parent = tempRoot.appendingPathComponent("Parent", isDirectory: true)
        let configuredChild = parent.appendingPathComponent("Configured", isDirectory: true)
        try FileManager.default.createDirectory(at: configuredChild, withIntermediateDirectories: true)
        try writeFile(configuredChild.appendingPathComponent("payload.bin"), byteCount: 64 * 1_024)

        let scanned = try await FileScanner(classifier: ItemClassifier(homeDirectory: tempRoot)).scan(
            roots: [
                ScanRoot(title: "Fixture", url: tempRoot, categoryHint: .downloads, riskHint: .medium),
                ScanRoot(title: "Configured", url: configuredChild, categoryHint: .documents, riskHint: .high)
            ],
            options: ScanOptions(minimumItemSizeBytes: 0)
        )
        let scannedParent = try XCTUnwrap(scanned.items.first { $0.path == parent.path })
        XCTAssertFalse(scannedParent.isDeletableCandidate)

        let forgedEligibleParent = DiskItem(
            url: scannedParent.url,
            kind: scannedParent.kind,
            category: scannedParent.category,
            risk: scannedParent.risk,
            byteSize: scannedParent.byteSize,
            fileCount: scannedParent.fileCount,
            childFolderCount: scannedParent.childFolderCount,
            modifiedAt: scannedParent.modifiedAt,
            lastAccessedAt: scannedParent.lastAccessedAt,
            rootPath: scannedParent.rootPath,
            fileIdentity: scannedParent.fileIdentity,
            canonicalPath: scannedParent.canonicalPath,
            coverage: .complete,
            deletionEligibility: .eligible,
            classificationRationale: scannedParent.classificationRationale
        )
        let forgedReport = ScanReport(
            roots: scanned.roots,
            items: [forgedEligibleParent],
            issues: [],
            totalBytes: scanned.totalBytes,
            scannedItemCount: scanned.scannedItemCount,
            scannedFileCount: scanned.scannedFileCount,
            scannedFolderCount: scanned.scannedFolderCount,
            startedAt: scanned.startedAt,
            finishedAt: scanned.finishedAt,
            scanID: scanned.scanID
        )

        do {
            _ = try await validator().preflight(item: forgedEligibleParent, in: forgedReport)
            XCTFail("Expected a containing folder to remain protected")
        } catch let error as DeletionValidationError {
            XCTAssertEqual(error, .configuredRoot)
        }
    }

    func testPreflightPreservesMergedHardLinkRiskAndRationale() async throws {
        let caches = tempRoot.appendingPathComponent("Library/Caches", isDirectory: true)
        let documents = tempRoot.appendingPathComponent("Documents", isDirectory: true)
        try FileManager.default.createDirectory(at: caches, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: documents, withIntermediateDirectories: true)
        let cacheLink = caches.appendingPathComponent("shared.bin")
        let documentLink = documents.appendingPathComponent("shared.bin")
        try writeFile(cacheLink, byteCount: 64 * 1_024)
        try FileManager.default.linkItem(at: cacheLink, to: documentLink)

        let report = try await FileScanner(classifier: ItemClassifier(homeDirectory: tempRoot)).scan(
            roots: [
                ScanRoot(title: "Caches", url: caches, categoryHint: .cache, riskHint: .low),
                ScanRoot(title: "Documents", url: documents, categoryHint: .documents, riskHint: .high)
            ],
            options: ScanOptions(minimumItemSizeBytes: 0)
        )
        let cacheItem = try XCTUnwrap(report.items.first { $0.path == cacheLink.path })
        XCTAssertEqual(cacheItem.category, .cache)
        XCTAssertEqual(cacheItem.risk, .high)
        XCTAssertTrue(cacheItem.isDeletableCandidate)

        let request = try await validator().preflight(item: cacheItem, in: report)
        XCTAssertEqual(request.summary.category, .cache)
        XCTAssertEqual(request.summary.risk, .high)
        XCTAssertTrue(request.summary.classificationRationale.contains("hard-linked"))
    }

    func testTrashServiceRejectsMutationAfterValidation() async throws {
        let file = tempRoot.appendingPathComponent("cache.bin")
        try writeFile(file, byteCount: 128 * 1_024)
        let report = try await scan()
        let item = try XCTUnwrap(report.items.first { $0.path == file.path })
        let request = try await validator().preflight(item: item, in: report)

        let handle = try FileHandle(forWritingTo: file)
        try handle.seekToEnd()
        try handle.write(contentsOf: Data(repeating: 0x42, count: 4_096))
        try handle.close()

        do {
            _ = try await FileManagerTrashService(homeDirectory: tempRoot).moveToTrash(request)
            XCTFail("Expected final fingerprint validation to fail")
        } catch let error as DeletionValidationError {
            XCTAssertEqual(error, .contentsChanged)
        }
        XCTAssertTrue(FileManager.default.fileExists(atPath: file.path))
    }

    func testTrashServiceRejectsFolderMutationAfterValidation() async throws {
        let folder = tempRoot.appendingPathComponent("CacheFolder", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try writeFile(folder.appendingPathComponent("first.bin"), byteCount: 64 * 1_024)
        let report = try await scan()
        let item = try XCTUnwrap(report.items.first { $0.path == folder.path })
        let request = try await validator().preflight(item: item, in: report)

        try writeFile(folder.appendingPathComponent("second.bin"), byteCount: 32 * 1_024)

        do {
            _ = try await FileManagerTrashService(homeDirectory: tempRoot).moveToTrash(request)
            XCTFail("Expected the changed folder fingerprint to fail")
        } catch let error as DeletionValidationError {
            XCTAssertEqual(error, .contentsChanged)
        }
        XCTAssertTrue(FileManager.default.fileExists(atPath: folder.path))
    }

    func testDisposableFileAndFolderCanMoveToTrash() async throws {
        let file = tempRoot.appendingPathComponent("cache.bin")
        let folder = tempRoot.appendingPathComponent("CacheFolder", isDirectory: true)
        try writeFile(file, byteCount: 64 * 1_024)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try writeFile(folder.appendingPathComponent("payload.bin"), byteCount: 64 * 1_024)
        let report = try await scan()
        let fileItem = try XCTUnwrap(report.items.first { $0.path == file.path })
        let folderItem = try XCTUnwrap(report.items.first { $0.path == folder.path })
        let validator = validator()
        let fileRequest = try await validator.preflight(item: fileItem, in: report)
        let folderRequest = try await validator.preflight(item: folderItem, in: report)
        let service = FileManagerTrashService(homeDirectory: tempRoot)

        let fileResult = try await service.moveToTrash(fileRequest)
        let folderResult = try await service.moveToTrash(folderRequest)
        extraCleanupURLs.append(contentsOf: (fileResult.items + folderResult.items).compactMap(\.trashedURL))

        XCTAssertFalse(FileManager.default.fileExists(atPath: file.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: folder.path))
    }

    private func scan() async throws -> ScanReport {
        try await FileScanner(classifier: ItemClassifier(homeDirectory: tempRoot)).scan(
            roots: [ScanRoot(title: "Caches", url: tempRoot, categoryHint: .cache, riskHint: .low)],
            options: ScanOptions(minimumItemSizeBytes: 0)
        )
    }

    private func validator() -> FileSystemDeletionValidator {
        FileSystemDeletionValidator(homeDirectory: tempRoot)
    }

    private func writeFile(_ url: URL, byteCount: Int) throws {
        try Data(repeating: 0x2A, count: byteCount).write(to: url, options: .atomic)
    }
}
