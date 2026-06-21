import Foundation
import MacCleanerCore
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

    func testSymlinkIsSkippedByDefault() async throws {
        let target = tempRoot.appendingPathComponent("target.bin")
        let link = tempRoot.appendingPathComponent("target-link.bin")
        try writeFile(target, byteCount: 128 * 1_024)
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: target)

        let report = try await makeScanner().scan(
            roots: [ScanRoot(title: "Fixture", url: tempRoot, categoryHint: .downloads, riskHint: .medium)],
            options: ScanOptions(minimumItemSizeBytes: 0)
        )

        XCTAssertNil(report.items.first { $0.path == link.path })
        XCTAssertFalse(report.items.contains { $0.kind == .symbolicLink })
    }

    func testKnownAppProfileBuildsExpectedRoots() {
        let roots = KnownAppProfile.codex.roots(homeDirectory: tempRoot)
        let paths = Set(roots.map(\.url.path))

        XCTAssertTrue(paths.contains(tempRoot.appendingPathComponent(".codex", isDirectory: true).path))
        XCTAssertTrue(paths.contains(tempRoot.appendingPathComponent("Library/Application Support/Codex", isDirectory: true).path))
        XCTAssertTrue(roots.allSatisfy { $0.categoryHint == .codex })
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
    }

    private func makeScanner() -> FileScanner {
        FileScanner(classifier: ItemClassifier(homeDirectory: tempRoot))
    }

    private func writeFile(_ url: URL, byteCount: Int) throws {
        let data = Data(repeating: 0x2A, count: byteCount)
        try data.write(to: url, options: .atomic)
    }
}
