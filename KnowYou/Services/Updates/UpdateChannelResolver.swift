import Foundation

struct UpdateChannelResolver {
    var buildChannelOverride: String? = Bundle.main.object(forInfoDictionaryKey: "KYUpdateChannel") as? String

    func resolve() -> UpdateChannel {
        switch buildChannelOverride?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "direct":
            return .direct
        case "app-store", "appstore", "mas":
            return .appStore
        default:
            return .unknown
        }
    }
}
