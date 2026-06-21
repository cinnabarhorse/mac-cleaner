import Foundation
import MacCleanerCore
import XCTest

final class TrashServiceTests: XCTestCase {
    func testTrashManagingAbstractionReturnsMovedItems() async throws {
        let original = URL(fileURLWithPath: "/tmp/example.dat")
        let trashed = URL(fileURLWithPath: "/tmp/.Trash/example.dat")
        let manager = FakeTrashManager(result: TrashOperationResult(items: [
            TrashedItem(originalURL: original, trashedURL: trashed)
        ]))

        let result = try await manager.moveToTrash([original])

        XCTAssertEqual(result.items, [TrashedItem(originalURL: original, trashedURL: trashed)])
        XCTAssertEqual(manager.requestedURLs, [original])
    }
}

private final class FakeTrashManager: TrashManaging, @unchecked Sendable {
    private(set) var requestedURLs: [URL] = []
    private let result: TrashOperationResult

    init(result: TrashOperationResult) {
        self.result = result
    }

    func moveToTrash(_ urls: [URL]) async throws -> TrashOperationResult {
        requestedURLs = urls
        return result
    }
}
