import Foundation

public enum FullDiskAccessStatus: String, Equatable, Sendable {
    case unknown
    case likelyGranted
    case likelyDenied
}

public struct FullDiskAccessProbe: Sendable {
    public static let defaultRelativePaths = [
        "Library/Messages",
        "Library/Mail",
        "Library/Safari"
    ]

    private let relativePaths: [String]

    public init(relativePaths: [String] = Self.defaultRelativePaths) {
        self.relativePaths = relativePaths
    }

    public func evaluate(homeDirectory: URL, fileManager: FileManager = .default) -> FullDiskAccessStatus {
        var readableProbeCount = 0
        var blockedProbeCount = 0

        for relativePath in relativePaths {
            let url = homeDirectory.appendingPathComponent(relativePath)
            guard fileManager.fileExists(atPath: url.path) else {
                continue
            }

            do {
                _ = try fileManager.contentsOfDirectory(
                    at: url,
                    includingPropertiesForKeys: nil,
                    options: [.skipsSubdirectoryDescendants]
                )
                readableProbeCount += 1
            } catch {
                blockedProbeCount += 1
            }
        }

        if readableProbeCount > 0 {
            return .likelyGranted
        }

        if blockedProbeCount > 0 {
            return .likelyDenied
        }

        return .unknown
    }
}
