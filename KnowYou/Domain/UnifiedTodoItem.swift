import Foundation

struct UnifiedTodoItem: Equatable, Identifiable, Codable, Sendable {
    enum Status: String, Codable, Sendable {
        case open
        case completed
    }

    enum PromotionKind: String, Codable, Sendable {
        case auto
        case manual
    }

    enum CompletionKind: String, Codable, Sendable {
        case manual
        case evidenceSweep = "evidence-sweep"
    }

    let id: String
    var title: String
    var normalizedTitle: String
    var status: Status
    var sourceDayKey: String
    var sourceEventIDs: [UUID]
    var createdAt: Date
    var completedAt: Date?
    var completionEvidenceEventIDs: [UUID]
    var promotionKind: PromotionKind
    var completionKind: CompletionKind?

    static func normalizeTitle(_ title: String) -> String {
        var value = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let taskPrefixes = ["- [ ]", "- [x]", "- [X]", "* [ ]", "* [x]", "* [X]"]
        for prefix in taskPrefixes where value.hasPrefix(prefix) {
            value = String(value.dropFirst(prefix.count))
                .trimmingCharacters(in: .whitespacesAndNewlines)
            break
        }
        value = value.replacingOccurrences(
            of: #"\s+"#,
            with: " ",
            options: .regularExpression
        )
        let trailingPunctuation = CharacterSet(charactersIn: ".。,，;；:：!！?？")
        while let last = value.unicodeScalars.last,
              trailingPunctuation.contains(last) {
            value.removeLast()
        }
        return value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }
}

struct DailyTodoCandidate: Equatable, Identifiable, Sendable {
    let id: String
    let title: String
    let normalizedTitle: String
    let sourceDayKey: String
    let sourceEventIDs: [UUID]
    let paragraphID: String

    static func extract(from story: DailyStory) -> [DailyTodoCandidate] {
        story.sections
            .flatMap(\.paragraphs)
            .filter(isTodoParagraph)
            .flatMap { paragraph in
                extract(from: paragraph, dayKey: story.dayKey)
            }
    }

    private static func isTodoParagraph(_ paragraph: DailyStoryParagraph) -> Bool {
        let id = paragraph.id.lowercased()
        guard id.contains("todo") == false else { return true }

        let text = paragraph.text
        return text.localizedCaseInsensitiveContains("# To-do")
            || text.contains("# 待办事项")
            || text.localizedCaseInsensitiveContains("todo")
    }

    private static func extract(from paragraph: DailyStoryParagraph, dayKey: String) -> [DailyTodoCandidate] {
        paragraph.text
            .components(separatedBy: .newlines)
            .compactMap { line -> DailyTodoCandidate? in
                let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
                guard trimmed.hasPrefix("- [ ]") || trimmed.hasPrefix("* [ ]") else {
                    return nil
                }

                let title = String(trimmed.dropFirst(5))
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                let normalizedTitle = UnifiedTodoItem.normalizeTitle(title)
                guard !title.isEmpty, !normalizedTitle.isEmpty else {
                    return nil
                }

                return DailyTodoCandidate(
                    id: "\(dayKey)|\(paragraph.id)|\(normalizedTitle)",
                    title: title,
                    normalizedTitle: normalizedTitle,
                    sourceDayKey: dayKey,
                    sourceEventIDs: paragraph.sourceEventIDs,
                    paragraphID: paragraph.id
                )
            }
    }
}

struct DailyTodoCandidatePresentation: Equatable, Identifiable, Sendable {
    let id: String
    let title: String
    let paragraphID: String
    let isTracked: Bool

    var statusTitle: String {
        isTracked ? "In Todo" : "Add to Todo"
    }

    static func make(
        candidates: [DailyTodoCandidate],
        trackedCandidateIDs: Set<String>
    ) -> [DailyTodoCandidatePresentation] {
        candidates.map { candidate in
            DailyTodoCandidatePresentation(
                id: candidate.id,
                title: candidate.title,
                paragraphID: candidate.paragraphID,
                isTracked: trackedCandidateIDs.contains(candidate.id)
            )
        }
    }
}

struct TodoReviewCandidatePresentation: Equatable, Identifiable, Sendable {
    let id: String
    let title: String
    let reason: String
    let confidence: TodoConfidence
    let action: TodoReconciliationDecision.Action
    let targetTodoID: String?

    var recommendedActionTitle: String {
        action == .merge ? "Merge" : "Add"
    }
}

struct TodoCloseRecommendationPresentation: Equatable, Identifiable, Sendable {
    var id: String { todoID }

    let todoID: String
    let title: String
    let reason: String
    let confidence: TodoConfidence
    let evidenceEventIDs: [UUID]
}
