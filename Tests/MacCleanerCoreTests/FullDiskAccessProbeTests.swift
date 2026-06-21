import Foundation
import MacCleanerCore
import XCTest

final class FullDiskAccessProbeTests: XCTestCase {
    private var tempDirectory: URL!

    override func setUpWithError() throws {
        tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("MacCleanerFullDiskAccessTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        if let tempDirectory {
            try? FileManager.default.removeItem(at: tempDirectory)
        }
    }

    func testUnknownWhenNoProbePathsExist() {
        let probe = FullDiskAccessProbe(relativePaths: ["Missing"])

        XCTAssertEqual(probe.evaluate(homeDirectory: tempDirectory), .unknown)
    }

    func testLikelyGrantedWhenProbePathIsReadable() throws {
        try FileManager.default.createDirectory(
            at: tempDirectory.appendingPathComponent("Readable", isDirectory: true),
            withIntermediateDirectories: true
        )
        let probe = FullDiskAccessProbe(relativePaths: ["Readable"])

        XCTAssertEqual(probe.evaluate(homeDirectory: tempDirectory), .likelyGranted)
    }

    func testLikelyDeniedWhenProbePathCannotBeRead() throws {
        let blockedURL = tempDirectory.appendingPathComponent("Blocked", isDirectory: true)
        try FileManager.default.createDirectory(at: blockedURL, withIntermediateDirectories: true)
        try FileManager.default.setAttributes([.posixPermissions: 0], ofItemAtPath: blockedURL.path)
        defer {
            try? FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: blockedURL.path)
        }

        if FileManager.default.isReadableFile(atPath: blockedURL.path) {
            throw XCTSkip("Current process can still read a chmod 000 directory.")
        }

        let probe = FullDiskAccessProbe(relativePaths: ["Blocked"])

        XCTAssertEqual(probe.evaluate(homeDirectory: tempDirectory), .likelyDenied)
    }
}
