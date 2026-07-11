import Foundation
import MacCleanerCore

public struct AccessibilityAnnouncement: Equatable, Sendable {
    public let id: UUID
    public let message: String

    public init(message: String, id: UUID = UUID()) {
        self.id = id
        self.message = message
    }
}

public enum CleanerActivity: Equatable, Sendable {
    case idle
    case scanning(generation: UInt64)
    case validating(itemID: DiskItem.ID)
    case revalidating(itemID: DiskItem.ID)
    case cancelingDeletion(itemID: DiskItem.ID)
    case movingToTrash(itemID: DiskItem.ID)

    public var isScanning: Bool {
        if case .scanning = self { true } else { false }
    }

    public var isMovingToTrash: Bool {
        if case .movingToTrash = self { true } else { false }
    }
}

public enum ReportViewState: Equatable, Sendable {
    case initialLoading
    case noReport
    case savedSnapshot(savedAt: Date, wasComplete: Bool)
    case livePartial
    case current
    case stopped
    case configurationChanged
    case staleAfterTrash
    case failed(message: String)

    public var isReadOnly: Bool {
        switch self {
        case .current:
            false
        case .initialLoading, .noReport, .savedSnapshot, .livePartial, .stopped, .configurationChanged, .staleAfterTrash, .failed:
            true
        }
    }
}

public enum DeletionFlow: Sendable {
    case verifying(DiskItem)
    case confirming(request: ValidatedTrashRequest, requiresSecondConfirmation: Bool)
    case revalidating(ValidatedTrashRequest)
    case moving(ValidatedTrashRequest)
    case blocked(item: DiskItem, message: String)

    public var item: DiskItem? {
        switch self {
        case .verifying(let item), .blocked(let item, _):
            item
        case .confirming, .revalidating, .moving:
            nil
        }
    }

    public var request: ValidatedTrashRequest? {
        switch self {
        case .confirming(let request, _), .revalidating(let request), .moving(let request):
            request
        case .verifying, .blocked:
            nil
        }
    }

    public var isMoving: Bool {
        if case .moving = self { true } else { false }
    }
}
