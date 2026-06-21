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

        XCTAssertEqual(loadedReport, report)
        XCTAssertTrue(loadedReport.isComplete)
        XCTAssertTrue(FileManager.default.fileExists(atPath: persistence.fileURL.path))
    }

    func testSavesAndLoadsPartialScanReport() throws {
        let persistence = ScanReportPersistence(directoryURL: tempDirectory)
        let report = makeReport(isComplete: false)

        try persistence.save(report)
        let loadedReport = try XCTUnwrap(persistence.load())

        XCTAssertEqual(loadedReport, report)
        XCTAssertFalse(loadedReport.isComplete)
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

    private func makeReport(isComplete: Bool = true) -> ScanReport {
        let root = tempDirectory.appendingPathComponent("Library/Caches", isDirectory: true)
        let item = DiskItem(
            url: root.appendingPathComponent("example.cache", isDirectory: false),
            kind: .file,
            category: .cache,
            risk: .low,
            byteSize: 42_000_000,
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
