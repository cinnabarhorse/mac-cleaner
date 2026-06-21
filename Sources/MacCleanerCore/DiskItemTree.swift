import Foundation

public struct DiskItemTreeNode: Identifiable, Hashable, Sendable {
    public var id: DiskItem.ID { item.id }

    public let item: DiskItem
    public let children: [DiskItemTreeNode]

    public var hasChildren: Bool {
        !children.isEmpty
    }

    public init(item: DiskItem, children: [DiskItemTreeNode] = []) {
        self.item = item
        self.children = children
    }
}

public enum DiskItemTreeBuilder {
    public static func build(from items: [DiskItem]) -> [DiskItemTreeNode] {
        let itemsByPath = Dictionary(uniqueKeysWithValues: items.map { ($0.path, $0) })
        let paths = Set(itemsByPath.keys)
        var childPathsByParent: [String: [String]] = [:]
        var rootPaths: [String] = []

        for item in items {
            if let parentPath = nearestScannedAncestorPath(for: item.path, in: paths) {
                childPathsByParent[parentPath, default: []].append(item.path)
            } else {
                rootPaths.append(item.path)
            }
        }

        func makeNode(path: String, visited: Set<String>) -> DiskItemTreeNode? {
            guard !visited.contains(path), let item = itemsByPath[path] else {
                return nil
            }

            let nextVisited = visited.union([path])
            let children = (childPathsByParent[path] ?? [])
                .compactMap { makeNode(path: $0, visited: nextVisited) }
                .sorted(by: sortNodes)

            return DiskItemTreeNode(item: item, children: children)
        }

        return rootPaths
            .compactMap { makeNode(path: $0, visited: []) }
            .sorted(by: sortNodes)
    }

    private static func nearestScannedAncestorPath(for path: String, in paths: Set<String>) -> String? {
        var parentPath = URL(fileURLWithPath: path)
            .deletingLastPathComponent()
            .standardizedFileURL
            .path

        while parentPath != path {
            if paths.contains(parentPath) {
                return parentPath
            }

            let nextParentPath = URL(fileURLWithPath: parentPath)
                .deletingLastPathComponent()
                .standardizedFileURL
                .path

            guard nextParentPath != parentPath else {
                return nil
            }

            parentPath = nextParentPath
        }

        return nil
    }

    private static func sortNodes(_ lhs: DiskItemTreeNode, _ rhs: DiskItemTreeNode) -> Bool {
        if lhs.item.byteSize == rhs.item.byteSize {
            return lhs.item.path.localizedStandardCompare(rhs.item.path) == .orderedAscending
        }

        return lhs.item.byteSize > rhs.item.byteSize
    }
}
