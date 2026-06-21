import Foundation

public enum DiskItemKind: String, CaseIterable, Codable, Sendable {
    case file
    case folder
    case package
    case symbolicLink
    case inaccessible

    public var displayName: String {
        switch self {
        case .file: "File"
        case .folder: "Folder"
        case .package: "Package"
        case .symbolicLink: "Symlink"
        case .inaccessible: "Inaccessible"
        }
    }

    public var systemImage: String {
        switch self {
        case .file: "doc"
        case .folder: "folder"
        case .package: "shippingbox"
        case .symbolicLink: "link"
        case .inaccessible: "lock"
        }
    }
}

public enum DiskItemCategory: String, CaseIterable, Identifiable, Codable, Sendable {
    case cache
    case logs
    case developerData
    case applicationSupport
    case media
    case documents
    case backups
    case codex
    case capCut
    case finalCut
    case downloads
    case trash
    case system
    case other

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .cache: "Cache"
        case .logs: "Logs"
        case .developerData: "Developer Data"
        case .applicationSupport: "Application Support"
        case .media: "Media"
        case .documents: "Documents"
        case .backups: "Backups"
        case .codex: "Codex"
        case .capCut: "CapCut"
        case .finalCut: "Final Cut Pro"
        case .downloads: "Downloads"
        case .trash: "Trash"
        case .system: "System"
        case .other: "Other"
        }
    }

    public var systemImage: String {
        switch self {
        case .cache: "externaldrive.badge.timemachine"
        case .logs: "doc.text.magnifyingglass"
        case .developerData: "hammer"
        case .applicationSupport: "app.badge"
        case .media: "film.stack"
        case .documents: "doc.richtext"
        case .backups: "clock.arrow.circlepath"
        case .codex: "terminal"
        case .capCut: "scissors"
        case .finalCut: "video"
        case .downloads: "arrow.down.circle"
        case .trash: "trash"
        case .system: "gearshape.2"
        case .other: "questionmark.folder"
        }
    }
}

public enum DeletionRisk: Int, CaseIterable, Comparable, Identifiable, Codable, Sendable {
    case low = 0
    case medium = 1
    case high = 2
    case protected = 3

    public var id: Int { rawValue }

    public static func < (lhs: DeletionRisk, rhs: DeletionRisk) -> Bool {
        lhs.rawValue < rhs.rawValue
    }

    public var displayName: String {
        switch self {
        case .low: "Low"
        case .medium: "Medium"
        case .high: "High"
        case .protected: "Protected"
        }
    }

    public var systemImage: String {
        switch self {
        case .low: "checkmark.seal"
        case .medium: "exclamationmark.circle"
        case .high: "exclamationmark.triangle"
        case .protected: "lock.shield"
        }
    }
}

public struct DiskItem: Identifiable, Hashable, Codable, Sendable {
    public var id: String { path }

    public let url: URL
    public let path: String
    public let name: String
    public let kind: DiskItemKind
    public let category: DiskItemCategory
    public let risk: DeletionRisk
    public let byteSize: Int64
    public let fileCount: Int
    public let childFolderCount: Int
    public let modifiedAt: Date?
    public let lastAccessedAt: Date?
    public let rootPath: String
    public let isDeletableCandidate: Bool

    public init(
        url: URL,
        kind: DiskItemKind,
        category: DiskItemCategory,
        risk: DeletionRisk,
        byteSize: Int64,
        fileCount: Int,
        childFolderCount: Int,
        modifiedAt: Date?,
        lastAccessedAt: Date?,
        rootPath: String,
        isDeletableCandidate: Bool
    ) {
        let standardizedURL = url.standardizedFileURL
        self.url = standardizedURL
        path = standardizedURL.path
        name = standardizedURL.lastPathComponent.isEmpty ? standardizedURL.path : standardizedURL.lastPathComponent
        self.kind = kind
        self.category = category
        self.risk = risk
        self.byteSize = byteSize
        self.fileCount = fileCount
        self.childFolderCount = childFolderCount
        self.modifiedAt = modifiedAt
        self.lastAccessedAt = lastAccessedAt
        self.rootPath = URL(fileURLWithPath: rootPath).standardizedFileURL.path
        self.isDeletableCandidate = isDeletableCandidate
    }
}
