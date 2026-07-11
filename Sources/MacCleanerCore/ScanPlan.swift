import Darwin
import Foundation

public struct ScanPlanRule: Hashable, Codable, Sendable {
    public let root: ScanRoot
    public let canonicalPath: String
    public let identity: FileIdentity?

    public init(root: ScanRoot, canonicalPath: String, identity: FileIdentity?) {
        self.root = root
        self.canonicalPath = canonicalPath
        self.identity = identity
    }
}

public struct ScanPlanRoot: Hashable, Codable, Sendable {
    public let url: URL
    public let canonicalPath: String
    public let identity: FileIdentity
    public let matchingRules: [ScanPlanRule]

    public init(url: URL, canonicalPath: String, identity: FileIdentity, matchingRules: [ScanPlanRule]) {
        self.url = url.standardizedFileURL
        self.canonicalPath = canonicalPath
        self.identity = identity
        self.matchingRules = matchingRules
    }
}

public struct ScanPlan: Equatable, Codable, Sendable {
    public let configuredRoots: [ScanRoot]
    public let rules: [ScanPlanRule]
    public let enumerationRoots: [ScanPlanRoot]

    public init(roots: [ScanRoot]) {
        self.init(roots: roots, identityProvider: FileSystemSafety.identity(at:))
    }

    init(
        roots: [ScanRoot],
        identityProvider: @Sendable (URL) -> FileIdentity?
    ) {
        configuredRoots = roots

        let builtRules = roots.map { root in
            let url = root.url.standardizedFileURL
            let canonicalURL = URL(fileURLWithPath: FileSystemSafety.canonicalPath(for: url))
            return ScanPlanRule(
                root: root,
                canonicalPath: canonicalURL.path,
                identity: identityProvider(canonicalURL)
            )
        }
        rules = builtRules

        let existingRules = builtRules.filter { $0.identity != nil }
        let ordered = existingRules.sorted { lhs, rhs in
            let lhsDepth = FileSystemSafety.pathDepth(lhs.canonicalPath)
            let rhsDepth = FileSystemSafety.pathDepth(rhs.canonicalPath)
            if lhsDepth != rhsDepth { return lhsDepth < rhsDepth }
            return lhs.canonicalPath.localizedStandardCompare(rhs.canonicalPath) == .orderedAscending
        }

        var selected: [ScanPlanRule] = []
        for rule in ordered {
            guard !selected.contains(where: {
                $0.identity == rule.identity
                    || (FileSystemSafety.isPath(rule.canonicalPath, insideOrEqualTo: $0.canonicalPath)
                        && $0.identity?.deviceID == rule.identity?.deviceID)
            }) else {
                continue
            }

            selected.append(rule)
        }

        enumerationRoots = selected.compactMap { selectedRule in
            guard let identity = selectedRule.identity else { return nil }
            let matchingRules = builtRules.filter {
                FileSystemSafety.isPath($0.canonicalPath, insideOrEqualTo: selectedRule.canonicalPath)
            }
            return ScanPlanRoot(
                url: URL(fileURLWithPath: selectedRule.canonicalPath, isDirectory: true),
                canonicalPath: selectedRule.canonicalPath,
                identity: identity,
                matchingRules: matchingRules
            )
        }
    }

    public func matchingRules(for url: URL) -> [ScanPlanRule] {
        let path = FileSystemSafety.canonicalPath(for: url)
        return rules.filter { FileSystemSafety.isPath(path, insideOrEqualTo: $0.canonicalPath) }
    }

    public func isConfiguredRoot(_ url: URL) -> Bool {
        let lexicalPath = url.standardizedFileURL.path
        let canonicalPath = FileSystemSafety.canonicalPath(for: url)
        return rules.contains {
            $0.root.url.standardizedFileURL.path == lexicalPath || $0.canonicalPath == canonicalPath
        }
    }
}

enum FileSystemSafety {
    static func identity(at url: URL) -> FileIdentity? {
        var metadata = stat()
        guard Darwin.lstat(url.path, &metadata) == 0 else { return nil }
        return FileIdentity(
            deviceID: UInt64(metadata.st_dev),
            fileID: UInt64(metadata.st_ino)
        )
    }

    static func canonicalPath(for url: URL) -> String {
        url.resolvingSymlinksInPath().standardizedFileURL.path
    }

    static func isPath(_ path: String, insideOrEqualTo rootPath: String) -> Bool {
        path == rootPath || path.hasPrefix(rootPath == "/" ? "/" : rootPath + "/")
    }

    static func pathDepth(_ path: String) -> Int {
        URL(fileURLWithPath: path).pathComponents.count
    }

    static func relativeComponents(of path: String, below rootPath: String) -> ArraySlice<String> {
        let pathComponents = URL(fileURLWithPath: path).pathComponents
        let rootComponents = URL(fileURLWithPath: rootPath).pathComponents
        return pathComponents.dropFirst(rootComponents.count)
    }
}
