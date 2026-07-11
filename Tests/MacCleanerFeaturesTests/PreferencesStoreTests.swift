import Foundation
import MacCleanerCore
@testable import MacCleanerFeatures
import XCTest

final class PreferencesStoreTests: XCTestCase {
    func testPreferencesRoundTripThroughIsolatedUserDefaults() throws {
        let suiteName = "MacCleanerFeaturesTests-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let store = UserDefaultsCleanerPreferencesStore(defaults: defaults, key: "preferences")
        let root = ScanRoot(
            title: "Fixture",
            url: URL(fileURLWithPath: "/tmp/fixture", isDirectory: true)
        )
        let preferences = CleanerPreferences(
            selectedScopeIDs: [ScanScope.downloads.rawValue],
            customRoots: [root],
            showHiddenFiles: true,
            showPackageContents: false,
            showSymbolicLinks: true,
            minimumItemSizeBytes: 42,
            maxReturnedItems: 123
        )

        store.save(preferences)

        XCTAssertEqual(store.load(), preferences)
    }

    func testUnknownScopeIdentifiersAreIgnored() {
        let preferences = CleanerPreferences(
            selectedScopeIDs: [ScanScope.documents.rawValue, "future-scope"]
        )

        XCTAssertEqual(preferences.selectedScopes, [.documents])
    }
}
