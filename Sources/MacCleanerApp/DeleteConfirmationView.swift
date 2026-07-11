import MacCleanerCore
import MacCleanerFeatures
import SwiftUI

struct DeleteConfirmationView: View {
    @Bindable var store: CleanerStore

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            header
            content
            buttons
        }
        .padding(24)
        .frame(width: 520)
        .accessibilityAddTraits(.isModal)
    }

    private var header: some View {
        HStack(spacing: 12) {
            Image(systemName: headerImage)
                .font(.title)
                .foregroundStyle(headerColor)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 3) {
                Text(headerTitle)
                    .font(.title2.weight(.semibold))
                Text(headerSubtitle)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
    }

    @ViewBuilder
    private var content: some View {
        switch store.deletionFlow {
        case let .verifying(item):
            progressContent("Checking identity, location, contents, and scan coverage for \(item.name)…")

        case let .confirming(request, requiresSecondConfirmation):
            confirmationContent(request.summary, changed: requiresSecondConfirmation)

        case .revalidating:
            progressContent("Checking that the item has not changed since confirmation…")

        case .moving:
            progressContent("The verified item is being moved to Trash. This operation can no longer be canceled.")

        case let .blocked(_, message):
            Label(message, systemImage: "hand.raised.fill")
                .foregroundStyle(.red)
                .fixedSize(horizontal: false, vertical: true)

        case nil:
            EmptyView()
        }
    }

    private func confirmationContent(
        _ summary: DeletionPreflightSummary,
        changed: Bool
    ) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            if changed {
                Label(
                    "The item changed after the first confirmation. Review these updated details and confirm again.",
                    systemImage: "arrow.triangle.2.circlepath"
                )
                .foregroundStyle(.orange)
                .fixedSize(horizontal: false, vertical: true)
            }

            VStack(alignment: .leading, spacing: 8) {
                MetadataLine(label: "Verified", value: ByteFormat.string(from: summary.verifiedByteSize))

                if summary.scannedByteSize != summary.verifiedByteSize {
                    MetadataLine(label: "Scan", value: ByteFormat.string(from: summary.scannedByteSize))
                    Label("The current size differs from the scan estimate.", systemImage: "exclamationmark.triangle")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }

                MetadataLine(label: "Contents", value: contentsDescription(summary))
                MetadataLine(label: "Risk", value: summary.risk.displayName)
                MetadataLine(label: "Why", value: summary.classificationRationale)
                MetadataLine(label: "Path", value: summary.url.path)
            }

            Text("The item will be moved to the macOS Trash and can be restored from there.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private func progressContent(_ message: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            ProgressView()
                .controlSize(.small)
            Text(message)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var buttons: some View {
        HStack {
            Spacer()

            if store.isMovingToTrash {
                Text("Moving to Trash…")
                    .foregroundStyle(.secondary)
            } else if case .blocked = store.deletionFlow {
                Button("Close") { store.dismissDeletion() }
                    .keyboardShortcut(.defaultAction)
            } else {
                Button("Cancel") { store.dismissDeletion() }
                    .keyboardShortcut(.cancelAction)
                    .disabled(!store.canDismissDeletion)

                if store.canConfirmDeletion {
                    Button(role: .destructive) {
                        store.confirmDeletion()
                    } label: {
                        Label("Move to Trash", systemImage: "trash")
                    }
                    .keyboardShortcut(.defaultAction)
                }
            }
        }
    }

    private var headerTitle: String {
        switch store.deletionFlow {
        case .verifying: "Verifying Item"
        case let .confirming(_, changed): changed ? "Item Changed" : "Move to Trash?"
        case .revalidating: "Final Safety Check"
        case .moving: "Moving to Trash"
        case .blocked: "Trash Operation Blocked"
        case nil: "Move to Trash"
        }
    }

    private var headerSubtitle: String {
        switch store.deletionFlow {
        case let .verifying(item), let .blocked(item, _): item.name
        case let .confirming(request, _), let .revalidating(request), let .moving(request):
            request.summary.url.lastPathComponent
        case nil: ""
        }
    }

    private var headerImage: String {
        switch store.deletionFlow {
        case .blocked: "hand.raised.fill"
        case .verifying, .revalidating: "checkmark.shield"
        case .confirming, .moving, nil: "trash"
        }
    }

    private var headerColor: Color {
        if case .blocked = store.deletionFlow { .red } else { .orange }
    }

    private func contentsDescription(_ summary: DeletionPreflightSummary) -> String {
        "\(summary.fileCount.formatted()) file\(summary.fileCount == 1 ? "" : "s"), \(summary.folderCount.formatted()) folder\(summary.folderCount == 1 ? "" : "s")"
    }
}

private struct MetadataLine: View {
    let label: String
    let value: String

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(label)
                .foregroundStyle(.secondary)
                .frame(width: 68, alignment: .leading)
            Text(value)
                .lineLimit(4)
                .truncationMode(.middle)
                .textSelection(.enabled)
            Spacer(minLength: 0)
        }
    }
}
