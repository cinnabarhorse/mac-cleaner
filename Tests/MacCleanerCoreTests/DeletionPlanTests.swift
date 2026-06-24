import Foundation
import MacCleanerCore
import XCTest

final class DeletionPlanTests: XCTestCase {
    func testPlanIncludesMultipleDeletableItems() {
        let first = makeItem(path: "/tmp/cache/a")
        let second = makeItem(path: "/tmp/cache/b")

        let plan = DeletionPlan(items: [first, second])

        XCTAssertEqual(plan.items, [first, second])
        XCTAssertEqual(plan.totalBytes, 84_000_000)
        XCTAssertEqual(plan.highestRisk, .low)
    }

    func testPlanFiltersProtectedItems() {
        let movable = makeItem(path: "/tmp/cache/a")
        let protected = makeItem(path: "/tmp/cache/protected", risk: .protected, isDeletableCandidate: false)

        let plan = DeletionPlan(items: [protected, movable])

        XCTAssertEqual(plan.items, [movable])
    }

    func testPlanCoalescesNestedItemsUnderSelectedParent() {
        let parent = makeItem(path: "/tmp/cache/a", byteSize: 100)
        let child = makeItem(path: "/tmp/cache/a/child", byteSize: 50)
        let sibling = makeItem(path: "/tmp/cache/b", byteSize: 25)

        let plan = DeletionPlan(items: [child, sibling, parent])

        XCTAssertEqual(plan.items, [parent, sibling])
        XCTAssertEqual(plan.totalBytes, 125)
    }

    private func makeItem(
        path: String,
        risk: DeletionRisk = .low,
        byteSize: Int64 = 42_000_000,
        isDeletableCandidate: Bool = true
    ) -> DiskItem {
        DiskItem(
            url: URL(fileURLWithPath: path),
            kind: .folder,
            category: .cache,
            risk: risk,
            byteSize: byteSize,
            fileCount: 1,
            childFolderCount: 0,
            modifiedAt: nil,
            lastAccessedAt: nil,
            rootPath: "/tmp/cache",
            isDeletableCandidate: isDeletableCandidate
        )
    }
}
