import Foundation

enum CodexJWT {
    private static let authClaimKey = "https://api.openai.com/auth"

    static func expiryDate(from token: String) -> Date? {
        guard
            let payload = payload(from: token),
            let expiry = payload["exp"] as? TimeInterval,
            expiry > 0
        else {
            return nil
        }
        return Date(timeIntervalSince1970: expiry)
    }

    static func accountID(from token: String) -> String? {
        guard
            let payload = payload(from: token),
            let auth = payload[authClaimKey] as? [String: Any],
            let accountID = auth["chatgpt_account_id"] as? String,
            !accountID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else {
            return nil
        }
        return accountID
    }

    private static func payload(from token: String) -> [String: Any]? {
        let parts = token.split(separator: ".")
        guard parts.count == 3 else {
            return nil
        }
        guard let data = Data(base64URLEncoded: String(parts[1])) else {
            return nil
        }
        return (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
    }
}

private extension Data {
    init?(base64URLEncoded value: String) {
        var base64 = value
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        let padding = (4 - base64.count % 4) % 4
        base64.append(String(repeating: "=", count: padding))
        self.init(base64Encoded: base64)
    }
}
