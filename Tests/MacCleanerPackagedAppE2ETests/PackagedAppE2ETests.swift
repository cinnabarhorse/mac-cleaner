import AppKit
import Foundation
import MacCleanerCore
import MacCleanerFeatures
import XCTest

@MainActor
final class PackagedAppE2ETests: XCTestCase {
    func testPackagedAppSafetyAndPersistenceFlow() async throws {
        let environment = ProcessInfo.processInfo.environment
        guard let rawAppPath = environment["MAC_CLEANER_E2E_APP"] else {
            throw XCTSkip("Run scripts/test-packaged-app.sh to exercise the packaged application.")
        }

        let appURL = URL(fileURLWithPath: rawAppPath, isDirectory: true).standardizedFileURL
        let home = try requiredDirectory("HOME", environment: environment)
        let fixedHome = try requiredDirectory("CFFIXED_USER_HOME", environment: environment)
        let cleanerHome = try requiredDirectory("MAC_CLEANER_HOME", environment: environment)
        let dataDirectory = try requiredDirectory("MAC_CLEANER_DATA_DIR", environment: environment)
        XCTAssertEqual(home, fixedHome)
        XCTAssertEqual(home, cleanerHome)
        let disposableTempRoot = URL(fileURLWithPath: "/tmp", isDirectory: true).resolvingSymlinksInPath().path
        XCTAssertTrue(home.resolvingSymlinksInPath().path.hasPrefix(disposableTempRoot + "/"))
        XCTAssertTrue(dataDirectory.resolvingSymlinksInPath().path.hasPrefix(disposableTempRoot + "/"))

        let fixture = try makeFixture(in: cleanerHome)
        let bundleIdentifier = try XCTUnwrap(Bundle(url: appURL)?.bundleIdentifier)
        try configureAppPreferences(bundleIdentifier: bundleIdentifier, scanRoot: fixture.scanRoot)
        let reportURL = dataDirectory.appendingPathComponent("last-scan.json")
        let launchEnvironment = environment.merging([
            "HOME": home.path,
            "CFFIXED_USER_HOME": fixedHome.path,
            "MAC_CLEANER_HOME": cleanerHome.path,
            "MAC_CLEANER_DATA_DIR": dataDirectory.path
        ]) { _, isolated in isolated }

        let firstApplication = try await launch(appURL, environment: launchEnvironment)
        defer {
            if !firstApplication.isTerminated { firstApplication.forceTerminate() }
        }
        let firstReport = try await waitForReport(at: reportURL) { report in
            report.isComplete
                && report.items.contains(where: { $0.path == fixture.hiddenFile.path })
                && report.items.contains(where: { $0.path == fixture.packagePayload.path })
                && report.items.contains(where: { $0.path == fixture.symbolicLink.path })
        }
        await terminate(firstApplication)

        XCTAssertEqual(firstReport.roots.map(\.url), [fixture.scanRoot])
        XCTAssertEqual(firstReport.totalBytes, try allocatedTotal(of: fixture.regularFiles))
        let hiddenItem = try XCTUnwrap(firstReport.items.first { $0.path == fixture.hiddenFile.path })
        XCTAssertTrue(hiddenItem.isHidden)
        let packageItem = try XCTUnwrap(firstReport.items.first { $0.path == fixture.package.path })
        XCTAssertEqual(packageItem.kind, .package)
        let packagePayload = try XCTUnwrap(firstReport.items.first { $0.path == fixture.packagePayload.path })
        XCTAssertEqual(packagePayload.packageRootPath, fixture.package.path)
        XCTAssertFalse(packagePayload.deletionEligibility.isEligible)
        let symbolicLink = try XCTUnwrap(firstReport.items.first { $0.path == fixture.symbolicLink.path })
        XCTAssertEqual(symbolicLink.kind, .symbolicLink)
        XCTAssertFalse(symbolicLink.deletionEligibility.isEligible)

        let scanner = FileScanner(classifier: ItemClassifier(homeDirectory: cleanerHome))
        let currentReport = try await scanner.scan(
            roots: firstReport.roots,
            options: ScanOptions(minimumItemSizeBytes: 0)
        )
        let validator = FileSystemDeletionValidator(homeDirectory: cleanerHome)

        let scannedReplacement = try XCTUnwrap(currentReport.items.first { $0.path == fixture.replacementFile.path })
        let replacementStaging = dataDirectory.appendingPathComponent("replacement-staging.bin")
        try writeFile(replacementStaging, byteCount: 18 * 1_024 * 1_024)
        try FileManager.default.removeItem(at: fixture.replacementFile)
        try FileManager.default.moveItem(at: replacementStaging, to: fixture.replacementFile)
        do {
            _ = try await validator.preflight(item: scannedReplacement, in: currentReport)
            XCTFail("Replacing a scanned file at the same path must block validation.")
        } catch let error as DeletionValidationError {
            XCTAssertEqual(error, .identityChanged)
        }

        let trashFileItem = try XCTUnwrap(currentReport.items.first { $0.path == fixture.trashFile.path })
        let trashFolderItem = try XCTUnwrap(currentReport.items.first { $0.path == fixture.trashFolder.path })
        let trashFileRequest = try await validator.preflight(item: trashFileItem, in: currentReport)
        let trashFolderRequest = try await validator.preflight(item: trashFolderItem, in: currentReport)
        let trashService = FileManagerTrashService(homeDirectory: cleanerHome)
        var trashArtifacts: [URL] = []
        defer { trashArtifacts.forEach { try? FileManager.default.removeItem(at: $0) } }
        let trashedFile = try await trashService.moveToTrash(trashFileRequest)
        trashArtifacts.append(contentsOf: trashedFile.items.compactMap(\.trashedURL))
        let trashedFolder = try await trashService.moveToTrash(trashFolderRequest)
        trashArtifacts.append(contentsOf: trashedFolder.items.compactMap(\.trashedURL))
        XCTAssertFalse(FileManager.default.fileExists(atPath: fixture.trashFile.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: fixture.trashFolder.path))

        let secondApplication = try await launch(appURL, environment: launchEnvironment)
        defer {
            if !secondApplication.isTerminated { secondApplication.forceTerminate() }
        }
        let secondReport = try await waitForReport(at: reportURL) { report in
            report.isComplete
                && report.scanID != firstReport.scanID
                && report.items.contains(where: { $0.path == fixture.replacementFile.path })
                && !report.items.contains(where: { $0.path == fixture.trashFile.path })
                && !report.items.contains(where: {
                    $0.path == fixture.trashFolder.path || $0.path.hasPrefix(fixture.trashFolder.path + "/")
                })
        }
        await terminate(secondApplication)

        XCTAssertEqual(secondReport.totalBytes, try allocatedTotal(of: fixture.remainingRegularFiles))
        XCTAssertNotEqual(secondReport.scanID, firstReport.scanID)
        let persistedAfterRestart = try XCTUnwrap(ScanReportPersistence(fileURL: reportURL).load())
        XCTAssertEqual(persistedAfterRestart.scanID, secondReport.scanID)
        XCTAssertEqual(persistedAfterRestart.totalBytes, secondReport.totalBytes)
    }

