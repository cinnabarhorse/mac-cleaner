import Foundation

public struct ScanReportPersistence: Sendable {
    public let fileURL: URL

    public init(fileURL: URL) {
        self.fileURL = fileURL.standardizedFileURL
    }

    public init(directoryURL: URL, fileName: String = "last-scan.json") {
        self.init(fileURL: directoryURL.appendingPathComponent(fileName, isDirectory: false))
    }

    public static func defaultStore(
        fileManager: FileManager = .default,
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> ScanReportPersistence {
        if let overrideDirectory = environment["MAC_CLEANER_DATA_DIR"], !overrideDirectory.isEmpty {
            return ScanReportPersistence(directoryURL: URL(fileURLWithPath: overrideDirectory, isDirectory: true))
        }

        let applicationSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? fileManager.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support", isDirectory: true)
        return ScanReportPersistence(directoryURL: applicationSupport.appendingPathComponent("MacCleaner", isDirectory: true))
    }

    public func load() throws -> ScanReport? {
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            return nil
        }

        let data = try Data(contentsOf: fileURL)
        return try decoder.decode(ScanReport.self, from: data)
    }

    public func save(_ report: ScanReport) throws {
        let directoryURL = fileURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)

        let data = try encoder.encode(report)
        try data.write(to: fileURL, options: [.atomic])
    }

    public func delete() throws {
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            return
        }

        try FileManager.default.removeItem(at: fileURL)
    }

    private var encoder: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }

    private var decoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}

public protocol ScanReportPersisting: Sendable {
    func load() async throws -> ScanReport?
    @discardableResult
    func save(_ report: ScanReport, revision: UInt64) async throws -> Bool
    @discardableResult
    func delete(revision: UInt64) async throws -> Bool
}

public actor SerializedScanReportStore: ScanReportPersisting {
    public nonisolated let fileURL: URL

    private let persistence: ScanReportPersistence
    private var latestRevision: UInt64 = 0

    public init(persistence: ScanReportPersistence = .defaultStore()) {
        self.persistence = persistence
        fileURL = persistence.fileURL
    }

    public func load() async throws -> ScanReport? {
        try persistence.load()
    }

    @discardableResult
    public func save(_ report: ScanReport, revision: UInt64) async throws -> Bool {
        guard revision > latestRevision else { return false }
        try persistence.save(report)
        latestRevision = revision
        return true
    }

    @discardableResult
    public func delete(revision: UInt64) async throws -> Bool {
        guard revision > latestRevision else { return false }
        try persistence.delete()
        latestRevision = revision
        return true
    }
}
