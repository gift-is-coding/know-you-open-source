import Foundation

struct PrivacyFilterResult: Equatable {
    let action: PrivacyAction
    let persistedText: String?
    let auditText: String?
}

struct PrivacyFilter {
    func classify(_ input: String) -> PrivacyFilterResult {
        let lowered = input.lowercased()

        if lowered.contains("password")
            || lowered.contains("otp")
            || lowered.contains("api_key")
            || lowered.contains("session=") {
            return PrivacyFilterResult(
                action: .drop,
                persistedText: nil,
                auditText: "Sensitive content skipped"
            )
        }

        if let range = input.range(of: #"\d{16}"#, options: .regularExpression) {
            let suffix = input[range].suffix(4)
            let redacted = input.replacingCharacters(in: range, with: "************" + suffix)
            return PrivacyFilterResult(
                action: .redact,
                persistedText: redacted,
                auditText: "Sensitive content redacted"
            )
        }

        return PrivacyFilterResult(
            action: .keep,
            persistedText: input,
            auditText: nil
        )
    }
}
