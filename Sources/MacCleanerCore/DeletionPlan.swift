import Foundation

public struct DeletionPlan: Identifiable, Equatable, Sendable {
    public let id: String
    public let items: [DiskItem]

    public init(items: [DiskItem]) {
        self.items = Self.coalescedDeletableItems(from: items)
        id = self.items.map(\.id).joined(separator: "\n")
    }

    public var isEmpty: Bool {
        items.isEmpty
    }

    public var totalBytes: Int64 {
        items.reduce(0) { $0 + $1.byteSize }
    }

    public var highestRisk: DeletionRisk? {
        items.map(\.risk).max()
    }

    private static func coalescedDeletableItems(from items: [DiskItem]) -> [DiskItem] {
        let deletableItems = items
            .filter(\.isDeletableCandidate)
            .sorted { lhs, rhs in
                if lhs.path.count == rhs.path.count {
                    return lhs.path < rhs.path
                }

                return lhs.path.count < rhs.path.count
            }

        var selectedParents: [String] = []
        var coalescedItems: [DiskItem] = []

        for item in deletableItems {
            guard !selectedParents.contains(where: { item.path.hasPrefix($0 + "/") }) else {
                continue
            }

            selectedParents.append(item.path)
            coalescedItems.append(item)
        }

        return coalescedItems
    }
}
