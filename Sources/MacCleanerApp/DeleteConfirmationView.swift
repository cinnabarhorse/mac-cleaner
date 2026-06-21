import MacCleanerCore
import SwiftUI

struct DeleteConfirmationView: View {
    let item: DiskItem
    let isDeleting: Bool
    let onCancel: () -> Void
    let onConfirm: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                Image(systemName: "trash")
                    .font(.title)
                    .foregroundStyle(.red)

                VStack(alignment: .leading, spacing: 3) {
                    Text("Move to Trash?")
                        .font(.title2)
                        .fontWeight(.semibold)
                    Text(item.name)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }

            VStack(alignment: .leading, spacing: 8) {
                MetadataLine(label: "Size", value: ByteFormat.string(from: item.byteSize))
                MetadataLine(label: "Risk", value: item.risk.displayName)
                MetadataLine(label: "Path", value: item.path)
            }

            HStack {
                Spacer()

                Button("Cancel", action: onCancel)
                    .keyboardShortcut(.cancelAction)

                Button(role: .destructive, action: onConfirm) {
                    if isDeleting {
                        ProgressView()
                            .controlSize(.small)
                    } else {
                        Label("Move to Trash", systemImage: "trash")
                    }
                }
                .keyboardShortcut(.defaultAction)
                .disabled(isDeleting)
            }
        }
        .padding(24)
        .frame(width: 460)
    }
}

private struct MetadataLine: View {
    let label: String
    let value: String

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(label)
                .foregroundStyle(.secondary)
                .frame(width: 44, alignment: .leading)

            Text(value)
                .lineLimit(3)
                .truncationMode(.middle)
                .textSelection(.enabled)

            Spacer(minLength: 0)
        }
    }
}
