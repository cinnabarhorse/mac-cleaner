import Foundation

public typealias ScanProgressHandler = @Sendable (ScanProgress) async -> Void

public actor FileScanner {
    private let classifier: ItemClassifier

    public init(classifier: ItemClassifier = ItemClassifier()) {
        self.classifier = classifier
    }

    public func scan(
        roots rawRoots: [ScanRoot],
        options: ScanOptions = ScanOptions(),
        progress: ScanProgressHandler? = nil
    ) async throws -> ScanReport {
        let startedAt = Date()
        let fileManager = FileManager.default
        let roots = uniqueExistingRoots(from: rawRoots, fileManager: fileManager)
        var issues: [ScanIssue] = []
        var records: [DiskItem] = []
        var totalBytes: Int64 = 0
        var scannedItemCount = 0
        var scannedFileCount = 0
        var scannedFolderCount = 0

        for root in roots {
            try Task.checkCancellation()

            let rootPath = root.url.standardizedFileURL.path
            guard fileManager.fileExists(atPath: rootPath) else {
                issues.append(ScanIssue(path: rootPath, message: "Path does not exist."))
                continue
            }

            var seeds: [String: ItemSeed] = [:]
            var directoryBytes: [String: Int64] = [rootPath: 0]
            var directoryFileCounts: [String: Int] = [rootPath: 0]
            var directoryFolderCounts: [String: Int] = [rootPath: 0]

            await progress?(ScanProgress(
                currentPath: rootPath,
                scannedItemCount: scannedItemCount,
                scannedByteCount: totalBytes,
                partialReport: records.isEmpty ? nil : makeReport(
                    roots: roots,
                    items: records,
                    issues: issues,
                    totalBytes: totalBytes,
                    scannedItemCount: scannedItemCount,
                    scannedFileCount: scannedFileCount,
                    scannedFolderCount: scannedFolderCount,
                    startedAt: startedAt,
                    finishedAt: Date(),
                    isComplete: false,
                    options: options
                )
            ))

            do {
                let rootValues = try root.url.resourceValues(forKeys: resourceKeys)
                let rootKind = itemKind(from: rootValues)
                seeds[rootPath] = ItemSeed(url: root.url, kind: rootKind, values: rootValues, directBytes: 0)
            } catch {
                issues.append(ScanIssue(path: rootPath, message: error.localizedDescription))
            }

            var enumerationOptions: FileManager.DirectoryEnumerationOptions = []
            if !options.includeHiddenFiles {
                enumerationOptions.insert(.skipsHiddenFiles)
            }
            if !options.includePackageContents {
                enumerationOptions.insert(.skipsPackageDescendants)
            }

            guard let enumerator = fileManager.enumerator(
                at: root.url,
                includingPropertiesForKeys: Array(resourceKeys),
                options: enumerationOptions,
                errorHandler: { url, error in
                    issues.append(ScanIssue(path: url.path, message: error.localizedDescription))
                    return true
                }
            ) else {
                issues.append(ScanIssue(path: rootPath, message: "Unable to enumerate path."))
                continue
            }

            while let url = enumerator.nextObject() as? URL {
                try Task.checkCancellation()

                let path = url.standardizedFileURL.path
                do {
                    let values = try url.resourceValues(forKeys: resourceKeys)
                    let kind = itemKind(from: values)

                    if kind == .symbolicLink && !options.includeSymlinkTargets {
                        continue
                    }

                    if values.isHidden == true && !options.includeHiddenFiles {
                        continue
                    }

                    scannedItemCount += 1
                    let directBytes = allocatedSize(from: values)
                    seeds[path] = ItemSeed(url: url, kind: kind, values: values, directBytes: directBytes)

                    switch kind {
                    case .file, .symbolicLink:
                        scannedFileCount += 1
                        for ancestor in ancestorDirectoryPaths(for: url, rootPath: rootPath) {
                            directoryBytes[ancestor, default: 0] += directBytes
                            directoryFileCounts[ancestor, default: 0] += 1
                        }
                    case .folder, .package:
                        scannedFolderCount += 1
                        directoryBytes[path, default: 0] += 0
                        directoryFileCounts[path, default: 0] += 0
                        directoryFolderCounts[path, default: 0] += 0
                        for ancestor in ancestorDirectoryPaths(for: url, rootPath: rootPath) {
                            directoryFolderCounts[ancestor, default: 0] += 1
                        }
                    case .inaccessible:
                        break
                    }

                    if scannedItemCount.isMultiple(of: 100) {
                        let scannedBytes = totalBytes + (directoryBytes[rootPath] ?? 0)
                        let partialReport: ScanReport? = if scannedItemCount.isMultiple(of: options.snapshotItemInterval) {
                            snapshotReport(
                                roots: roots,
                                completedItems: records,
                                seeds: seeds,
                                directoryBytes: directoryBytes,
                                directoryFileCounts: directoryFileCounts,
                                directoryFolderCounts: directoryFolderCounts,
                                root: root,
                                rootPath: rootPath,
                                issues: issues,
                                totalBytes: scannedBytes,
                                scannedItemCount: scannedItemCount,
                                scannedFileCount: scannedFileCount,
                                scannedFolderCount: scannedFolderCount,
                                startedAt: startedAt,
                                options: options
                            )
                        } else {
                            nil
                        }

                        await progress?(ScanProgress(
                            currentPath: path,
                            scannedItemCount: scannedItemCount,
                            scannedByteCount: scannedBytes,
                            partialReport: partialReport
                        ))
                    }
                } catch {
                    issues.append(ScanIssue(path: path, message: error.localizedDescription))
                }
            }

            let rootBytes = directoryBytes[rootPath] ?? 0
            totalBytes += rootBytes
            records.append(contentsOf: items(
                from: seeds,
                directoryBytes: directoryBytes,
                directoryFileCounts: directoryFileCounts,
                directoryFolderCounts: directoryFolderCounts,
                root: root,
                rootPath: rootPath,
                options: options
            ))

            await progress?(ScanProgress(
                currentPath: rootPath,
                scannedItemCount: scannedItemCount,
                scannedByteCount: totalBytes,
                partialReport: makeReport(
                    roots: roots,
                    items: records,
                    issues: issues,
                    totalBytes: totalBytes,
                    scannedItemCount: scannedItemCount,
                    scannedFileCount: scannedFileCount,
                    scannedFolderCount: scannedFolderCount,
                    startedAt: startedAt,
                    finishedAt: Date(),
                    isComplete: false,
                    options: options
                )
            ))
        }

        return makeReport(
            roots: roots,
            items: records,
            issues: issues,
            totalBytes: totalBytes,
            scannedItemCount: scannedItemCount,
            scannedFileCount: scannedFileCount,
            scannedFolderCount: scannedFolderCount,
            startedAt: startedAt,
            finishedAt: Date(),
            options: options
        )
    }

    private func makeReport(
        roots: [ScanRoot],
        items rawItems: [DiskItem],
        issues: [ScanIssue],
        totalBytes: Int64,
        scannedItemCount: Int,
        scannedFileCount: Int,
        scannedFolderCount: Int,
        startedAt: Date,
        finishedAt: Date,
        isComplete: Bool = true,
        options: ScanOptions
    ) -> ScanReport {
        let items = deduplicated(rawItems)
            .sorted { lhs, rhs in
                if lhs.byteSize == rhs.byteSize {
                    return lhs.path.localizedStandardCompare(rhs.path) == .orderedAscending
                }
                return lhs.byteSize > rhs.byteSize
            }
            .prefix(options.maxReturnedItems)

        return ScanReport(
            roots: roots,
            items: Array(items),
            issues: issues,
            totalBytes: totalBytes,
            scannedItemCount: scannedItemCount,
            scannedFileCount: scannedFileCount,
            scannedFolderCount: scannedFolderCount,
            startedAt: startedAt,
            finishedAt: finishedAt,
            isComplete: isComplete
        )
    }

    private func snapshotReport(
        roots: [ScanRoot],
        completedItems: [DiskItem],
        seeds: [String: ItemSeed],
        directoryBytes: [String: Int64],
        directoryFileCounts: [String: Int],
        directoryFolderCounts: [String: Int],
        root: ScanRoot,
        rootPath: String,
        issues: [ScanIssue],
        totalBytes: Int64,
        scannedItemCount: Int,
        scannedFileCount: Int,
        scannedFolderCount: Int,
        startedAt: Date,
        options: ScanOptions
    ) -> ScanReport {
        let currentItems = items(
            from: seeds,
            directoryBytes: directoryBytes,
            directoryFileCounts: directoryFileCounts,
            directoryFolderCounts: directoryFolderCounts,
            root: root,
            rootPath: rootPath,
            options: options
        )

        return makeReport(
            roots: roots,
            items: completedItems + currentItems,
            issues: issues,
            totalBytes: totalBytes,
            scannedItemCount: scannedItemCount,
            scannedFileCount: scannedFileCount,
            scannedFolderCount: scannedFolderCount,
            startedAt: startedAt,
            finishedAt: Date(),
            isComplete: false,
            options: options
        )
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

    private func uniqueExistingRoots(from roots: [ScanRoot], fileManager: FileManager) -> [ScanRoot] {
        var seen: Set<String> = []
        var uniqueRoots: [ScanRoot] = []

        for root in roots {
            let path = root.url.standardizedFileURL.path
            guard seen.insert(path).inserted else {
                continue
            }

            uniqueRoots.append(root)
        }

        return uniqueRoots
    }

    private func items(
        from seeds: [String: ItemSeed],
        directoryBytes: [String: Int64],
        directoryFileCounts: [String: Int],
        directoryFolderCounts: [String: Int],
        root: ScanRoot,
        rootPath: String,
        options: ScanOptions
    ) -> [DiskItem] {
        seeds.compactMap { path, seed in
            let bytes: Int64
            let fileCount: Int
            let folderCount: Int

            switch seed.kind {
            case .file, .symbolicLink:
                bytes = seed.directBytes
                fileCount = 1
                folderCount = 0
            case .folder, .package:
                bytes = directoryBytes[path] ?? 0
                fileCount = directoryFileCounts[path] ?? 0
                folderCount = directoryFolderCounts[path] ?? 0
            case .inaccessible:
                bytes = 0
                fileCount = 0
                folderCount = 0
            }

            guard bytes >= options.minimumItemSizeBytes else {
                return nil
            }

            let classification = classifier.classify(url: seed.url, kind: seed.kind, root: root)
            let isRoot = path == rootPath

            return DiskItem(
                url: seed.url,
                kind: seed.kind,
                category: classification.category,
                risk: classification.risk,
                byteSize: bytes,
                fileCount: fileCount,
                childFolderCount: folderCount,
                modifiedAt: seed.values.contentModificationDate,
                lastAccessedAt: seed.values.contentAccessDate,
                rootPath: rootPath,
                isDeletableCandidate: classification.isDeletableCandidate && !isRoot
            )
        }
    }

    private func deduplicated(_ items: [DiskItem]) -> [DiskItem] {
        var byID: [DiskItem.ID: DiskItem] = [:]

        for item in items {
            guard let existing = byID[item.id] else {
                byID[item.id] = item
                continue
            }

            if shouldReplace(existing: existing, candidate: item) {
                byID[item.id] = item
            }
        }

        return Array(byID.values)
    }

    private func shouldReplace(existing: DiskItem, candidate: DiskItem) -> Bool {
        if existing.category == .other && candidate.category != .other {
            return true
        }

        if existing.risk == .protected && candidate.risk != .protected {
            return true
        }

        return candidate.byteSize > existing.byteSize
    }

    private func itemKind(from values: URLResourceValues) -> DiskItemKind {
        if values.isSymbolicLink == true {
            return .symbolicLink
        }

        if values.isDirectory == true {
            return values.isPackage == true ? .package : .folder
        }

        if values.isRegularFile == true {
            return .file
        }

        return .inaccessible
    }

    private func allocatedSize(from values: URLResourceValues) -> Int64 {
        let size = values.totalFileAllocatedSize
            ?? values.fileAllocatedSize
            ?? values.fileSize
            ?? 0

        return Int64(size)
    }

    private func ancestorDirectoryPaths(for url: URL, rootPath: String) -> [String] {
        let normalizedRoot = URL(fileURLWithPath: rootPath).standardizedFileURL.path
        var current = url.deletingLastPathComponent().standardizedFileURL.path
        var ancestors: [String] = []

        while isPath(current, insideOrEqualTo: normalizedRoot) {
            ancestors.append(current)

            if current == normalizedRoot {
                break
            }

            let next = URL(fileURLWithPath: current).deletingLastPathComponent().standardizedFileURL.path
            guard next != current else {
                break
            }

            current = next
        }

        return ancestors
    }

    private func isPath(_ path: String, insideOrEqualTo rootPath: String) -> Bool {
        path == rootPath || path.hasPrefix(rootPath + "/")
    }
}

private struct ItemSeed {
    let url: URL
    let kind: DiskItemKind
    let values: URLResourceValues
    let directBytes: Int64
}
