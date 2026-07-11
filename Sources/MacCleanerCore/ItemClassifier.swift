import Foundation

public struct ItemClassification: Equatable, Sendable {
    public let category: DiskItemCategory
    public let risk: DeletionRisk
    public let deletionEligibility: DeletionEligibility
    public let rationale: String
    public let applicationProfile: String?

    public var isDeletableCandidate: Bool {
        deletionEligibility.isEligible
    }

    public init(
        category: DiskItemCategory,
        risk: DeletionRisk,
        isDeletableCandidate: Bool,
        rationale: String = "Classified from path and scan scope.",
        applicationProfile: String? = nil
    ) {
        self.init(
            category: category,
            risk: risk,
            deletionEligibility: isDeletableCandidate ? .eligible : .blocked("This item is protected."),
            rationale: rationale,
            applicationProfile: applicationProfile
        )
    }

    public init(
        category: DiskItemCategory,
        risk: DeletionRisk,
        deletionEligibility: DeletionEligibility,
        rationale: String,
        applicationProfile: String? = nil
    ) {
        self.category = category
        self.risk = risk
        self.deletionEligibility = deletionEligibility
        self.rationale = rationale
        self.applicationProfile = applicationProfile
    }
}

public struct ItemClassifier: Sendable {
    private let homePath: String

    public init(homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser) {
        homePath = FileSystemSafety.canonicalPath(for: homeDirectory)
    }

    public func classify(url: URL, kind: DiskItemKind, root: ScanRoot) -> ItemClassification {
        classify(
            url: url,
            kind: kind,
            matchingRoots: [root],
            isConfiguredRoot: url.standardizedFileURL.path == root.url.standardizedFileURL.path
        )
    }

    public func classify(
        url: URL,
        kind: DiskItemKind,
        matchingRoots: [ScanRoot],
        isConfiguredRoot: Bool = false,
        coverage: ScanCoverage = .complete,
        packageRootPath: String? = nil
    ) -> ItemClassification {
        let path = url.standardizedFileURL.path
        let canonicalPath = FileSystemSafety.canonicalPath(for: url)
        let lowercasedPath = canonicalPath.lowercased()
        let inferredCategory = inferredCategory(for: lowercasedPath)
        let categoryHint = mostSpecificCategoryHint(from: matchingRoots, itemPath: canonicalPath)
        let category = inferredCategory == .other ? (categoryHint ?? .other) : inferredCategory
        let inferredRisk = inferredRisk(for: lowercasedPath, category: category)
        let hintedRisk = matchingRoots.compactMap(\.riskHint).max() ?? .low
        var risk = max(inferredRisk, hintedRisk)
        let applicationProfile = inferredApplicationProfile(for: lowercasedPath, roots: matchingRoots)
        var reasons = ["\(category.displayName) content is \(inferredRisk.displayName.lowercased()) risk."]

        if hintedRisk > inferredRisk {
            reasons.append("A matching scan scope raises the risk to \(hintedRisk.displayName.lowercased()).")
        }

        if isProtectedSystemPath(canonicalPath) || matchingRoots.contains(where: \.isSystemScope) {
            risk = .protected
            reasons.append("The path is a protected system or outside-home location.")
        }

        let eligibility: DeletionEligibility
        if isConfiguredRoot {
            eligibility = .blocked("Configured scan roots cannot be moved to Trash.")
            reasons.append("It is a configured scan root.")
        } else if risk == .protected {
            eligibility = .blocked("Protected locations are scan-only.")
        } else if kind == .symbolicLink {
            eligibility = .blocked("Symbolic links are shown for inspection only.")
            reasons.append("Symlinks are never followed or deleted.")
        } else if kind == .inaccessible {
            eligibility = .blocked("The item could not be inspected completely.")
        } else if !coverage.isComplete {
            eligibility = .blocked("The item contains paths that could not be inspected completely.")
            reasons.append("Enumeration was incomplete.")
        } else if let packageRootPath, packageRootPath != path {
            eligibility = .blocked("Files inside a package cannot be removed individually.")
            reasons.append("The enclosing package is the atomic deletion unit.")
        } else if isBlockedHomeContainer(canonicalPath) {
            eligibility = .blocked("This home folder is a protected container.")
        } else {
            eligibility = .eligible
        }

        if let applicationProfile {
            reasons.append("Associated app: \(applicationProfile).")
        }

        return ItemClassification(
            category: category,
            risk: risk,
            deletionEligibility: eligibility,
            rationale: reasons.joined(separator: " "),
            applicationProfile: applicationProfile
        )
    }

