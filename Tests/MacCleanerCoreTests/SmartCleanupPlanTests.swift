import Foundation
import MacCleanerCore
import XCTest

final class SmartCleanupPlanTests: XCTestCase {
    private let referenceDate = Date(timeIntervalSince1970: 2_000_000_000)

    func testSafePlanIncludesOldLowRiskCleanupItems() {
        let cache = makeItem(path: "/tmp/cache/a", category: .cache, risk: .low, bytes: 20)
        let log = makeItem(path: "/tmp/logs/b", category: .logs, risk: .low, bytes: 30)

        let plan = SmartCleanupPlan(items: [cache, log], referenceDate: referenceDate)

        XCTAssertEqual(plan.items.map(\.path), [log.path, cache.path])
        XCTAssertEqual(plan.totalBytes, 50)
        XCTAssertFalse(plan.isEmpty)
    }

    func testSafePlanExcludesRiskyFreshAndProtectedItems() {
        let safe = makeItem(path: "/tmp/cache/safe", category: .cache, risk: .low)
        let risky = makeItem(path: "/tmp/docs/report", category: .documents, risk: .high)
        let fresh = makeItem(
            path: "/tmp/cache/fresh",
            category: .cache,
            risk: .low,
            modifiedAt: referenceDate.addingTimeInterval(-3 * 86_400)
        )
        let protected = makeItem(path: "/tmp/cache/protected", category: .cache, risk: .protected, isDeletableCandidate: false)

        let plan = SmartCleanupPlan(items: [risky, fresh, protected, safe], referenceDate: referenceDate)

        XCTAssertEqual(plan.items, [safe])
    }

    func testSafePlanCoalescesNestedItems() {
        let parent = makeItem(path: "/tmp/cache/a", category: .cache, risk: .low, bytes: 100)
        let child = makeItem(path: "/tmp/cache/a/child", category: .cache, risk: .low, bytes: 80)
        let sibling = makeItem(path: "/tmp/cache/b", category: .cache, risk: .low, bytes: 25)

        let plan = SmartCleanupPlan(items: [child, sibling, parent], referenceDate: referenceDate)

        XCTAssertEqual(plan.items.map(\.path), [parent.path, sibling.path])
        XCTAssertEqual(plan.deletionPlan.totalBytes, 125)
    }

    private func makeItem(
        path: String,
        category: DiskItemCategory,
        risk: DeletionRisk,
        bytes: Int64 = 42,
        modifiedAt: Date? = nil,
        isDeletableCandidate: Bool = true
    ) -> DiskItem {
        DiskItem(
            url: URL(fileURLWithPath: path),
            kind: .folder,
            category: category,
            risk: risk,
            byteSize: bytes,
            fileCount: 1,
            childFolderCount: 0,
            modifiedAt: modifiedAt ?? referenceDate.addingTimeInterval(-45 * 86_400),
            lastAccessedAt: nil,
            rootPath: "/tmp/cache",
            isDeletableCandidate: isDeletableCandidate
        )
    }
}
