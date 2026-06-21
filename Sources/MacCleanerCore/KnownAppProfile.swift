import Foundation

public struct KnownAppProfile: Identifiable, Hashable, Sendable {
    public let id: String
    public let name: String
    public let category: DiskItemCategory
    public let risk: DeletionRisk
    public let relativePaths: [String]
    public let absolutePaths: [String]

    public init(
        id: String,
        name: String,
        category: DiskItemCategory,
        risk: DeletionRisk,
        relativePaths: [String],
        absolutePaths: [String] = []
    ) {
        self.id = id
        self.name = name
        self.category = category
        self.risk = risk
        self.relativePaths = relativePaths
        self.absolutePaths = absolutePaths
    }

    public func roots(homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser) -> [ScanRoot] {
        let relativeRoots = relativePaths.map { relativePath in
            ScanRoot(
                title: name,
                url: homeDirectory.appendingPathComponent(relativePath, isDirectory: true),
                categoryHint: category,
                riskHint: risk
            )
        }

        let absoluteRoots = absolutePaths.map { absolutePath in
            ScanRoot(
                title: name,
                url: URL(fileURLWithPath: absolutePath, isDirectory: true),
                categoryHint: category,
                riskHint: risk,
                isSystemScope: !absolutePath.hasPrefix(homeDirectory.path)
            )
        }

        return relativeRoots + absoluteRoots
    }

    public static let codex = KnownAppProfile(
        id: "codex",
        name: "Codex",
        category: .codex,
        risk: .medium,
        relativePaths: [
            ".codex",
            "Library/Application Support/Codex",
            "Library/Caches/Codex",
            "Library/Logs/Codex"
        ]
    )

    public static let capCut = KnownAppProfile(
        id: "capcut",
        name: "CapCut",
        category: .capCut,
        risk: .high,
        relativePaths: [
            "Movies/CapCut",
            "Library/Application Support/CapCut",
            "Library/Application Support/com.lemon.lvoverseas",
            "Library/Caches/CapCut",
            "Library/Caches/com.lemon.lvoverseas",
            "Library/Containers/com.lemon.lvoverseas"
        ]
    )

    public static let finalCut = KnownAppProfile(
        id: "final-cut",
        name: "Final Cut Pro",
        category: .finalCut,
        risk: .high,
        relativePaths: [
            "Movies/Final Cut Backups",
            "Movies/Motion Templates",
            "Library/Application Support/ProApps",
            "Library/Caches/com.apple.FinalCut",
            "Library/Caches/com.apple.FinalCutTrial"
        ]
    )

    public static let defaults: [KnownAppProfile] = [
        .codex,
        .capCut,
        .finalCut
    ]
}
