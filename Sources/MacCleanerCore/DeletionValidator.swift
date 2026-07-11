import CryptoKit
import Foundation

public struct DeletionPreflightSummary: Hashable, Sendable {
    public let url: URL
    public let canonicalPath: String
    public let kind: DiskItemKind
    public let category: DiskItemCategory
    public let risk: DeletionRisk
    public let classificationRationale: String
    public let scannedByteSize: Int64
    public let verifiedByteSize: Int64
    public let fileCount: Int
    public let folderCount: Int
    public let fingerprint: String
    public let identity: FileIdentity

    public var byteSizeDifference: Int64 {
        verifiedByteSize - scannedByteSize
    }

    public init(
        url: URL,
        canonicalPath: String,
        kind: DiskItemKind,
        category: DiskItemCategory,
        risk: DeletionRisk,
        classificationRationale: String,
        scannedByteSize: Int64,
        verifiedByteSize: Int64,
        fileCount: Int,
        folderCount: Int,
        fingerprint: String,
        identity: FileIdentity
    ) {
        self.url = url.standardizedFileURL
        self.canonicalPath = canonicalPath
        self.kind = kind
        self.category = category
        self.risk = risk
        self.classificationRationale = classificationRationale
        self.scannedByteSize = scannedByteSize
        self.verifiedByteSize = verifiedByteSize
        self.fileCount = fileCount
        self.folderCount = folderCount
        self.fingerprint = fingerprint
        self.identity = identity
    }
}

public struct ValidatedTrashRequest: Hashable, Sendable {
    public let summary: DeletionPreflightSummary
    public let scanID: UUID
    public let scanRootPath: String
    public let configuredRoots: [ScanRoot]

    init(
        summary: DeletionPreflightSummary,
        scanID: UUID,
        scanRootPath: String,
        configuredRoots: [ScanRoot]
    ) {
        self.summary = summary
        self.scanID = scanID
        self.scanRootPath = URL(fileURLWithPath: scanRootPath).standardizedFileURL.path
        self.configuredRoots = configuredRoots
    }
}

public enum DeletionRevalidation: Equatable, Sendable {
    case unchanged(ValidatedTrashRequest)
    case changed(ValidatedTrashRequest)

    public var request: ValidatedTrashRequest {
        switch self {
        case let .unchanged(request), let .changed(request): request
        }
    }

    public var requiresAnotherConfirmation: Bool {
        if case .changed = self { return true }
        return false
    }
}

public enum DeletionValidationError: Error, Equatable, LocalizedError, Sendable {
    case reportNotCurrent
    case itemNotEligible(String)
    case itemNotInReport
    case itemMissing(String)
    case identityChanged
    case canonicalPathChanged
    case kindChanged
    case configuredRoot
    case outsideScanRoot
    case packageInternal
    case mountedVolumeBoundary(String)
    case inspectionFailed(path: String, message: String)
    case contentsChanged

    public var errorDescription: String? {
        switch self {
        case .reportNotCurrent:
            "Run a fresh, complete scan before moving an item to Trash."
        case let .itemNotEligible(reason):
            reason
        case .itemNotInReport:
            "The selected item is not part of the current scan."
        case let .itemMissing(path):
            "The item no longer exists at \(path)."
        case .identityChanged:
            "The item at this path is not the file that was scanned. Refresh the scan."
        case .canonicalPathChanged:
            "The path now resolves to a different location. Refresh the scan."
        case .kindChanged:
            "The item type changed after it was scanned. Refresh the scan."
        case .configuredRoot:
            "Configured scan roots and folders containing them cannot be moved to Trash."
        case .outsideScanRoot:
            "The item is outside its verified scan root."
        case .packageInternal:
            "Files inside a package cannot be moved individually."
        case let .mountedVolumeBoundary(path):
            "A mounted volume boundary at \(path) prevents complete validation."
        case let .inspectionFailed(path, message):
            "Could not inspect \(path): \(message)"
        case .contentsChanged:
            "The item changed after confirmation. Review it again before moving it to Trash."
        }
    }
}

public protocol DeletionValidating: Sendable {
    func preflight(item: DiskItem, in report: ScanReport) async throws -> ValidatedTrashRequest
    func revalidate(_ request: ValidatedTrashRequest) async throws -> DeletionRevalidation
}

