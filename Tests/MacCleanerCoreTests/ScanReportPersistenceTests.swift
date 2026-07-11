import Foundation
import MacCleanerCore
import XCTest

final class ScanReportPersistenceTests: XCTestCase {
    private var tempDirectory: URL!

    override func setUpWithError() throws {
        tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("MacCleanerPersistenceTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        if let tempDirectory {
            try? FileManager.default.removeItem(at: tempDirectory)
        }
    }

    func testSavesAndLoadsScanReport() throws {
        let persistence = ScanReportPersistence(directoryURL: tempDirectory)
        let report = makeReport()

        try persistence.save(report)
        let loadedReport = try XCTUnwrap(persistence.load())

        XCTAssertEqual(loadedReport.scanID, report.scanID)
        XCTAssertEqual(loadedReport.items.map(\.path), report.items.map(\.path))
        XCTAssertTrue(loadedReport.items.allSatisfy { !$0.isDeletableCandidate })
        XCTAssertEqual(loadedReport.totalBytes, report.totalBytes)
        XCTAssertTrue(loadedReport.isComplete)
        XCTAssertEqual(loadedReport.freshness, .savedSnapshot)
        XCTAssertFalse(loadedReport.isActionable)
        XCTAssertTrue(FileManager.default.fileExists(atPath: persistence.fileURL.path))
    }

    func testSavesAndLoadsPartialScanReport() throws {
        let persistence = ScanReportPersistence(directoryURL: tempDirectory)
        let report = makeReport(isComplete: false)

        try persistence.save(report)
        let loadedReport = try XCTUnwrap(persistence.load())

        XCTAssertEqual(loadedReport.items.map(\.path), report.items.map(\.path))
        XCTAssertTrue(loadedReport.items.allSatisfy { !$0.isDeletableCandidate })
        XCTAssertFalse(loadedReport.isComplete)
        XCTAssertEqual(loadedReport.freshness, .savedSnapshot)
        XCTAssertFalse(loadedReport.isActionable)
    }

    func testLoadsLegacyReportWithoutCompletionFlag() throws {
        let persistence = ScanReportPersistence(directoryURL: tempDirectory)
        try persistence.save(makeReport())

        let data = try Data(contentsOf: persistence.fileURL)
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        json.removeValue(forKey: "isComplete")

        let legacyData = try JSONSerialization.data(withJSONObject: json)
        try legacyData.write(to: persistence.fileURL)

        let loadedReport = try XCTUnwrap(persistence.load())
        XCTAssertTrue(loadedReport.isComplete)
        XCTAssertFalse(loadedReport.isActionable)
    }

    func testLegacyReportDecodesReadOnlyAndBlocksLegacyItemEligibility() throws {
        let persistence = ScanReportPersistence(directoryURL: tempDirectory)
        try persistence.save(makeReport())

        let data = try Data(contentsOf: persistence.fileURL)
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        json.removeValue(forKey: "schemaVersion")
        json.removeValue(forKey: "scanID")
        json.removeValue(forKey: "freshness")
        var items = try XCTUnwrap(json["items"] as? [[String: Any]])
        items[0].removeValue(forKey: "fileIdentity")
        items[0].removeValue(forKey: "canonicalPath")
        items[0].removeValue(forKey: "coverage")
        items[0].removeValue(forKey: "deletionEligibility")
        items[0].removeValue(forKey: "classificationRationale")
        json["items"] = items

        try JSONSerialization.data(withJSONObject: json).write(to: persistence.fileURL)
        let loaded = try XCTUnwrap(persistence.load())

        XCTAssertEqual(loaded.schemaVersion, 1)
        XCTAssertEqual(loaded.freshness, .savedSnapshot)
        XCTAssertFalse(loaded.isActionable)
        XCTAssertFalse(try XCTUnwrap(loaded.items.first).isDeletableCandidate)
        XCTAssertFalse(try XCTUnwrap(loaded.items.first).coverage.isComplete)
    }

    func testDeleteRemovesSavedReport() throws {
        let persistence = ScanReportPersistence(directoryURL: tempDirectory)
        try persistence.save(makeReport())

        try persistence.delete()

        XCTAssertNil(try persistence.load())
    }

    func testDefaultStoreUsesEnvironmentOverride() {
        let persistence = ScanReportPersistence.defaultStore(environment: [
            "MAC_CLEANER_DATA_DIR": tempDirectory.path
        ])

        XCTAssertEqual(persistence.fileURL, tempDirectory.appendingPathComponent("last-scan.json"))
    }

    func testSerializedStoreRejectsLateOlderRevision() async throws {
        let persistence = ScanReportPersistence(directoryURL: tempDirectory)
        let store = SerializedScanReportStore(persistence: persistence)
        let newer = makeReport(totalBytes: 84_000_000)
        let older = makeReport(totalBytes: 42_000_000)

        let savedNewer = try await store.save(newer, revision: 2)
        let savedOlder = try await store.save(older, revision: 1)
        XCTAssertTrue(savedNewer)
        XCTAssertFalse(savedOlder)
        let loadedReport = try await store.load()
        let loaded = try XCTUnwrap(loadedReport)

        XCTAssertEqual(loaded.totalBytes, newer.totalBytes)
    }

    private func makeReport(isComplete: Bool = true, totalBytes: Int64 = 42_000_000) -> ScanReport {
        let root = tempDirectory.appendingPathComponent("Library/Caches", isDirectory: true)
        let item = DiskItem(
            url: root.appendingPathComponent("example.cache", isDirectory: false),
            kind: .file,
            category: .cache,
            risk: .low,
            byteSize: totalBytes,
            fileCount: 1,
            childFolderCount: 0,
            modifiedAt: Date(timeIntervalSince1970: 1_800_000_000),
            lastAccessedAt: Date(timeIntervalSince1970: 1_800_000_100),
            rootPath: root.path,
            isDeletableCandidate: true
        )

        return ScanReport(
            roots: [ScanRoot(title: "Caches", url: root, categoryHint: .cache, riskHint: .low)],
            items: [item],
            issues: [ScanIssue(path: root.appendingPathComponent("private").path, message: "Permission denied")],
            totalBytes: item.byteSize,
            scannedItemCount: 3,
            scannedFileCount: 1,
            scannedFolderCount: 2,
            startedAt: Date(timeIntervalSince1970: 1_800_000_000),
            finishedAt: Date(timeIntervalSince1970: 1_800_000_200),
            isComplete: isComplete
        )
    }
}
