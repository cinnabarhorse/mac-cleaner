import MacCleanerCore
import SwiftUI

struct DeleteConfirmationView: View {
    let plan: DeletionPlan
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
                    Text(subtitle)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }

            VStack(alignment: .leading, spacing: 8) {
                MetadataLine(label: "Items", value: plan.items.count.formatted())
                MetadataLine(label: "Size", value: ByteFormat.string(from: plan.totalBytes))

                if let highestRisk = plan.highestRisk {
                    MetadataLine(label: "Risk", value: highestRisk.displayName)
                }

                if plan.items.count == 1, let item = plan.items.first {
                    MetadataLine(label: "Path", value: item.path)
                } else {
                    itemList
                }
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
                        Label(confirmTitle, systemImage: "trash")
                    }
                }
                .keyboardShortcut(.defaultAction)
                .disabled(isDeleting)
            }
        }
        .padding(24)
        .frame(width: 500)
    }

    private var subtitle: String {
        guard plan.items.count != 1 else {
            return plan.items.first?.name ?? "1 item"
        }

        return "\(plan.items.count.formatted()) items selected"
    }

    private var confirmTitle: String {
        guard plan.items.count != 1 else {
            return "Move to Trash"
        }

        return "Move \(plan.items.count.formatted()) to Trash"
    }

    private var itemList: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(plan.items.prefix(6)) { item in
                Text(item.path)
                    .font(.caption)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .textSelection(.enabled)
            }

            if plan.items.count > 6 {
                Text("\((plan.items.count - 6).formatted()) more")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
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