public actor FileSystemDeletionValidator: DeletionValidating {
    private let inspector: DeletionInspector

    public init(homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser) {
        inspector = DeletionInspector(homeDirectory: homeDirectory)
    }

    public func preflight(item: DiskItem, in report: ScanReport) async throws -> ValidatedTrashRequest {
        guard report.isActionable else { throw DeletionValidationError.reportNotCurrent }
        guard let scannedItem = report.items.first(where: { $0.id == item.id }) else {
            throw DeletionValidationError.itemNotInReport
        }
        guard scannedItem == item else { throw DeletionValidationError.itemNotInReport }
        guard scannedItem.deletionEligibility.isEligible else {
            throw DeletionValidationError.itemNotEligible(
                scannedItem.deletionEligibility.reason ?? "This item is protected."
            )
        }
        guard scannedItem.coverage.isComplete else {
            throw DeletionValidationError.itemNotEligible("The scan did not inspect every descendant.")
        }
        guard let scannedIdentity = scannedItem.fileIdentity else {
            throw DeletionValidationError.itemNotEligible("The scanned file identity is unavailable.")
        }

        let inspection = try inspector.inspect(
            url: scannedItem.url,
            scanRootPath: scannedItem.rootPath,
            configuredRoots: report.roots,
            scannedByteSize: scannedItem.byteSize,
            scannedCategory: scannedItem.category,
            minimumRisk: scannedItem.risk,
            scannedRationale: scannedItem.classificationRationale
        )
        guard inspection.summary.identity == scannedIdentity else {
            throw DeletionValidationError.identityChanged
        }
        guard inspection.summary.canonicalPath == scannedItem.canonicalPath else {
            throw DeletionValidationError.canonicalPathChanged
        }
        guard inspection.summary.kind == scannedItem.kind else {
            throw DeletionValidationError.kindChanged
        }

        return ValidatedTrashRequest(
            summary: inspection.summary,
            scanID: report.scanID,
            scanRootPath: scannedItem.rootPath,
            configuredRoots: report.roots
        )
    }

    public func revalidate(_ request: ValidatedTrashRequest) async throws -> DeletionRevalidation {
        let inspection = try inspector.inspect(
            url: request.summary.url,
            scanRootPath: request.scanRootPath,
            configuredRoots: request.configuredRoots,
            scannedByteSize: request.summary.scannedByteSize,
            scannedCategory: request.summary.category,
            minimumRisk: request.summary.risk,
            scannedRationale: request.summary.classificationRationale
        )
        guard inspection.summary.canonicalPath == request.summary.canonicalPath else {
            throw DeletionValidationError.canonicalPathChanged
        }
        guard inspection.summary.kind == request.summary.kind else {
            throw DeletionValidationError.kindChanged
        }

        let refreshedRequest = ValidatedTrashRequest(
            summary: inspection.summary,
            scanID: request.scanID,
            scanRootPath: request.scanRootPath,
            configuredRoots: request.configuredRoots
        )
        return inspection.summary == request.summary
            ? .unchanged(refreshedRequest)
            : .changed(refreshedRequest)
    }
}

struct DeletionInspector: Sendable {
    private let classifier: ItemClassifier

    init(homeDirectory: URL) {
        classifier = ItemClassifier(homeDirectory: homeDirectory)
    }

