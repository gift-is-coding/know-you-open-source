import Foundation

struct PrivacyFilterResult: Equatable {
    let action: PrivacyAction
    let persistedText: String?
    let auditText: String?
}

struct PrivacyFilter {
    private let sensitiveNumberPattern = #/\d{16,}/#

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

        let redacted = redactSensitiveNumbers(in: input)

        if redacted != input {
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

    private func redactSensitiveNumbers(in input: String) -> String {
        let matches = input.matches(of: sensitiveNumberPattern)

        guard !matches.isEmpty else {
            return input
        }

        var redacted = ""
        var currentIndex = input.startIndex

        for match in matches {
            redacted += input[currentIndex..<match.range.lowerBound]

            let digits = input[match.range]
            let suffix = digits.suffix(4)
            let maskedDigits = String(repeating: "*", count: digits.count - 4) + suffix
            redacted += maskedDigits

            currentIndex = match.range.upperBound
        }

        redacted += input[currentIndex...]
        return redacted
    }
}
