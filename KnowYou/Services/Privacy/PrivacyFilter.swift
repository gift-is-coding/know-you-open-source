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
            || lowered.contains("session=")
            || lowered.contains("secret")
            || lowered.contains("token")
            || lowered.contains("bearer")
            || lowered.contains("private_key")
            || lowered.contains("begin private key")
            || lowered.contains("-----begin") {
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

struct DiarySharePayload: Equatable {
    let dayKey: String
    let sourceTitle: String
    let body: String
    let mode: DiaryShareMode
    let downloadURL: URL
}

enum DiaryShareMode: Equatable {
    case redacted
    case original
}

enum DiaryShareSource: Equatable {
    case fullStory(DailyStory)
    case paragraph(DailyStoryParagraph, dayKey: String)
}

struct DiaryShareContentBuilder {
    static let defaultDownloadURL = URL(string: "https://giiift.site/know-you/download")!

    private let redactor: DiaryShareRedactor
    private let downloadURL: URL

    init(
        redactor: DiaryShareRedactor = DiaryShareRedactor(),
        downloadURL: URL = Self.defaultDownloadURL
    ) {
        self.redactor = redactor
        self.downloadURL = downloadURL
    }

    func payload(source: DiaryShareSource, redacted: Bool) -> DiarySharePayload? {
        let dayKey: String
        let sourceTitle: String
        let originalBody: String

        switch source {
        case .fullStory(let story):
            dayKey = story.dayKey
            sourceTitle = "Full diary"
            originalBody = story.sections
                .flatMap(\.paragraphs)
                .map(\.text)
                .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
                .joined(separator: "\n\n")
        case .paragraph(let paragraph, let paragraphDayKey):
            dayKey = paragraphDayKey
            sourceTitle = "Diary excerpt"
            originalBody = paragraph.text.trimmingCharacters(in: .whitespacesAndNewlines)
        }

        guard originalBody.isEmpty == false else { return nil }

        return DiarySharePayload(
            dayKey: dayKey,
            sourceTitle: sourceTitle,
            body: redacted ? redactor.redact(originalBody) : originalBody,
            mode: redacted ? .redacted : .original,
            downloadURL: downloadURL
        )
    }
}

struct DiaryShareRedactor {
    func redact(_ text: String) -> String {
        var redacted = text
        redacted = replace(pattern: #"(?is)-----BEGIN[^-]+PRIVATE KEY-----.*?-----END[^-]+PRIVATE KEY-----"#, in: redacted, with: "[secret block]")
        redacted = replace(pattern: #"(?i)\b([A-Z0-9._%+-]+)@([A-Z0-9.-]+\.[A-Z]{2,})\b"#, in: redacted, with: "[email]")
        redacted = replace(pattern: #"(?i)\b(password|passcode|token|secret|api[_ -]?key|bearer)\b\s*[:=]\s*\S+"#, in: redacted, with: "$1: [secret]")
        redacted = replace(pattern: #"\b\d{11,}\b"#, in: redacted, with: "[number]")
        redacted = replace(pattern: #"(https?://[^\s?#]+)(?:\?[^\s#]*)?(?:#[^\s]*)?"#, in: redacted, with: "$1")
        return redacted
    }

    private func replace(pattern: String, in text: String, with template: String) -> String {
        guard let expression = try? NSRegularExpression(pattern: pattern) else {
            return text
        }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        return expression.stringByReplacingMatches(
            in: text,
            options: [],
            range: range,
            withTemplate: template
        )
    }
}
