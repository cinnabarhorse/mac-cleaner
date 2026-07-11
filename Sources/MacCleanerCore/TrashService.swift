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
    func moveToTrash(_ request: ValidatedTrashRequest) async throws -> TrashOperationResult
}

public actor FileManagerTrashService: TrashManaging {
    private let inspector: DeletionInspector

    public init(homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser) {
        inspector = DeletionInspector(homeDirectory: homeDirectory)
    }

    public func moveToTrash(_ request: ValidatedTrashRequest) async throws -> TrashOperationResult {
        let current = try inspector.inspect(
            url: request.summary.url,
            scanRootPath: request.scanRootPath,
            configuredRoots: request.configuredRoots,
            scannedByteSize: request.summary.scannedByteSize,
            scannedCategory: request.summary.category,
            minimumRisk: request.summary.risk,
            scannedRationale: request.summary.classificationRationale
        )
        guard current.summary == request.summary else {
            throw DeletionValidationError.contentsChanged
        }
        guard FileSystemSafety.identity(at: request.summary.url) == request.summary.identity else {
            throw DeletionValidationError.contentsChanged
        }

        var resultingURL: NSURL?
        try FileManager.default.trashItem(at: request.summary.url, resultingItemURL: &resultingURL)

        return TrashOperationResult(items: [
            TrashedItem(originalURL: request.summary.url, trashedURL: resultingURL as URL?)
        ])
    }
}
