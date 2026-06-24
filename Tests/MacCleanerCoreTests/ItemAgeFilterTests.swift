import Foundation
import MacCleanerCore
import XCTest

final class ItemAgeFilterTests: XCTestCase {
    private let referenceDate = Date(timeIntervalSince1970: 2_000_000_000)

    func testAnyFilterIncludesItemsWithoutDates() {
        XCTAssertTrue(ItemAgeFilter.any.includes(makeItem(modifiedAt: nil), referenceDate: referenceDate))
    }

    func testAgeFilterRequiresLastActivityBeforeCutoff() {
        let oldItem = makeItem(modifiedAt: referenceDate.addingTimeInterval(-91 * 86_400))
        let freshItem = makeItem(modifiedAt: referenceDate.addingTimeInterval(-12 * 86_400))

        XCTAssertTrue(ItemAgeFilter.days90.includes(oldItem, referenceDate: referenceDate))
        XCTAssertFalse(ItemAgeFilter.days90.includes(freshItem, referenceDate: referenceDate))
    }

    func testLastActivityUsesNewestKnownDate() {
        let item = makeItem(
            modifiedAt: referenceDate.addingTimeInterval(-200 * 86_400),
            lastAccessedAt: referenceDate.addingTimeInterval(-3 * 86_400)
        )

        XCTAssertFalse(ItemAgeFilter.days30.includes(item, referenceDate: referenceDate))
        XCTAssertEqual(item.ageInDays(referenceDate: referenceDate), 3)
    }

    private func makeItem(
        modifiedAt: Date?,
        lastAccessedAt: Date? = nil
    ) -> DiskItem {
        DiskItem(
            url: URL(fileURLWithPath: "/tmp/cache/item"),
            kind: .file,
            category: .cache,
            risk: .low,
            byteSize: 1_000,
            fileCount: 1,
            childFolderCount: 0,
            modifiedAt: modifiedAt,
            lastAccessedAt: lastAccessedAt,
            rootPath: "/tmp/cache",
            isDeletableCandidate: true
        )
    }
}
