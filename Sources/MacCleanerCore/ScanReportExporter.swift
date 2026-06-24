import Foundation

public enum ScanReportExportFormat: String, CaseIterable, Identifiable, Sendable {
    case markdown
    case csv

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .markdown: "Markdown"
        case .csv: "CSV"
        }
    }

    public var fileExtension: String {
        switch self {
        case .markdown: "md"
        case .csv: "csv"
        }
    }
}

public enum ScanReportExporter {
    public static func export(_ report: ScanReport, as format: ScanReportExportFormat) -> String {
        switch format {
        case .markdown:
            markdown(for: report)
        case .csv:
            csv(for: report)
        }
    }

    private static func markdown(for report: ScanReport) -> String {
        var lines = [
            "# Mac Cleaner Scan Report",
            "",
            "- Finished: \(isoString(from: report.finishedAt))",
            "- Duration: \(String(format: "%.1f", report.duration)) seconds",
            "- Scanned: \(report.scannedItemCount) items",
            "- Visible bytes: \(report.totalBytes)",
            "- Issues: \(report.issues.count)",
            "",
            "| Size | Risk | Category | Kind | Path |",
            "| ---: | --- | --- | --- | --- |"
        ]

        lines.append(contentsOf: report.items.map { item in
            "| \(ByteFormat.string(from: item.byteSize)) | \(item.risk.displayName) | \(item.category.displayName) | \(item.kind.displayName) | \(escapeMarkdown(item.path)) |"
        })

        if !report.issues.isEmpty {
            lines.append(contentsOf: [
                "",
                "## Scan Issues",
                "",
                "| Path | Message |",
                "| --- | --- |"
            ])
            lines.append(contentsOf: report.issues.map { issue in
                "| \(escapeMarkdown(issue.path)) | \(escapeMarkdown(issue.message)) |"
            })
        }

        return lines.joined(separator: "\n") + "\n"
    }

    private static func csv(for report: ScanReport) -> String {
        let rows = [
            ["path", "name", "bytes", "size", "category", "risk", "kind", "files", "folders", "modified_at", "accessed_at", "root"]
        ] + report.items.map { item in
            [
                item.path,
                item.name,
                String(item.byteSize),
                ByteFormat.string(from: item.byteSize),
                item.category.displayName,
                item.risk.displayName,
                item.kind.displayName,
                String(item.fileCount),
                String(item.childFolderCount),
                item.modifiedAt.map(isoString) ?? "",
                item.lastAccessedAt.map(isoString) ?? "",
                item.rootPath
            ]
        }

        return rows
            .map { $0.map(csvEscape).joined(separator: ",") }
            .joined(separator: "\n") + "\n"
    }

    private static func isoString(from date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.string(from: date)
    }

    private static func escapeMarkdown(_ value: String) -> String {
        value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "|", with: "\\|")
            .replacingOccurrences(of: "\n", with: " ")
    }

    private static func csvEscape(_ value: String) -> String {
        let escapedValue = value.replacingOccurrences(of: "\"", with: "\"\"")
        if escapedValue.contains(",") || escapedValue.contains("\"") || escapedValue.contains("\n") {
            return "\"\(escapedValue)\""
        }

        return escapedValue
    }
}
