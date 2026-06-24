import Foundation
import MacCleanerCore
import XCTest

final class ScanReportExporterTests: XCTestCase {
    func testMarkdownExportIncludesSummaryItemsAndIssues() {
        let report = makeReport()

        let markdown = ScanReportExporter.export(report, as: .markdown)

        XCTAssertTrue(markdown.contains("# Mac Cleaner Scan Report"))
        XCTAssertTrue(markdown.contains("| Low | Cache | File | /tmp/cache/app.cache |"))
        XCTAssertTrue(markdown.contains("## Scan Issues"))
        XCTAssertTrue(markdown.contains("Permission denied"))
    }

    func testCSVExportEscapesCommasAndQuotes() {
        let item = makeItem(path: "/tmp/cache/app, \"quoted\".cache")
        let report = makeReport(items: [item], issues: [])

        let csv = ScanReportExporter.export(report, as: .csv)

        XCTAssertTrue(csv.hasPrefix("path,name,bytes,size,category,risk,kind"))
        XCTAssertTrue(csv.contains("\"/tmp/cache/app, \"\"quoted\"\".cache\""))
    }

    private func makeReport(
        items: [DiskItem]? = nil,
        issues: [ScanIssue] = [ScanIssue(path: "/tmp/private", message: "Permission denied")]
    ) -> ScanReport {
        let startedAt = Date(timeIntervalSince1970: 2_000_000_000)
        let reportItems = items ?? [makeItem(path: "/tmp/cache/app.cache")]
        return ScanReport(
            roots: [ScanRoot(title: "Cache", url: URL(fileURLWithPath: "/tmp/cache"), categoryHint: .cache, riskHint: .low)],
            items: reportItems,
            issues: issues,
            totalBytes: reportItems.reduce(0) { $0 + $1.byteSize },
            scannedItemCount: 10,
            scannedFileCount: 8,
            scannedFolderCount: 2,
            startedAt: startedAt,
            finishedAt: startedAt.addingTimeInterval(3),
            isComplete: true
        )
    }

    private func makeItem(path: String) -> DiskItem {
        DiskItem(
            url: URL(fileURLWithPath: path),
            kind: .file,
            category: .cache,
            risk: .low,
            byteSize: 42_000_000,
            fileCount: 1,
            childFolderCount: 0,
            modifiedAt: Date(timeIntervalSince1970: 1_999_000_000),
            lastAccessedAt: nil,
            rootPath: "/tmp/cache",
            isDeletableCandidate: true
        )
    }
}
