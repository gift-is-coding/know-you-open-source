import Foundation

enum UpdateChannel: Equatable {
    case direct
    case appStore
    case unknown
}

enum UpdateActionKind: Equatable {
    case installInApp
    case openAppStore
    case unavailable
}

struct AppVersion: Comparable, Equatable {
    let rawValue: String
    private let components: [Int]

    init(_ rawValue: String) {
        self.rawValue = rawValue
        self.components = rawValue
            .split(separator: ".")
            .map { Int($0) ?? 0 }
    }

    static func < (lhs: AppVersion, rhs: AppVersion) -> Bool {
        let count = max(lhs.components.count, rhs.components.count)
        for index in 0..<count {
            let left = index < lhs.components.count ? lhs.components[index] : 0
            let right = index < rhs.components.count ? rhs.components[index] : 0
            if left != right {
                return left < right
            }
        }
        return false
    }
}

struct UpdateOffer: Equatable {
    var availableVersion: String
    var releaseSummary: String?
    var publishedAt: Date?
    var actionKind: UpdateActionKind
    var storeURL: URL? = nil
    var downloadURL: URL? = nil

    var pillTitle: String {
        "Update \(availableVersion)"
    }

    var primaryActionTitle: String {
        switch actionKind {
        case .installInApp:
            return "Update Now"
        case .openAppStore:
            return "Open in App Store"
        case .unavailable:
            return "Unavailable"
        }
    }

    var actionDescription: String {
        switch actionKind {
        case .installInApp:
            return "This build updates from the official direct-download release."
        case .openAppStore:
            return "This build updates through the Mac App Store."
        case .unavailable:
            return "Automatic update actions are not configured for this build yet."
        }
    }

    var summaryText: String {
        let trimmedSummary = releaseSummary?
            .trimmingCharacters(in: .whitespacesAndNewlines)

        if let trimmedSummary, trimmedSummary.isEmpty == false {
            return trimmedSummary
        }

        return "This release includes improvements and fixes."
    }

    var publishedTimestampText: String? {
        guard let publishedAt else { return nil }
        return Self.publishedTimestampFormatter.string(from: publishedAt)
    }

    private static let publishedTimestampFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "Asia/Shanghai")
        formatter.dateFormat = "MM-dd HH:mm"
        return formatter
    }()
}
