import Foundation
@testable import MacCleanerCore
import XCTest

final class TrashServiceTests: XCTestCase {
    func testTrashManagingAbstractionAcceptsOneValidatedRequest() async throws {
        let original = URL(fileURLWithPath: "/tmp/example.dat")
        let trashed = URL(fileURLWithPath: "/tmp/.Trash/example.dat")
        let request = makeRequest(url: original)
        let manager = FakeTrashManager(result: TrashOperationResult(items: [
            TrashedItem(originalURL: original, trashedURL: trashed)
        ]))

        let result = try await manager.moveToTrash(request)

        XCTAssertEqual(result.items, [TrashedItem(originalURL: original, trashedURL: trashed)])
        XCTAssertEqual(manager.requestedRequest, request)
    }

    private func makeRequest(url: URL) -> ValidatedTrashRequest {
        ValidatedTrashRequest(
            summary: DeletionPreflightSummary(
                url: url,
                canonicalPath: url.path,
                kind: .file,
                category: .cache,
                risk: .low,
                classificationRationale: "Test fixture.",
                scannedByteSize: 42,
                verifiedByteSize: 42,
                fileCount: 1,
                folderCount: 0,
                fingerprint: "fixture",
                identity: FileIdentity(deviceID: 1, fileID: 2)
            ),
            scanID: UUID(),
            scanRootPath: "/tmp",
            configuredRoots: []
        )
    }
}

private final class FakeTrashManager: TrashManaging, @unchecked Sendable {
    private(set) var requestedRequest: ValidatedTrashRequest?
    private let result: TrashOperationResult

    init(result: TrashOperationResult) {
        self.result = result
    }

    func moveToTrash(_ request: ValidatedTrashRequest) async throws -> TrashOperationResult {
        requestedRequest = request
        return result
    }
}