    private func requiredDirectory(_ name: String, environment: [String: String]) throws -> URL {
        let value = try XCTUnwrap(environment[name], "Missing \(name)")
        let url = URL(fileURLWithPath: value, isDirectory: true).standardizedFileURL
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func configureAppPreferences(bundleIdentifier: String, scanRoot: URL) throws {
        let defaults = try XCTUnwrap(UserDefaults(suiteName: bundleIdentifier))
        defaults.removePersistentDomain(forName: bundleIdentifier)
        UserDefaultsCleanerPreferencesStore(defaults: defaults).save(CleanerPreferences(
            selectedScopeIDs: [],
            customRoots: [ScanRoot(
                title: "Packaged E2E",
                url: scanRoot,
                categoryHint: .cache,
                riskHint: .low
            )],
            showHiddenFiles: false,
            showPackageContents: false,
            showSymbolicLinks: false,
            minimumItemSizeBytes: 0,
            maxReturnedItems: 1_000
        ))
        XCTAssertTrue(defaults.synchronize())
    }

    private func launch(_ appURL: URL, environment: [String: String]) async throws -> NSRunningApplication {
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = false
        configuration.addsToRecentItems = false
        configuration.createsNewApplicationInstance = true
        configuration.environment = environment
        return try await NSWorkspace.shared.openApplication(at: appURL, configuration: configuration)
    }

    private func terminate(_ application: NSRunningApplication) async {
        application.terminate()
        for _ in 0..<50 where !application.isTerminated {
            try? await Task.sleep(for: .milliseconds(100))
        }
        if !application.isTerminated {
            application.forceTerminate()
        }
    }

    private func waitForReport(
        at url: URL,
        timeout: Duration = .seconds(20),
        matching predicate: (ScanReport) -> Bool
    ) async throws -> ScanReport {
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: timeout)
        while clock.now < deadline {
            if let report = try? ScanReportPersistence(fileURL: url).load(), predicate(report) {
                return report
            }
            try await Task.sleep(for: .milliseconds(100))
        }
        throw E2EFailure.timedOutWaitingForReport(url.path)
    }