    func inspect(
        url rawURL: URL,
        scanRootPath rawScanRootPath: String,
        configuredRoots: [ScanRoot],
        scannedByteSize: Int64,
        scannedCategory: DiskItemCategory,
        minimumRisk: DeletionRisk,
        scannedRationale: String
    ) throws -> DeletionInspection {
        try Task.checkCancellation()
        let url = rawURL.standardizedFileURL
        let path = url.path
        let scanRootPath = FileSystemSafety.canonicalPath(for: URL(fileURLWithPath: rawScanRootPath))
        guard FileManager.default.fileExists(atPath: path) || FileSystemSafety.identity(at: url) != nil else {
            throw DeletionValidationError.itemMissing(path)
        }

        let canonicalPath = FileSystemSafety.canonicalPath(for: url)
        guard FileSystemSafety.isPath(canonicalPath, insideOrEqualTo: scanRootPath) else {
            throw DeletionValidationError.outsideScanRoot
        }
        guard !configuredRoots.contains(where: {
            let configuredPath = $0.url.standardizedFileURL.path
            let configuredCanonicalPath = FileSystemSafety.canonicalPath(for: $0.url)
            return FileSystemSafety.isPath(configuredPath, insideOrEqualTo: path)
                || FileSystemSafety.isPath(configuredCanonicalPath, insideOrEqualTo: canonicalPath)
        }) else {
            throw DeletionValidationError.configuredRoot
        }
        guard try enclosingPackagePath(for: url, stoppingAt: scanRootPath) == nil else {
            throw DeletionValidationError.packageInternal
        }

        let rootIdentity = try requiredIdentity(at: url)
        let rootValues = try values(at: url)
        let rootKind = kind(from: rootValues)
        guard rootKind != .symbolicLink && rootKind != .inaccessible else {
            throw DeletionValidationError.itemNotEligible("Symbolic links and inaccessible entries are read-only.")
        }

        var verifiedBytes: Int64 = 0
        var fileCount = 0
        var folderCount = 0
        var entries = [fingerprintEntry(
            relativePath: ".",
            kind: rootKind,
            identity: rootIdentity,
            byteSize: rootKind == .file ? allocatedSize(from: rootValues) : 0,
            modifiedAt: rootValues.contentModificationDate
        )]
        var accountedIdentities: Set<FileIdentity> = []

        if rootKind == .file {
            verifiedBytes = allocatedSize(from: rootValues)
            fileCount = 1
            accountedIdentities.insert(rootIdentity)
        } else {
            var enumerationFailure: (path: String, message: String)?
            guard let enumerator = FileManager.default.enumerator(
                at: url,
                includingPropertiesForKeys: Array(resourceKeys),
                options: [],
                errorHandler: { failedURL, error in
                    enumerationFailure = (failedURL.path, error.localizedDescription)
                    return false
                }
            ) else {
                throw DeletionValidationError.inspectionFailed(path: path, message: "Unable to enumerate path.")
            }

            while let descendantURL = enumerator.nextObject() as? URL {
                try Task.checkCancellation()
                let descendant = descendantURL.standardizedFileURL
                let descendantValues = try values(at: descendant)
                let descendantKind = kind(from: descendantValues)
                let identity = try requiredIdentity(at: descendant)
                guard identity.deviceID == rootIdentity.deviceID else {
                    if descendantKind == .folder || descendantKind == .package { enumerator.skipDescendants() }
                    throw DeletionValidationError.mountedVolumeBoundary(descendant.path)
                }
                if descendantKind != .symbolicLink {
                    let resolved = FileSystemSafety.canonicalPath(for: descendant)
                    guard FileSystemSafety.isPath(resolved, insideOrEqualTo: canonicalPath) else {
                        throw DeletionValidationError.canonicalPathChanged
                    }
                }

                let relativePath = String(descendant.path.dropFirst(path.count)).trimmingCharacters(in: CharacterSet(charactersIn: "/"))
                let bytes = allocatedSize(from: descendantValues)
                entries.append(fingerprintEntry(
                    relativePath: relativePath,
                    kind: descendantKind,
                    identity: identity,
                    byteSize: bytes,
                    modifiedAt: descendantValues.contentModificationDate
                ))

                switch descendantKind {
                case .file, .symbolicLink:
                    fileCount += 1
                    if accountedIdentities.insert(identity).inserted { verifiedBytes += bytes }
                case .folder, .package:
                    folderCount += 1
                case .inaccessible:
                    throw DeletionValidationError.inspectionFailed(
                        path: descendant.path,
                        message: "Unsupported or inaccessible file type."
                    )
                }
            }

            if let enumerationFailure {
                throw DeletionValidationError.inspectionFailed(
                    path: enumerationFailure.path,
                    message: enumerationFailure.message
                )
            }

            guard FileSystemSafety.identity(at: url) == rootIdentity else {
                throw DeletionValidationError.identityChanged
            }
        }

        let matchingRoots = configuredRoots.filter {
            FileSystemSafety.isPath(canonicalPath, insideOrEqualTo: FileSystemSafety.canonicalPath(for: $0.url))
        }
        let classification = classifier.classify(
            url: url,
            kind: rootKind,
            matchingRoots: matchingRoots,
            isConfiguredRoot: false,
            coverage: .complete,
            packageRootPath: nil
        )
        guard classification.deletionEligibility.isEligible else {
            throw DeletionValidationError.itemNotEligible(
                classification.deletionEligibility.reason ?? "The item is protected."
            )
        }

        let effectiveRisk = max(classification.risk, minimumRisk)
        let effectiveRationale = classification.risk > minimumRisk
            ? scannedRationale + " Current path classification raises the risk to \(classification.risk.displayName.lowercased())."
            : scannedRationale
        let fingerprintData = Data(entries.sorted().joined(separator: "\n").utf8)
        let fingerprint = SHA256.hash(data: fingerprintData).map { String(format: "%02x", $0) }.joined()
        return DeletionInspection(summary: DeletionPreflightSummary(
            url: url,
            canonicalPath: canonicalPath,
            kind: rootKind,
            category: scannedCategory,
            risk: effectiveRisk,
            classificationRationale: effectiveRationale,
            scannedByteSize: scannedByteSize,
            verifiedByteSize: verifiedBytes,
            fileCount: fileCount,
            folderCount: folderCount,
            fingerprint: fingerprint,
            identity: rootIdentity
        ))
    }

