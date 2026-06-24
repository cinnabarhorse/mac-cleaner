import Foundation

public enum ItemAgeFilter: Int, CaseIterable, Identifiable, Codable, Sendable {
    case any = 0
    case days30 = 30
    case days90 = 90
    case days180 = 180
    case days365 = 365

    public var id: Int { rawValue }

    public var displayName: String {
        switch self {
        case .any: "Any Age"
        case .days30: "30+ Days"
        case .days90: "90+ Days"
        case .days180: "180+ Days"
        case .days365: "1+ Year"
        }
    }

    public func includes(_ item: DiskItem, referenceDate: Date = Date()) -> Bool {
        guard self != .any else {
            return true
        }

        guard let lastActivityDate = item.lastActivityDate else {
            return false
        }

        return lastActivityDate <= referenceDate.addingTimeInterval(-Double(rawValue) * 86_400)
    }
}

public extension DiskItem {
    var lastActivityDate: Date? {
        [lastAccessedAt, modifiedAt].compactMap(\.self).max()
    }

    func ageInDays(referenceDate: Date = Date()) -> Int? {
        guard let lastActivityDate else {
            return nil
        }

        return max(0, Int(referenceDate.timeIntervalSince(lastActivityDate) / 86_400))
    }
}