    private func inferredCategory(for path: String) -> DiskItemCategory {
        if containsComponent("caches", in: path) { return .cache }
        if containsComponent("logs", in: path) { return .logs }
        if path.contains("/deriveddata/") || path.hasSuffix("/deriveddata") || path.contains("/build/") {
            return .developerData
        }
        if path.contains("/library/developer/") || path.hasSuffix("/library/developer") { return .developerData }
        if path.contains("/application support/") || path.hasSuffix("/application support") { return .applicationSupport }
        if path.contains("/library/containers/") || path.hasSuffix("/library/containers")
            || path.contains("/library/group containers/") || path.hasSuffix("/library/group containers") {
            return .applicationSupport
        }
        if path.contains("/node_modules/") || path.hasSuffix("/node_modules") { return .developerData }
        if path.contains("/.codex/") || path.hasSuffix("/.codex") { return .codex }
        if path.contains("backup") { return .backups }
        if hasContentLibraryExtension(path) || containsComponent("libraries", in: path) || containsComponent("library", in: path) {
            return .libraries
        }
        if hasProjectExtension(path)
            || containsComponent("projects", in: path)
            || containsComponent("repositories", in: path)
            || containsComponent("repos", in: path)
            || containsComponent("workspaces", in: path) {
            return .projectData
        }
        if containsComponent("downloads", in: path) { return .downloads }
        if containsComponent("documents", in: path) { return .documents }
        if containsComponent("movies", in: path) || containsComponent("pictures", in: path) || containsComponent("music", in: path) {
            return .media
        }
        if containsComponent(".trash", in: path) { return .trash }
        if path.hasPrefix("/system/") || path == "/system" || path.hasPrefix("/library/") || path == "/library" {
            return .system
        }
        return .other
    }

    private func inferredRisk(for path: String, category: DiskItemCategory) -> DeletionRisk {
        if path.contains("/deriveddata/") || path.hasSuffix("/deriveddata") || path.contains("/build/") || path.contains("/node_modules/") {
            return .low
        }

        switch category {
        case .cache, .logs, .trash:
            return .low
        case .developerData, .applicationSupport, .downloads, .backups, .codex:
            return .medium
        case .media, .documents, .libraries, .projectData, .capCut, .finalCut:
            return .high
        case .system:
            return .protected
        case .other:
            return .medium
        }
    }

    private func mostSpecificCategoryHint(from roots: [ScanRoot], itemPath: String) -> DiskItemCategory? {
        roots
            .filter { root in
                FileSystemSafety.isPath(itemPath, insideOrEqualTo: FileSystemSafety.canonicalPath(for: root.url))
            }
            .sorted {
                let lhsDepth = FileSystemSafety.pathDepth($0.url.path)
                let rhsDepth = FileSystemSafety.pathDepth($1.url.path)
                if lhsDepth != rhsDepth { return lhsDepth > rhsDepth }
                let lhsCategory = $0.categoryHint?.rawValue ?? ""
                let rhsCategory = $1.categoryHint?.rawValue ?? ""
                if lhsCategory != rhsCategory { return lhsCategory < rhsCategory }
                return $0.title.localizedStandardCompare($1.title) == .orderedAscending
            }
            .compactMap(\.categoryHint)
            .filter { $0 != .capCut && $0 != .finalCut }
            .first
    }

    private func inferredApplicationProfile(for path: String, roots: [ScanRoot]) -> String? {
        if path.contains("capcut") || path.contains("com.lemon.lvoverseas")
            || roots.contains(where: { $0.title.localizedCaseInsensitiveContains("CapCut") }) { return "CapCut" }
        if path.contains("final cut") || path.contains("finalcut") || path.contains("/proapps")
            || roots.contains(where: { $0.title.localizedCaseInsensitiveContains("Final Cut") }) { return "Final Cut Pro" }
        if path.contains("/.codex") || roots.contains(where: { $0.title.localizedCaseInsensitiveContains("Codex") }) { return "Codex" }
        return nil
    }

    private func hasContentLibraryExtension(_ path: String) -> Bool {
        ["photoslibrary", "photolibrary", "musiclibrary", "imovielibrary", "fcpbundle"].contains(
            URL(fileURLWithPath: path).pathExtension
        )
    }

    private func hasProjectExtension(_ path: String) -> Bool {
        ["xcodeproj", "xcworkspace", "playground", "logicx"].contains(
            URL(fileURLWithPath: path).pathExtension
        )
    }

    private func containsComponent(_ component: String, in path: String) -> Bool {
        path == "/\(component)" || path.hasSuffix("/\(component)") || path.contains("/\(component)/")
    }

    private func isProtectedSystemPath(_ path: String) -> Bool {
        if path == "/" || path == "/System" || path.hasPrefix("/System/") { return true }
        if path == "/Applications" || path.hasPrefix("/Applications/") { return true }
        if path == "/Library" || path.hasPrefix("/Library/") { return true }
        if path == homePath + "/Applications" || path.hasPrefix(homePath + "/Applications/") { return true }
        return !FileSystemSafety.isPath(path, insideOrEqualTo: homePath)
    }

    private func isBlockedHomeContainer(_ path: String) -> Bool {
        [
            homePath,
            homePath + "/Library",
            homePath + "/Documents",
            homePath + "/Downloads",
            homePath + "/Movies",
            homePath + "/Pictures",
            homePath + "/Music",
            homePath + "/Desktop"
        ].contains(path)
    }
}
