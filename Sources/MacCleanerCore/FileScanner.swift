import Foundation

public typealias ScanProgressHandler = @Sendable (ScanProgress) async -> Void

public protocol FileScanning: Sendable {
    func scan(
        roots: [ScanRoot],
        options: ScanOptions,
        progress: ScanProgressHandler?
    ) async throws -> ScanReport
}

public extension FileScanning {
    func scan(roots: [ScanRoot], options: ScanOptions = ScanOptions()) async throws -> ScanReport {
        try await scan(roots: roots, options: options, progress: nil)
    }
}

public actor FileScanner: FileScanning {
    private let classifier: ItemClassifier
    private let identityProvider: @Sendable (URL) -> FileIdentity?

    public init(classifier: ItemClassifier = ItemClassifier()) {
        self.classifier = classifier
        identityProvider = FileSystemSafety.identity(at:)
    }

    init(
        classifier: ItemClassifier,
        identityProvider: @escaping @Sendable (URL) -> FileIdentity?
    ) {
        self.classifier = classifier
        self.identityProvider = identityProvider
    }

    public func scan(
        roots rawRoots: [ScanRoot],
        options: ScanOptions = ScanOptions(),
        progress: ScanProgressHandler? = nil
    ) async throws -> ScanReport {
        let startedAt = Date()
        let scanID = UUID()
        let fileManager = FileManager.default
        let plan = ScanPlan(roots: rawRoots, identityProvider: identityProvider)
        var issues: [ScanIssue] = []
        var seeds: [String: ItemSeed] = [:]
        var directoryBytes: [String: Int64] = [:]
        var directoryFileCounts: [String: Int] = [:]
        var directoryFolderCounts: [String: Int] = [:]
        var coverageIssues: [String: Set<String>] = [:]
        var accountedFileIdentities: Set<FileIdentity> = []
        var scannedItemCount = 0
        var scannedFileCount = 0
        var scannedFolderCount = 0
        var totalBytes: Int64 = 0
        var lastSnapshotAt = Date()

        func recordIssue(path rawPath: String, message: String, rootPath: String?) {
            let path = URL(fileURLWithPath: rawPath).standardizedFileURL.path
            issues.append(ScanIssue(path: path, message: message))
            guard let rootPath else { return }

            var current = path
            while FileSystemSafety.isPath(current, insideOrEqualTo: rootPath) {
                coverageIssues[current, default: []].insert(path)
                if current == rootPath { break }
                let parent = URL(fileURLWithPath: current).deletingLastPathComponent().standardizedFileURL.path
                guard parent != current else { break }
                current = parent
            }
        }

        for rule in plan.rules where rule.identity == nil {
            recordIssue(path: rule.root.url.path, message: "Path does not exist or cannot be inspected.", rootPath: nil)
        }

        for planRoot in plan.enumerationRoots {
            try Task.checkCancellation()

            let rootURL = planRoot.url.standardizedFileURL
            let rootPath = planRoot.canonicalPath
            var hiddenByDirectory: [String: Bool] = [:]
            var packageByDirectory: [String: String] = [:]

            await progress?(ScanProgress(
                currentPath: rootPath,
                scannedItemCount: scannedItemCount,
                scannedByteCount: totalBytes,
                partialReport: seeds.isEmpty ? nil : makeReport(
                    plan: plan,
                    seeds: seeds,
                    directoryBytes: directoryBytes,
                    directoryFileCounts: directoryFileCounts,
                    directoryFolderCounts: directoryFolderCounts,
                    coverageIssues: coverageIssues,
                    issues: issues,
                    totalBytes: totalBytes,
                    scannedItemCount: scannedItemCount,
                    scannedFileCount: scannedFileCount,
                    scannedFolderCount: scannedFolderCount,
                    startedAt: startedAt,
                    scanID: scanID,
                    options: options,
                    isComplete: false
                )
            ))

            let rootValues: URLResourceValues
            do {
                rootValues = try rootURL.resourceValues(forKeys: resourceKeys)
            } catch {
                recordIssue(path: rootPath, message: error.localizedDescription, rootPath: rootPath)
                continue
            }

            let rootKind = itemKind(from: rootValues)
            let rootHidden = rootValues.isHidden == true || rootURL.lastPathComponent.hasPrefix(".")
            hiddenByDirectory[rootPath] = rootHidden
            directoryBytes[rootPath, default: 0] = 0
            directoryFileCounts[rootPath, default: 0] = 0
            directoryFolderCounts[rootPath, default: 0] = 0

            if rootKind == .package {
                packageByDirectory[rootPath] = rootPath
            }

            let rootIdentity = identityProvider(rootURL)
            let rootDirectBytes = allocatedSize(from: rootValues)
            let rootAccountedBytes: Int64
            if rootKind == .file || rootKind == .symbolicLink {
                rootAccountedBytes = if let rootIdentity {
                    accountedFileIdentities.insert(rootIdentity).inserted ? rootDirectBytes : 0
                } else {
                    rootDirectBytes
                }
            } else {
                rootAccountedBytes = 0
            }

            seeds[rootPath] = ItemSeed(
                url: rootURL,
                canonicalPath: rootPath,
                kind: rootKind,
                values: rootValues,
                accountedBytes: rootAccountedBytes,
                qualifyingBytes: rootDirectBytes,
                identity: rootIdentity,
                enumerationRootPath: rootPath,
                packageRootPath: nil,
                isHidden: rootHidden
            )

            if rootKind == .file || rootKind == .symbolicLink {
                scannedItemCount += 1
                scannedFileCount += 1
                totalBytes += rootAccountedBytes
                continue
            }

            guard let enumerator = fileManager.enumerator(
                at: rootURL,
                includingPropertiesForKeys: Array(resourceKeys),
                options: [],
                errorHandler: { url, error in
                    recordIssue(path: url.path, message: error.localizedDescription, rootPath: rootPath)
                    return true
                }
            ) else {
                recordIssue(path: rootPath, message: "Unable to enumerate path.", rootPath: rootPath)
                continue
            }

            while let url = enumerator.nextObject() as? URL {
                try Task.checkCancellation()
                let standardizedURL = url.standardizedFileURL
                let path = standardizedURL.path
                let parentPath = standardizedURL.deletingLastPathComponent().standardizedFileURL.path

                do {
                    let values = try standardizedURL.resourceValues(forKeys: resourceKeys)
                    let kind = itemKind(from: values)
                    let identity = identityProvider(standardizedURL)
                    let canonicalPath = FileSystemSafety.canonicalPath(for: standardizedURL)

                    if kind != .symbolicLink && !FileSystemSafety.isPath(canonicalPath, insideOrEqualTo: rootPath) {
                        recordIssue(path: path, message: "The path resolves outside its scan root.", rootPath: rootPath)
                        if kind == .folder || kind == .package { enumerator.skipDescendants() }
                        continue
                    }

                    let crossesMountBoundary = identity.map {
                        $0.deviceID != planRoot.identity.deviceID
                    } ?? false
                    if crossesMountBoundary {
                        recordIssue(path: path, message: "Mounted volume boundary was not traversed.", rootPath: rootPath)
                        if kind == .folder || kind == .package { enumerator.skipDescendants() }
                    }

                    scannedItemCount += 1
                    let directBytes = allocatedSize(from: values)
                    let parentIsHidden = hiddenByDirectory[parentPath] ?? false
                    let isHidden = parentIsHidden || values.isHidden == true || standardizedURL.lastPathComponent.hasPrefix(".")
                    let inheritedPackage = packageByDirectory[parentPath]

                    switch kind {
                    case .file, .symbolicLink:
                        scannedFileCount += 1
                        let shouldAccount: Bool
                        if crossesMountBoundary {
                            shouldAccount = false
                        } else if let identity {
                            shouldAccount = accountedFileIdentities.insert(identity).inserted
                        } else {
                            shouldAccount = true
                        }
                        let accountedBytes = shouldAccount ? directBytes : 0
                        totalBytes += accountedBytes
                        addFile(
                            at: standardizedURL,
                            accountedBytes: accountedBytes,
                            rootPath: rootPath,
                            directoryBytes: &directoryBytes,
                            directoryFileCounts: &directoryFileCounts
                        )

                        if directBytes >= options.minimumItemSizeBytes || kind == .symbolicLink {
                            seeds[path] = ItemSeed(
                                url: standardizedURL,
                                canonicalPath: canonicalPath,
                                kind: kind,
                                values: values,
                                accountedBytes: accountedBytes,
                                qualifyingBytes: directBytes,
                                identity: identity,
                                enumerationRootPath: rootPath,
                                packageRootPath: inheritedPackage,
                                isHidden: isHidden
                            )
                        }

                    case .folder, .package:
                        scannedFolderCount += 1
                        directoryBytes[path, default: 0] = 0
                        directoryFileCounts[path, default: 0] = 0
                        directoryFolderCounts[path, default: 0] = 0
                        addFolder(
                            at: standardizedURL,
                            rootPath: rootPath,
                            directoryFolderCounts: &directoryFolderCounts
                        )
                        hiddenByDirectory[path] = isHidden
                        packageByDirectory[path] = inheritedPackage ?? (kind == .package ? path : nil)
                        seeds[path] = ItemSeed(
                            url: standardizedURL,
                            canonicalPath: canonicalPath,
                            kind: kind,
                            values: values,
                            accountedBytes: 0,
                            qualifyingBytes: 0,
                            identity: identity,
                            enumerationRootPath: rootPath,
                            packageRootPath: inheritedPackage,
                            isHidden: isHidden
                        )

                    case .inaccessible:
                        recordIssue(path: path, message: "Unsupported or inaccessible file type.", rootPath: rootPath)
                    }

                    let now = Date()
                    let shouldSnapshot = now.timeIntervalSince(lastSnapshotAt) >= options.snapshotInterval
                    if shouldSnapshot || scannedItemCount.isMultiple(of: 100) {
                        let partialReport = shouldSnapshot ? makeReport(
                            plan: plan,
                            seeds: seeds,
                            directoryBytes: directoryBytes,
                            directoryFileCounts: directoryFileCounts,
                            directoryFolderCounts: directoryFolderCounts,
                            coverageIssues: coverageIssues,
                            issues: issues,
                            totalBytes: totalBytes,
                            scannedItemCount: scannedItemCount,
                            scannedFileCount: scannedFileCount,
                            scannedFolderCount: scannedFolderCount,
                            startedAt: startedAt,
                            scanID: scanID,
                            options: options,
                            isComplete: false
                        ) : nil
                        if shouldSnapshot { lastSnapshotAt = now }

                        await progress?(ScanProgress(
                            currentPath: path,
                            scannedItemCount: scannedItemCount,
                            scannedByteCount: totalBytes,
                            partialReport: partialReport
                        ))
                    }
                } catch {
                    recordIssue(path: path, message: error.localizedDescription, rootPath: rootPath)
                }
            }

            await progress?(ScanProgress(
                currentPath: rootPath,
                scannedItemCount: scannedItemCount,
                scannedByteCount: totalBytes,
                partialReport: makeReport(
                    plan: plan,
                    seeds: seeds,
                    directoryBytes: directoryBytes,
                    directoryFileCounts: directoryFileCounts,
                    directoryFolderCounts: directoryFolderCounts,
                    coverageIssues: coverageIssues,
                    issues: issues,
                    totalBytes: totalBytes,
                    scannedItemCount: scannedItemCount,
                    scannedFileCount: scannedFileCount,
                    scannedFolderCount: scannedFolderCount,
                    startedAt: startedAt,
                    scanID: scanID,
                    options: options,
                    isComplete: false
                )
            ))
            lastSnapshotAt = Date()
        }

        return makeReport(
            plan: plan,
            seeds: seeds,
            directoryBytes: directoryBytes,
            directoryFileCounts: directoryFileCounts,
            directoryFolderCounts: directoryFolderCounts,
            coverageIssues: coverageIssues,
            issues: issues,
            totalBytes: totalBytes,
            scannedItemCount: scannedItemCount,
            scannedFileCount: scannedFileCount,
            scannedFolderCount: scannedFolderCount,
            startedAt: startedAt,
            scanID: scanID,
            options: options,
            isComplete: true
        )
    }

    private func makeReport(
        plan: ScanPlan,
        seeds: [String: ItemSeed],
        directoryBytes: [String: Int64],
        directoryFileCounts: [String: Int],
        directoryFolderCounts: [String: Int],
        coverageIssues: [String: Set<String>],
        issues: [ScanIssue],
        totalBytes: Int64,
        scannedItemCount: Int,
        scannedFileCount: Int,
        scannedFolderCount: Int,
        startedAt: Date,
        scanID: UUID,
        options: ScanOptions,
        isComplete: Bool
    ) -> ScanReport {
        let observations = seeds.values.compactMap { seed -> DiskItem? in
            let byteSize: Int64
            let fileCount: Int
            let folderCount: Int

            switch seed.kind {
            case .file, .symbolicLink:
                byteSize = seed.accountedBytes
                fileCount = 1
                folderCount = 0
            case .folder, .package:
                byteSize = directoryBytes[seed.url.path] ?? 0
                fileCount = directoryFileCounts[seed.url.path] ?? 0
                folderCount = directoryFolderCounts[seed.url.path] ?? 0
            case .inaccessible:
                byteSize = 0
                fileCount = 0
                folderCount = 0
            }

            guard seed.kind == .symbolicLink
                || max(byteSize, seed.qualifyingBytes) >= options.minimumItemSizeBytes else { return nil }
            let issuePaths = Array(coverageIssues[seed.url.path] ?? []).sorted()
            let coverage = issuePaths.isEmpty ? ScanCoverage.complete : .incomplete(issuePaths)
            let matchingRoots = plan.rules
                .filter { FileSystemSafety.isPath(seed.canonicalPath, insideOrEqualTo: $0.canonicalPath) }
                .map(\.root)
            let isConfiguredRoot = plan.rules.contains {
                seed.url.path == $0.root.url.standardizedFileURL.path || seed.canonicalPath == $0.canonicalPath
            }
            let containsConfiguredRoot = seed.kind == .folder || seed.kind == .package
                ? plan.rules.contains {
                    FileSystemSafety.isPath($0.root.url.standardizedFileURL.path, insideOrEqualTo: seed.url.path)
                        || FileSystemSafety.isPath($0.canonicalPath, insideOrEqualTo: seed.canonicalPath)
                }
                : false
            let classification = classifier.classify(
                url: seed.url,
                kind: seed.kind,
                matchingRoots: matchingRoots,
                isConfiguredRoot: isConfiguredRoot,
                coverage: coverage,
                packageRootPath: seed.packageRootPath
            )
            let eligibility: DeletionEligibility
            if seed.identity == nil {
                eligibility = .blocked("The file identity could not be verified.")
            } else if containsConfiguredRoot && !isConfiguredRoot {
                eligibility = .blocked("This folder contains a configured scan root.")
            } else {
                eligibility = classification.deletionEligibility
            }
            let rationale = containsConfiguredRoot && !isConfiguredRoot
                ? classification.rationale + " Deleting it would also remove a configured scan root."
                : classification.rationale

            return DiskItem(
                url: seed.url,
                kind: seed.kind,
                category: classification.category,
                risk: classification.risk,
                byteSize: byteSize,
                fileCount: fileCount,
                childFolderCount: folderCount,
                modifiedAt: seed.values.contentModificationDate,
                lastAccessedAt: seed.values.contentAccessDate,
                rootPath: seed.enumerationRootPath,
                fileIdentity: seed.identity,
                canonicalPath: seed.canonicalPath,
                coverage: coverage,
                deletionEligibility: eligibility,
                classificationRationale: rationale,
                applicationProfile: classification.applicationProfile,
                packageRootPath: seed.packageRootPath,
                isHidden: seed.isHidden
            )
        }

        let items = mergeDuplicateObservations(observations)
        .sorted { lhs, rhs in
            if lhs.byteSize == rhs.byteSize {
                return lhs.path.localizedStandardCompare(rhs.path) == .orderedAscending
            }
            return lhs.byteSize > rhs.byteSize
        }
        .prefix(options.maxReturnedItems)

        var seenIssues: Set<String> = []
        let uniqueIssues = issues.filter { seenIssues.insert($0.id).inserted }
        return ScanReport(
            roots: plan.configuredRoots,
            items: Array(items),
            issues: uniqueIssues,
            totalBytes: totalBytes,
            scannedItemCount: scannedItemCount,
            scannedFileCount: scannedFileCount,
            scannedFolderCount: scannedFolderCount,
            startedAt: startedAt,
            finishedAt: Date(),
            isComplete: isComplete,
            scanID: scanID,
            freshness: .current
        )
    }

    private func mergeDuplicateObservations(_ observations: [DiskItem]) -> [DiskItem] {
        var observationsByIdentity: [FileIdentity: [DiskItem]] = [:]
        for item in observations {
            guard let identity = item.fileIdentity else { continue }
            observationsByIdentity[identity, default: []].append(item)
        }

        return observations.map { item in
            guard let identity = item.fileIdentity,
                  let duplicates = observationsByIdentity[identity],
                  duplicates.count > 1 else {
                return item
            }

            let highestRisk = duplicates.map(\.risk).max() ?? item.risk
            let blockingObservation = duplicates
                .filter { !$0.deletionEligibility.isEligible || $0.risk == .protected }
                .sorted {
                    if $0.risk != $1.risk { return $0.risk > $1.risk }
                    return $0.path.localizedStandardCompare($1.path) == .orderedAscending
                }
                .first
            let mergedEligibility = blockingObservation.map { blockedItem in
                DeletionEligibility.blocked(
                    "A duplicate physical observation is read-only: \(blockedItem.deletionEligibility.reason ?? "the matching location is protected")."
                )
            } ?? item.deletionEligibility

            guard highestRisk != item.risk || mergedEligibility != item.deletionEligibility else {
                return item
            }

            var rationale = item.classificationRationale
            if highestRisk > item.risk {
                rationale += " A hard-linked observation raises the risk to \(highestRisk.displayName.lowercased())."
            }
            if blockingObservation != nil {
                rationale += " A protected or read-only observation of the same physical item blocks deletion."
            }

            return DiskItem(
                url: item.url,
                kind: item.kind,
                category: item.category,
                risk: highestRisk,
                byteSize: item.byteSize,
                fileCount: item.fileCount,
                childFolderCount: item.childFolderCount,
                modifiedAt: item.modifiedAt,
                lastAccessedAt: item.lastAccessedAt,
                rootPath: item.rootPath,
                fileIdentity: item.fileIdentity,
                canonicalPath: item.canonicalPath,
                coverage: item.coverage,
                deletionEligibility: mergedEligibility,
                classificationRationale: rationale,
                applicationProfile: item.applicationProfile,
                packageRootPath: item.packageRootPath,
                isHidden: item.isHidden
            )
        }
    }

    private var resourceKeys: Set<URLResourceKey> {
        [
            .isDirectoryKey,
            .isRegularFileKey,
            .isSymbolicLinkKey,
            .isPackageKey,
            .isHiddenKey,
            .fileSizeKey,
            .fileAllocatedSizeKey,
            .totalFileAllocatedSizeKey,
            .contentModificationDateKey,
            .contentAccessDateKey
        ]
    }

    private func itemKind(from values: URLResourceValues) -> DiskItemKind {
        if values.isSymbolicLink == true { return .symbolicLink }
        if values.isDirectory == true { return values.isPackage == true ? .package : .folder }
        if values.isRegularFile == true { return .file }
        return .inaccessible
    }

    private func allocatedSize(from values: URLResourceValues) -> Int64 {
        Int64(values.totalFileAllocatedSize ?? values.fileAllocatedSize ?? values.fileSize ?? 0)
    }

    private func addFile(
        at url: URL,
        accountedBytes: Int64,
        rootPath: String,
        directoryBytes: inout [String: Int64],
        directoryFileCounts: inout [String: Int]
    ) {
        for ancestor in ancestorPaths(for: url.deletingLastPathComponent().path, rootPath: rootPath) {
            directoryBytes[ancestor, default: 0] += accountedBytes
            directoryFileCounts[ancestor, default: 0] += 1
        }
    }

    private func addFolder(
        at url: URL,
        rootPath: String,
        directoryFolderCounts: inout [String: Int]
    ) {
        for ancestor in ancestorPaths(for: url.deletingLastPathComponent().path, rootPath: rootPath) {
            directoryFolderCounts[ancestor, default: 0] += 1
        }
    }

    private func ancestorPaths(for initialPath: String, rootPath: String) -> [String] {
        var current = URL(fileURLWithPath: initialPath).standardizedFileURL.path
        var result: [String] = []
        while FileSystemSafety.isPath(current, insideOrEqualTo: rootPath) {
            result.append(current)
            if current == rootPath { break }
            let parent = URL(fileURLWithPath: current).deletingLastPathComponent().standardizedFileURL.path
            guard parent != current else { break }
            current = parent
        }
        return result
    }
}

private struct ItemSeed {
    let url: URL
    let canonicalPath: String
    let kind: DiskItemKind
    let values: URLResourceValues
    let accountedBytes: Int64
    let qualifyingBytes: Int64
    let identity: FileIdentity?
    let enumerationRootPath: String
    let packageRootPath: String?
    let isHidden: Bool
}