    private var resourceKeys: Set<URLResourceKey> {
        [
            .isDirectoryKey,
            .isRegularFileKey,
            .isSymbolicLinkKey,
            .isPackageKey,
            .fileSizeKey,
            .fileAllocatedSizeKey,
            .totalFileAllocatedSizeKey,
            .contentModificationDateKey
        ]
    }

    private func values(at url: URL) throws -> URLResourceValues {
        do {
            return try url.resourceValues(forKeys: resourceKeys)
        } catch {
            throw DeletionValidationError.inspectionFailed(path: url.path, message: error.localizedDescription)
        }
    }

    private func requiredIdentity(at url: URL) throws -> FileIdentity {
        guard let identity = FileSystemSafety.identity(at: url) else {
            throw DeletionValidationError.inspectionFailed(path: url.path, message: "File identity is unavailable.")
        }
        return identity
    }

    private func kind(from values: URLResourceValues) -> DiskItemKind {
        if values.isSymbolicLink == true { return .symbolicLink }
        if values.isDirectory == true { return values.isPackage == true ? .package : .folder }
        if values.isRegularFile == true { return .file }
        return .inaccessible
    }

    private func allocatedSize(from values: URLResourceValues) -> Int64 {
        Int64(values.totalFileAllocatedSize ?? values.fileAllocatedSize ?? values.fileSize ?? 0)
    }

    private func fingerprintEntry(
        relativePath: String,
        kind: DiskItemKind,
        identity: FileIdentity,
        byteSize: Int64,
        modifiedAt: Date?
    ) -> String {
        let modifiedBits = modifiedAt.map { $0.timeIntervalSince1970.bitPattern } ?? 0
        return [
            relativePath,
            kind.rawValue,
            String(identity.deviceID),
            String(identity.fileID),
            String(byteSize),
            String(modifiedBits)
        ].joined(separator: "\u{0}")
    }

    private func enclosingPackagePath(for url: URL, stoppingAt rootPath: String) throws -> String? {
        var current = url.deletingLastPathComponent().standardizedFileURL
        while FileSystemSafety.isPath(current.path, insideOrEqualTo: rootPath) {
            let values: URLResourceValues
            do {
                values = try current.resourceValues(forKeys: [.isPackageKey])
            } catch {
                throw DeletionValidationError.inspectionFailed(path: current.path, message: error.localizedDescription)
            }
            if values.isPackage == true {
                return current.path
            }
            if current.path == rootPath { break }
            let parent = current.deletingLastPathComponent().standardizedFileURL
            guard parent.path != current.path else { break }
            current = parent
        }
        return nil
    }
}

struct DeletionInspection: Sendable {
    let summary: DeletionPreflightSummary
}
