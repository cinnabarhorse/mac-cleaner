import Foundation

public struct SmartCleanupPlan: Identifiable, Equatable, Sendable {
    public let id: String
    public let items: [DiskItem]
    public let minimumAgeDays: Int

    public init(
        items: [DiskItem],
        referenceDate: Date = Date(),
        minimumAgeDays: Int = 30,
        maxItems: Int = 25
    ) {
        self.minimumAgeDays = minimumAgeDays

        let cutoffDate = referenceDate.addingTimeInterval(-Double(minimumAgeDays) * 86_400)
        let candidates = items
            .filter { Self.isSafeCandidate($0, cutoffDate: cutoffDate) }
            .sorted(by: Self.sortByLargestFirst)
            .prefix(max(1, maxItems))

        self.items = DeletionPlan(items: Array(candidates))
            .items
            .sorted(by: Self.sortByLargestFirst)
        id = self.items.map(\.id).joined(separator: "\n")
    }

    public var isEmpty: Bool {
        items.isEmpty
    }

    public var deletionPlan: DeletionPlan {
        DeletionPlan(items: items)
    }

    public var totalBytes: Int64 {
        items.reduce(0) { $0 + $1.byteSize }
    }

    public var oldestActivityDate: Date? {
        items.compactMap(\.lastActivityDate).min()
    }

    private static func isSafeCandidate(_ item: DiskItem, cutoffDate: Date) -> Bool {
        guard item.isDeletableCandidate, item.risk == .low else {
            return false
        }

        guard [.cache, .logs, .trash].contains(item.category) else {
            return false
        }

        guard let lastActivityDate = item.lastActivityDate else {
            return false
        }

        return lastActivityDate <= cutoffDate
    }

    private static func sortByLargestFirst(_ lhs: DiskItem, _ rhs: DiskItem) -> Bool {
        if lhs.byteSize == rhs.byteSize {
            return lhs.path.localizedStandardCompare(rhs.path) == .orderedAscending
        }

        return lhs.byteSize > rhs.byteSize
    }
}