    private func allocatedTotal(of urls: [URL]) throws -> Int64 {
        try urls.reduce(into: Int64(0)) { total, url in
            let values = try url.resourceValues(forKeys: [
                .fileSizeKey,
                .fileAllocatedSizeKey,
                .totalFileAllocatedSizeKey
            ])
            total += Int64(values.totalFileAllocatedSize ?? values.fileAllocatedSize ?? values.fileSize ?? 0)
        }
    }

    private func makeFixture(in home: URL) throws -> Fixture {
        let root = home.appendingPathComponent("PackagedE2E", isDirectory: true)
        let package = root.appendingPathComponent("Fixture.app", isDirectory: true)
        let packageContents = package.appendingPathComponent("Contents", isDirectory: true)
        let trashFolder = root.appendingPathComponent("TrashFolder", isDirectory: true)
        try FileManager.default.createDirectory(at: packageContents, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: trashFolder, withIntermediateDirectories: true)

        let visibleFile = root.appendingPathComponent("visible.bin")
        let hiddenFile = root.appendingPathComponent(".hidden.bin")
        let packagePayload = packageContents.appendingPathComponent("payload.bin")
        let replacementFile = root.appendingPathComponent("replacement.bin")
        let trashFile = root.appendingPathComponent("trash-file.bin")
        let trashFolderPayload = trashFolder.appendingPathComponent("payload.bin")
        try writeFile(visibleFile, byteCount: 12 * 1_024 * 1_024)
        try writeFile(hiddenFile, byteCount: 13 * 1_024 * 1_024)
        try writeFile(packagePayload, byteCount: 14 * 1_024 * 1_024)
        try writeFile(replacementFile, byteCount: 15 * 1_024 * 1_024)
        try writeFile(trashFile, byteCount: 16 * 1_024 * 1_024)
        try writeFile(trashFolderPayload, byteCount: 17 * 1_024 * 1_024)
        let symbolicLink = root.appendingPathComponent("visible-link")
        try FileManager.default.createSymbolicLink(at: symbolicLink, withDestinationURL: visibleFile)

        return Fixture(
            scanRoot: root,
            package: package,
            visibleFile: visibleFile,
            hiddenFile: hiddenFile,
            packagePayload: packagePayload,
            symbolicLink: symbolicLink,
            replacementFile: replacementFile,
            trashFile: trashFile,
            trashFolder: trashFolder,
            trashFolderPayload: trashFolderPayload
        )
    }

    private func writeFile(_ url: URL, byteCount: Int) throws {
        try Data(repeating: 0xA5, count: byteCount).write(to: url, options: .atomic)
    }
}

private struct Fixture {
    let scanRoot: URL
    let package: URL
    let visibleFile: URL
    let hiddenFile: URL
    let packagePayload: URL
    let symbolicLink: URL
    let replacementFile: URL
    let trashFile: URL
    let trashFolder: URL
    let trashFolderPayload: URL

    var regularFiles: [URL] {
        [visibleFile, hiddenFile, packagePayload, replacementFile, trashFile, trashFolderPayload]
    }

    var remainingRegularFiles: [URL] {
        [visibleFile, hiddenFile, packagePayload, replacementFile]
    }
}

private enum E2EFailure: Error, LocalizedError {
    case timedOutWaitingForReport(String)

    var errorDescription: String? {
        switch self {
        case let .timedOutWaitingForReport(path):
            "Timed out waiting for a completed packaged-app report at \(path)."
        }
    }
}
