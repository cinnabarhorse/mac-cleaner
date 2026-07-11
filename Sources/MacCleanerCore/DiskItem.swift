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
    case libraries
    case projectData
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
        case .libraries: "Libraries"
        case .projectData: "Project Data"
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
        case .libraries: "books.vertical"
        case .projectData: "folder.badge.gearshape"
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

public struct FileIdentity: Hashable, Codable, Sendable {
    public let deviceID: UInt64
    public let fileID: UInt64

    public init(deviceID: UInt64, fileID: UInt64) {
        self.deviceID = deviceID
        self.fileID = fileID
    }
}

public struct ScanCoverage: Hashable, Codable, Sendable {
    public let isComplete: Bool
    public let issuePaths: [String]

    public static let complete = ScanCoverage(isComplete: true)

    public static func incomplete(_ issuePaths: [String]) -> ScanCoverage {
        ScanCoverage(isComplete: false, issuePaths: issuePaths)
    }

    public init(isComplete: Bool, issuePaths: [String] = []) {
        self.isComplete = isComplete
        self.issuePaths = Array(Set(issuePaths)).sorted()
    }
}

public struct DeletionEligibility: Hashable, Codable, Sendable {
    public let isEligible: Bool
    public let reason: String?

    public static let eligible = DeletionEligibility(isEligible: true)

    public static func blocked(_ reason: String) -> DeletionEligibility {
        DeletionEligibility(isEligible: false, reason: reason)
    }

    public init(isEligible: Bool, reason: String? = nil) {
        self.isEligible = isEligible
        self.reason = isEligible ? nil : (reason ?? "This item cannot be moved to Trash.")
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
    public let fileIdentity: FileIdentity?
    public let canonicalPath: String
    public let coverage: ScanCoverage
    public let deletionEligibility: DeletionEligibility
    public let classificationRationale: String
    public let applicationProfile: String?
    public let packageRootPath: String?
    public let isHidden: Bool

    public var isDeletableCandidate: Bool {
        deletionEligibility.isEligible
    }

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
        self.init(
            url: url,
            kind: kind,
            category: category,
            risk: risk,
            byteSize: byteSize,
            fileCount: fileCount,
            childFolderCount: childFolderCount,
            modifiedAt: modifiedAt,
            lastAccessedAt: lastAccessedAt,
            rootPath: rootPath,
            fileIdentity: nil,
            canonicalPath: nil,
            coverage: .complete,
            deletionEligibility: isDeletableCandidate ? .eligible : .blocked("This item is protected."),
            classificationRationale: "Legacy classification.",
            applicationProfile: nil,
            packageRootPath: nil,
            isHidden: false
        )
    }

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
        fileIdentity: FileIdentity?,
        canonicalPath: String? = nil,
        coverage: ScanCoverage = .complete,
        deletionEligibility: DeletionEligibility,
        classificationRationale: String,
        applicationProfile: String? = nil,
        packageRootPath: String? = nil,
        isHidden: Bool = false
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
        self.fileIdentity = fileIdentity
        self.canonicalPath = canonicalPath
            .map { URL(fileURLWithPath: $0).standardizedFileURL.path }
            ?? standardizedURL.resolvingSymlinksInPath().standardizedFileURL.path
        self.coverage = coverage
        self.deletionEligibility = deletionEligibility
        self.classificationRationale = classificationRationale
        self.applicationProfile = applicationProfile
        self.packageRootPath = packageRootPath.map { URL(fileURLWithPath: $0).standardizedFileURL.path }
        self.isHidden = isHidden
    }

    private enum CodingKeys: String, CodingKey {
        case url
        case path
        case name
        case kind
        case category
        case risk
        case byteSize
        case fileCount
        case childFolderCount
        case modifiedAt
        case lastAccessedAt
        case rootPath
        case isDeletableCandidate
        case fileIdentity
        case canonicalPath
        case coverage
        case deletionEligibility
        case classificationRationale
        case applicationProfile
        case packageRootPath
        case isHidden
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let decodedURL = try container.decode(URL.self, forKey: .url).standardizedFileURL

        url = decodedURL
        path = decodedURL.path
        name = decodedURL.lastPathComponent.isEmpty ? decodedURL.path : decodedURL.lastPathComponent
        kind = try container.decode(DiskItemKind.self, forKey: .kind)
        category = try container.decode(DiskItemCategory.self, forKey: .category)
        risk = try container.decode(DeletionRisk.self, forKey: .risk)
        byteSize = try container.decode(Int64.self, forKey: .byteSize)
        fileCount = try container.decode(Int.self, forKey: .fileCount)
        childFolderCount = try container.decode(Int.self, forKey: .childFolderCount)
        modifiedAt = try container.decodeIfPresent(Date.self, forKey: .modifiedAt)
        lastAccessedAt = try container.decodeIfPresent(Date.self, forKey: .lastAccessedAt)
        rootPath = URL(
            fileURLWithPath: try container.decode(String.self, forKey: .rootPath)
        ).standardizedFileURL.path
        fileIdentity = try container.decodeIfPresent(FileIdentity.self, forKey: .fileIdentity)
        canonicalPath = try container.decodeIfPresent(String.self, forKey: .canonicalPath)
            ?? decodedURL.resolvingSymlinksInPath().standardizedFileURL.path
        applicationProfile = try container.decodeIfPresent(String.self, forKey: .applicationProfile)
        packageRootPath = try container.decodeIfPresent(String.self, forKey: .packageRootPath)
        isHidden = try container.decodeIfPresent(Bool.self, forKey: .isHidden) ?? false

        if let eligibility = try container.decodeIfPresent(DeletionEligibility.self, forKey: .deletionEligibility) {
            _ = eligibility
            deletionEligibility = .blocked("Saved scan snapshots must be refreshed before Trash is available.")
            coverage = try container.decodeIfPresent(ScanCoverage.self, forKey: .coverage) ?? .complete
            classificationRationale = try container.decodeIfPresent(String.self, forKey: .classificationRationale)
                ?? "Classification restored from a saved scan."
        } else {
            deletionEligibility = .blocked("Legacy saved scans must be refreshed before Trash is available.")
            coverage = .incomplete([path])
            classificationRationale = "Legacy saved scan; refresh required."
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(url, forKey: .url)
        try container.encode(path, forKey: .path)
        try container.encode(name, forKey: .name)
        try container.encode(kind, forKey: .kind)
        try container.encode(category, forKey: .category)
        try container.encode(risk, forKey: .risk)
        try container.encode(byteSize, forKey: .byteSize)
        try container.encode(fileCount, forKey: .fileCount)
        try container.encode(childFolderCount, forKey: .childFolderCount)
        try container.encodeIfPresent(modifiedAt, forKey: .modifiedAt)
        try container.encodeIfPresent(lastAccessedAt, forKey: .lastAccessedAt)
        try container.encode(rootPath, forKey: .rootPath)
        try container.encode(isDeletableCandidate, forKey: .isDeletableCandidate)
        try container.encodeIfPresent(fileIdentity, forKey: .fileIdentity)
        try container.encode(canonicalPath, forKey: .canonicalPath)
        try container.encode(coverage, forKey: .coverage)
        try container.encode(deletionEligibility, forKey: .deletionEligibility)
        try container.encode(classificationRationale, forKey: .classificationRationale)
        try container.encodeIfPresent(applicationProfile, forKey: .applicationProfile)
        try container.encodeIfPresent(packageRootPath, forKey: .packageRootPath)
        try container.encode(isHidden, forKey: .isHidden)
    }
}
