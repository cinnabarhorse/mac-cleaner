import Foundation
import MacCleanerCore

public struct CleanerPreferences: Codable, Equatable, Sendable {
    public static let currentSchemaVersion = 1

    public var schemaVersion: Int
    public var selectedScopeIDs: Set<String>
    public var customRoots: [ScanRoot]
    public var showHiddenFiles: Bool
    public var showPackageContents: Bool
    public var showSymbolicLinks: Bool
    public var minimumItemSizeBytes: Int64
    public var maxReturnedItems: Int

    public init(
        schemaVersion: Int = CleanerPreferences.currentSchemaVersion,
        selectedScopeIDs: Set<String> = Set(ScanScope.defaultSelection.map(\.rawValue)),
        customRoots: [ScanRoot] = [],
        showHiddenFiles: Bool = false,
        showPackageContents: Bool = true,
        showSymbolicLinks: Bool = false,
        minimumItemSizeBytes: Int64 = 10 * 1_024 * 1_024,
        maxReturnedItems: Int = 5_000
    ) {
        self.schemaVersion = schemaVersion
        self.selectedScopeIDs = selectedScopeIDs
        self.customRoots = customRoots
        self.showHiddenFiles = showHiddenFiles
        self.showPackageContents = showPackageContents
        self.showSymbolicLinks = showSymbolicLinks
        self.minimumItemSizeBytes = minimumItemSizeBytes
        self.maxReturnedItems = maxReturnedItems
    }

    public var selectedScopes: Set<ScanScope> {
        Set(selectedScopeIDs.compactMap(ScanScope.init(rawValue:)))
    }
}

public protocol CleanerPreferencesPersisting: Sendable {
    func load() -> CleanerPreferences?
    func save(_ preferences: CleanerPreferences)
}

public struct UserDefaultsCleanerPreferencesStore: CleanerPreferencesPersisting, @unchecked Sendable {
    private let defaults: UserDefaults
    private let key: String

    public init(defaults: UserDefaults = .standard, key: String = "cleaner-preferences-v1") {
        self.defaults = defaults
        self.key = key
    }

    public func load() -> CleanerPreferences? {
        guard let data = defaults.data(forKey: key) else {
            return nil
        }

        return try? JSONDecoder().decode(CleanerPreferences.self, from: data)
    }

    public func save(_ preferences: CleanerPreferences) {
        guard let data = try? JSONEncoder().encode(preferences) else {
            return
        }

        defaults.set(data, forKey: key)
    }
}
