import Foundation

public struct ItemClassification: Equatable, Sendable {
    public let category: DiskItemCategory
    public let risk: DeletionRisk
    public let isDeletableCandidate: Bool

    public init(category: DiskItemCategory, risk: DeletionRisk, isDeletableCandidate: Bool) {
        self.category = category
        self.risk = risk
        self.isDeletableCandidate = isDeletableCandidate
    }
}

public struct ItemClassifier: Sendable {
    private let homePath: String

    public init(homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser) {
        homePath = homeDirectory.standardizedFileURL.path
    }

    public func classify(url: URL, kind: DiskItemKind, root: ScanRoot) -> ItemClassification {
        let path = url.standardizedFileURL.path
        let lowercasedPath = path.lowercased()
        var category = root.categoryHint ?? inferredCategory(for: lowercasedPath)
        var risk = root.riskHint ?? inferredRisk(for: lowercasedPath, category: category)

        if lowercasedPath.contains("/.codex") || lowercasedPath.contains("/codex") {
            category = .codex
            risk = max(risk, .medium)
        }

        if lowercasedPath.contains("capcut") || lowercasedPath.contains("com.lemon.lvoverseas") {
            category = .capCut
            risk = max(risk, .high)
        }

        if lowercasedPath.contains("final cut") || lowercasedPath.contains("finalcut") || lowercasedPath.contains("/proapps") {
            category = .finalCut
            risk = max(risk, .high)
        }

        if isProtectedSystemPath(path) || root.isSystemScope {
            risk = .protected
            if category == .other {
                category = .system
            }
        }

        if kind == .symbolicLink || kind == .inaccessible {
            risk = max(risk, .medium)
        }

        return ItemClassification(
            category: category,
            risk: risk,
            isDeletableCandidate: canOfferTrashMove(path: path, kind: kind, risk: risk)
        )
    }

    private func inferredCategory(for lowercasedPath: String) -> DiskItemCategory {
        if lowercasedPath.contains("/caches/") || lowercasedPath.hasSuffix("/caches") {
            return .cache
        }

        if lowercasedPath.contains("/logs/") || lowercasedPath.hasSuffix("/logs") {
            return .logs
        }

        if lowercasedPath.contains("/library/developer/") || lowercasedPath.hasSuffix("/library/developer") {
            return .developerData
        }

        if lowercasedPath.contains("/application support/") || lowercasedPath.hasSuffix("/application support") {
            return .applicationSupport
        }

        if lowercasedPath.contains("/downloads/") || lowercasedPath.hasSuffix("/downloads") {
            return .downloads
        }

        if lowercasedPath.contains("/documents/") || lowercasedPath.hasSuffix("/documents") {
            return .documents
        }

        if lowercasedPath.contains("/movies/") || lowercasedPath.hasSuffix("/movies") {
            return .media
        }

        if lowercasedPath.contains("/backups/") || lowercasedPath.contains("backup") {
            return .backups
        }

        if lowercasedPath.contains("/.trash/") || lowercasedPath.hasSuffix("/.trash") {
            return .trash
        }

        if lowercasedPath.hasPrefix("/system/") || lowercasedPath.hasPrefix("/library/") {
            return .system
        }

        return .other
    }

    private func inferredRisk(for lowercasedPath: String, category: DiskItemCategory) -> DeletionRisk {
        switch category {
        case .cache, .logs, .trash:
            return .low
        case .developerData, .applicationSupport, .downloads, .backups, .codex:
            return .medium
        case .media, .documents, .capCut, .finalCut:
            return .high
        case .system:
            return .protected
        case .other:
            if lowercasedPath.contains("/deriveddata/") || lowercasedPath.contains("/node_modules/") {
                return .low
            }
            return .medium
        }
    }

    private func isProtectedSystemPath(_ path: String) -> Bool {
        if path == "/" || path == "/System" || path.hasPrefix("/System/") {
            return true
        }

        if path == "/Applications" || path.hasPrefix("/Applications/") {
            return true
        }

        if path == "/Library" || path.hasPrefix("/Library/") {
            return true
        }

        if !path.hasPrefix(homePath + "/") && path != homePath {
            return true
        }

        return false
    }

    private func canOfferTrashMove(path: String, kind: DiskItemKind, risk: DeletionRisk) -> Bool {
        guard risk != .protected else {
            return false
        }

        guard kind != .inaccessible else {
            return false
        }

        let blockedHomePaths: Set<String> = [
            homePath,
            homePath + "/Library",
            homePath + "/Documents",
            homePath + "/Downloads",
            homePath + "/Movies",
            homePath + "/Desktop"
        ]

        if blockedHomePaths.contains(path) {
            return false
        }

        return true
    }
}
