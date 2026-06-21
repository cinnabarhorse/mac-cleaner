import MacCleanerCore
import XCTest

final class ScanIssueTests: XCTestCase {
    func testPermissionMessagesAreRecognized() {
        let issue = ScanIssue(
            path: "/Users/example/Library/Caches/com.apple.Safari",
            message: "The file could not be opened because you don't have permission to view it."
        )

        XCTAssertTrue(issue.isLikelyPermissionIssue)
    }

    func testNonPermissionMessagesAreNotRecognized() {
        let issue = ScanIssue(
            path: "/Users/example/Missing",
            message: "Path does not exist."
        )

        XCTAssertFalse(issue.isLikelyPermissionIssue)
    }
}
