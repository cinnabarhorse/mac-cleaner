import Foundation

public struct ScanOptions: Equatable, Codable, Sendable {
    public var includeHiddenFiles: Bool
    public var includePackageContents: Bool
    public var includeSymlinkTargets: Bool
    public var minimumItemSizeBytes: Int64
    public var maxReturnedItems: Int
    public var snapshotItemInterval: Int
    public var snapshotInterval: TimeInterval

    public var showHiddenFiles: Bool {
        get { includeHiddenFiles }
        set { includeHiddenFiles = newValue }
    }

    public var showPackageContents: Bool {
        get { includePackageContents }
        set { includePackageContents = newValue }
    }

    public var showSymbolicLinks: Bool {
        get { includeSymlinkTargets }
        set { includeSymlinkTargets = newValue }
    }

    public init(
        includeHiddenFiles: Bool = false,
        includePackageContents: Bool = true,
        includeSymlinkTargets: Bool = false,
        minimumItemSizeBytes: Int64 = 10 * 1_024 * 1_024,
        maxReturnedItems: Int = 5_000,
        snapshotItemInterval: Int = 5_000,
        snapshotInterval: TimeInterval = 1
    ) {
        self.includeHiddenFiles = includeHiddenFiles
        self.includePackageContents = includePackageContents
        self.includeSymlinkTargets = includeSymlinkTargets
        self.minimumItemSizeBytes = minimumItemSizeBytes
        self.maxReturnedItems = max(1, maxReturnedItems)
        self.snapshotItemInterval = max(1, snapshotItemInterval)
        self.snapshotInterval = max(0.1, snapshotInterval)
    }

    private enum CodingKeys: String, CodingKey {
        case includeHiddenFiles
        case includePackageContents
        case includeSymlinkTargets
        case minimumItemSizeBytes
        case maxReturnedItems
        case snapshotItemInterval
        case snapshotInterval
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            includeHiddenFiles: try container.decodeIfPresent(Bool.self, forKey: .includeHiddenFiles) ?? false,
            includePackageContents: try container.decodeIfPresent(Bool.self, forKey: .includePackageContents) ?? true,
            includeSymlinkTargets: try container.decodeIfPresent(Bool.self, forKey: .includeSymlinkTargets) ?? false,
            minimumItemSizeBytes: try container.decodeIfPresent(Int64.self, forKey: .minimumItemSizeBytes) ?? 10 * 1_024 * 1_024,
            maxReturnedItems: try container.decodeIfPresent(Int.self, forKey: .maxReturnedItems) ?? 5_000,
            snapshotItemInterval: try container.decodeIfPresent(Int.self, forKey: .snapshotItemInterval) ?? 5_000,
            snapshotInterval: try container.decodeIfPresent(TimeInterval.self, forKey: .snapshotInterval) ?? 1
        )
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

    public init(path: String, message: String) {
        self.path = path
        self.message = message
    }
}

public enum ScanReportFreshness: String, Equatable, Codable, Sendable {
    case current
    case savedSnapshot
    case stale
}

public struct ScanReport: Equatable, Codable, Sendable {
    public static let currentSchemaVersion = 2

    public let schemaVersion: Int
    public let scanID: UUID
    public let freshness: ScanReportFreshness
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

    public var isActionable: Bool {
        isComplete && freshness == .current && schemaVersion == Self.currentSchemaVersion
    }

    public var duration: TimeInterval {
        finishedAt.timeIntervalSince(startedAt)
    }

    private enum CodingKeys: String, CodingKey {
        case roots
        case schemaVersion
        case scanID
        case freshness
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
        isComplete: Bool = true,
        schemaVersion: Int = ScanReport.currentSchemaVersion,
        scanID: UUID = UUID(),
        freshness: ScanReportFreshness = .current
    ) {
        self.schemaVersion = schemaVersion
        self.scanID = scanID
        self.freshness = freshness
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

        schemaVersion = try container.decodeIfPresent(Int.self, forKey: .schemaVersion) ?? 1
        scanID = try container.decodeIfPresent(UUID.self, forKey: .scanID) ?? UUID()
        // Anything decoded from persistence is a snapshot and must be refreshed.
        freshness = .savedSnapshot
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
        let paths = items.filter { ids.contains($0.id) }.map(\.path)
        return paths.reduce(self) { report, path in
            report.removingSubtree(at: URL(fileURLWithPath: path))
        }
    }

    public func removingSubtree(at url: URL) -> ScanReport {
        let removedPath = url.standardizedFileURL.path

        return ScanReport(
            roots: roots,
            items: items.filter { item in
                item.path != removedPath && !item.path.hasPrefix(removedPath + "/")
            },
            issues: issues,
            // Aggregates remain explicitly stale until the mandatory refresh.
            totalBytes: totalBytes,
            scannedItemCount: scannedItemCount,
            scannedFileCount: scannedFileCount,
            scannedFolderCount: scannedFolderCount,
            startedAt: startedAt,
            finishedAt: finishedAt,
            isComplete: isComplete,
            schemaVersion: schemaVersion,
            scanID: scanID,
            freshness: .stale
        )
    }

    public func markingStale() -> ScanReport {
        ScanReport(
            roots: roots,
            items: items,
            issues: issues,
            totalBytes: totalBytes,
            scannedItemCount: scannedItemCount,
            scannedFileCount: scannedFileCount,
            scannedFolderCount: scannedFolderCount,
            startedAt: startedAt,
            finishedAt: finishedAt,
            isComplete: isComplete,
            schemaVersion: schemaVersion,
            scanID: scanID,
            freshness: .stale
        )
    }
}
