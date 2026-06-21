import Foundation

public struct TrashedItem: Hashable, Sendable {
    public let originalURL: URL
    public let trashedURL: URL?

    public init(originalURL: URL, trashedURL: URL?) {
        self.originalURL = originalURL
        self.trashedURL = trashedURL
    }
}

public struct TrashOperationResult: Equatable, Sendable {
    public let items: [TrashedItem]

    public init(items: [TrashedItem]) {
        self.items = items
    }
}

public protocol TrashManaging: Sendable {
    func moveToTrash(_ urls: [URL]) async throws -> TrashOperationResult
}

public struct FileManagerTrashService: TrashManaging {
    public init() {}

    public func moveToTrash(_ urls: [URL]) async throws -> TrashOperationResult {
        try await Task.detached(priority: .userInitiated) {
            let fileManager = FileManager.default
            var trashedItems: [TrashedItem] = []

            for url in urls {
                var resultingURL: NSURL?
                try fileManager.trashItem(at: url, resultingItemURL: &resultingURL)
                trashedItems.append(TrashedItem(originalURL: url, trashedURL: resultingURL as URL?))
            }

            return TrashOperationResult(items: trashedItems)
        }.value
    }
}
