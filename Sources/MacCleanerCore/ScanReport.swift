import Foundation

public struct ScanOptions: Equatable, Codable, Sendable {
    public var includeHiddenFiles: Bool
    public var includePackageContents: Bool
    public var includeSymlinkTargets: Bool
    public var minimumItemSizeBytes: Int64
    public var maxReturnedItems: Int
    public var snapshotItemInterval: Int

    public init(
        includeHiddenFiles: Bool = false,
        includePackageContents: Bool = true,
        includeSymlinkTargets: Bool = false,
        minimumItemSizeBytes: Int64 = 10 * 1_024 * 1_024,
        maxReturnedItems: Int = 5_000,
        snapshotItemInterval: Int = 5_000
    ) {
        self.includeHiddenFiles = includeHiddenFiles
        self.includePackageContents = includePackageContents
        self.includeSymlinkTargets = includeSymlinkTargets
        self.minimumItemSizeBytes = minimumItemSizeBytes
        self.maxReturnedItems = max(1, maxReturnedItems)
        self.snapshotItemInterval = max(1, snapshotItemInterval)
    }
}

public struct ScanProgress: Equatable, Sendable {
    public let currentPath: String
    public let scannedItemCount: Int
    public let scannedByteCount: Int64
    public let partialReport: ScanReport?

    public init(
        currentPath: String,
        scannedItemCount: Int,
        scannedByteCount: Int64,
        partialReport: ScanReport? = nil
    ) {
        self.currentPath = currentPath
        self.scannedItemCount = scannedItemCount
        self.scannedByteCount = scannedByteCount
        self.partialReport = partialReport
    }
}

public struct ScanIssue: Identifiable, Equatable, Codable, Sendable {
    public var id: String { path + message }

    public let path: String
    public let message: String

    public var isLikelyPermissionIssue: Bool {
        let normalizedMessage = message.lowercased()
        return normalizedMessage.contains("permission")
            || normalizedMessage.contains("operation not permitted")
            || normalizedMessage.contains("not authorized")
            || normalizedMessage.contains("privacy")
    }

    public init(path: String, message: String) {
        self.path = path
        self.message = message
    }
}

public struct ScanReport: Equatable, Codable, Sendable {
    public let roots: [ScanRoot]
    public let items: [DiskItem]
    public let issues: [ScanIssue]
    public let totalBytes: Int64
    public let scannedItemCount: Int
    public let scannedFileCount: Int
    public let scannedFolderCount: Int
    public let startedAt: Date
    public let finishedAt: Date
    public let isComplete: Bool

    public var duration: TimeInterval {
        finishedAt.timeIntervalSince(startedAt)
    }

    private enum CodingKeys: String, CodingKey {
        case roots
        case items
        case issues
        case totalBytes
        case scannedItemCount
        case scannedFileCount
        case scannedFolderCount
        case startedAt
        case finishedAt
        case isComplete
    }

    public init(
        roots: [ScanRoot],
        items: [DiskItem],
        issues: [ScanIssue],
        totalBytes: Int64,
        scannedItemCount: Int,
        scannedFileCount: Int,
        scannedFolderCount: Int,
        startedAt: Date,
        finishedAt: Date,
        isComplete: Bool = true
    ) {
        self.roots = roots
        self.items = items
        self.issues = issues
        self.totalBytes = totalBytes
        self.scannedItemCount = scannedItemCount
        self.scannedFileCount = scannedFileCount
        self.scannedFolderCount = scannedFolderCount
        self.startedAt = startedAt
        self.finishedAt = finishedAt
        self.isComplete = isComplete
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        roots = try container.decode([ScanRoot].self, forKey: .roots)
        items = try container.decode([DiskItem].self, forKey: .items)
        issues = try container.decode([ScanIssue].self, forKey: .issues)
        totalBytes = try container.decode(Int64.self, forKey: .totalBytes)
        scannedItemCount = try container.decode(Int.self, forKey: .scannedItemCount)
        scannedFileCount = try container.decode(Int.self, forKey: .scannedFileCount)
        scannedFolderCount = try container.decode(Int.self, forKey: .scannedFolderCount)
        startedAt = try container.decode(Date.self, forKey: .startedAt)
        finishedAt = try container.decode(Date.self, forKey: .finishedAt)
        isComplete = try container.decodeIfPresent(Bool.self, forKey: .isComplete) ?? true
    }

    public func removingItems(withIDs ids: Set<DiskItem.ID>) -> ScanReport {
        ScanReport(
            roots: roots,
            items: items.filter { !ids.contains($0.id) },
            issues: issues,
            totalBytes: totalBytes,
            scannedItemCount: scannedItemCount,
            scannedFileCount: scannedFileCount,
            scannedFolderCount: scannedFolderCount,
            startedAt: startedAt,
            finishedAt: finishedAt,
            isComplete: isComplete
        )
    }
}
