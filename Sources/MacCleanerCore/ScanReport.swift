import Foundation

public struct ScanOptions: Equatable, Sendable {
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

public struct ScanIssue: Identifiable, Equatable, Sendable {
    public var id: String { path + message }

    public let path: String
    public let message: String

    public init(path: String, message: String) {
        self.path = path
        self.message = message
    }
}

public struct ScanReport: Equatable, Sendable {
    public let roots: [ScanRoot]
    public let items: [DiskItem]
    public let issues: [ScanIssue]
    public let totalBytes: Int64
    public let scannedItemCount: Int
    public let scannedFileCount: Int
    public let scannedFolderCount: Int
    public let startedAt: Date
    public let finishedAt: Date

    public var duration: TimeInterval {
        finishedAt.timeIntervalSince(startedAt)
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
        finishedAt: Date
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
            finishedAt: finishedAt
        )
    }
}
