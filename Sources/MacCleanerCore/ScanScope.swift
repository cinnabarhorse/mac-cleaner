import Foundation

public struct ScanRoot: Identifiable, Hashable, Codable, Sendable {
    public var id: String { url.path }

    public let title: String
    public let url: URL
    public let categoryHint: DiskItemCategory?
    public let riskHint: DeletionRisk?
    public let isSystemScope: Bool

    public init(
        title: String,
        url: URL,
        categoryHint: DiskItemCategory? = nil,
        riskHint: DeletionRisk? = nil,
        isSystemScope: Bool = false
    ) {
        self.title = title
        self.url = url.standardizedFileURL
        self.categoryHint = categoryHint
        self.riskHint = riskHint
        self.isSystemScope = isSystemScope
    }
}

public enum ScanScope: String, CaseIterable, Identifiable, Sendable {
    case documents
    case downloads
    case movies
    case libraryCaches
    case libraryLogs
    case applicationSupport
    case developerData
    case codex
    case capCut
    case finalCut
    case home
    case systemCaches
    case systemApplicationSupport

    public var id: String { rawValue }

    public static let defaultSelection: Set<ScanScope> = [
        .documents,
        .downloads,
        .movies,
        .libraryCaches,
        .libraryLogs,
        .applicationSupport,
        .developerData,
        .codex,
        .capCut,
        .finalCut
    ]

    public static let scanPriority: [ScanScope] = [
        .libraryCaches,
        .libraryLogs,
        .codex,
        .capCut,
        .finalCut,
        .downloads,
        .movies,
        .developerData,
        .applicationSupport,
        .documents,
        .home,
        .systemCaches,
        .systemApplicationSupport
    ]

    public var title: String {
        switch self {
        case .documents: "Documents"
        case .downloads: "Downloads"
        case .movies: "Movies"
        case .libraryCaches: "Library Caches"
        case .libraryLogs: "Library Logs"
        case .applicationSupport: "Application Support"
        case .developerData: "Developer Data"
        case .codex: "Codex"
        case .capCut: "CapCut"
        case .finalCut: "Final Cut Pro"
        case .home: "Home Folder"
        case .systemCaches: "System Caches"
        case .systemApplicationSupport: "System App Support"
        }
    }

    public var systemImage: String {
        switch self {
        case .documents: "doc.richtext"
        case .downloads: "arrow.down.circle"
        case .movies: "film.stack"
        case .libraryCaches: "externaldrive.badge.timemachine"
        case .libraryLogs: "doc.text.magnifyingglass"
        case .applicationSupport: "app.badge"
        case .developerData: "hammer"
        case .codex: "terminal"
        case .capCut: "scissors"
        case .finalCut: "video"
        case .home: "house"
        case .systemCaches: "gearshape.2"
        case .systemApplicationSupport: "internaldrive"
        }
    }

    public func roots(homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser) -> [ScanRoot] {
        switch self {
        case .documents:
            [root("Documents", title: title, home: homeDirectory, category: .documents, risk: .high)]
        case .downloads:
            [root("Downloads", title: title, home: homeDirectory, category: .downloads, risk: .medium)]
        case .movies:
            [root("Movies", title: title, home: homeDirectory, category: .media, risk: .high)]
        case .libraryCaches:
            [root("Library/Caches", title: title, home: homeDirectory, category: .cache, risk: .low)]
        case .libraryLogs:
            [root("Library/Logs", title: title, home: homeDirectory, category: .logs, risk: .low)]
        case .applicationSupport:
            [root("Library/Application Support", title: title, home: homeDirectory, category: .applicationSupport, risk: .medium)]
        case .developerData:
            [root("Library/Developer", title: title, home: homeDirectory, category: .developerData, risk: .medium)]
        case .codex:
            KnownAppProfile.codex.roots(homeDirectory: homeDirectory)
        case .capCut:
            KnownAppProfile.capCut.roots(homeDirectory: homeDirectory)
        case .finalCut:
            KnownAppProfile.finalCut.roots(homeDirectory: homeDirectory)
        case .home:
            [ScanRoot(title: title, url: homeDirectory)]
        case .systemCaches:
            [ScanRoot(title: title, url: URL(fileURLWithPath: "/Library/Caches"), categoryHint: .cache, riskHint: .protected, isSystemScope: true)]
        case .systemApplicationSupport:
            [ScanRoot(title: title, url: URL(fileURLWithPath: "/Library/Application Support"), categoryHint: .system, riskHint: .protected, isSystemScope: true)]
        }
    }

    private func root(
        _ relativePath: String,
        title: String,
        home: URL,
        category: DiskItemCategory,
        risk: DeletionRisk
    ) -> ScanRoot {
        ScanRoot(
            title: title,
            url: home.appendingPathComponent(relativePath, isDirectory: true),
            categoryHint: category,
            riskHint: risk
        )
    }
}
