import Foundation

enum TodoConfidence: String, Equatable, Sendable {
    case high
    case medium
    case low
}

struct TodoReconciliationDecision: Equatable, Sendable {
    enum Action: String, Sendable {
        case create
        case merge
        case ignore
    }

    let candidateID: String
    let action: Action
    let confidence: TodoConfidence
    let targetTodoID: String?
    let reason: String
}

struct TodoReconciliationResult: Equatable, Sendable {
    let decisions: [TodoReconciliationDecision]
    let isDegraded: Bool

    var highConfidenceCreates: [TodoReconciliationDecision] {
        decisions.filter { $0.action == .create && $0.confidence == .high }
    }

    var highConfidenceMerges: [TodoReconciliationDecision] {
        decisions.filter { $0.action == .merge && $0.confidence == .high && $0.targetTodoID != nil }
    }
}

struct TodoReconciler: Sendable {
    let summarizer: (any SummaryGenerating)?

    init(summarizer: (any SummaryGenerating)?) {
        self.summarizer = summarizer
    }

    func reconcile(
        candidates: [DailyTodoCandidate],
        existingTodos: [UnifiedTodoItem],
        dayKey: String
    ) async throws -> TodoReconciliationResult {
        guard !candidates.isEmpty else {
            return TodoReconciliationResult(decisions: [], isDegraded: false)
        }
        guard let summarizer else {
            return TodoReconciliationResult(decisions: [], isDegraded: true)
        }

        do {
            let raw = try await summarizer.summarize(
                dayKey: dayKey,
                markdown: Self.prompt(candidates: candidates, existingTodos: existingTodos, dayKey: dayKey),
                context: .defaultBehavior
            )
            let payload = try Self.decodePayload(raw)
            let candidateIDs = Set(candidates.map(\.id))
            let todoIDs = Set(existingTodos.map(\.id))
            let decisions = payload.decisions.compactMap { item -> TodoReconciliationDecision? in
                guard candidateIDs.contains(item.candidateID),
                      let action = TodoReconciliationDecision.Action(rawValue: item.action),
                      let confidence = TodoConfidence(rawValue: item.confidence)
                else {
                    return nil
                }
                let targetTodoID = item.targetTodoID.flatMap { todoIDs.contains($0) ? $0 : nil }
                if action == .merge, targetTodoID == nil {
                    return nil
                }
                return TodoReconciliationDecision(
                    candidateID: item.candidateID,
                    action: action,
                    confidence: confidence,
                    targetTodoID: targetTodoID,
                    reason: item.reason
                )
            }
            return TodoReconciliationResult(decisions: decisions, isDegraded: false)
        } catch {
            return TodoReconciliationResult(decisions: [], isDegraded: true)
        }
    }

    private static func prompt(
        candidates: [DailyTodoCandidate],
        existingTodos: [UnifiedTodoItem],
        dayKey: String
    ) -> String {
        let candidateLines = candidates.map { candidate in
            """
            - candidateID: \(candidate.id)
              title: \(candidate.title)
              normalizedTitle: \(candidate.normalizedTitle)
              sourceEventIDs: \(candidate.sourceEventIDs.map(\.uuidString).joined(separator: ", "))
            """
        }.joined(separator: "\n")
        let todoLines = existingTodos.map { item in
            """
            - todoID: \(item.id)
              title: \(item.title)
              normalizedTitle: \(item.normalizedTitle)
              status: \(item.status.rawValue)
            """
        }.joined(separator: "\n")

        return """
        Decide how today's diary todo candidates should be reconciled into the app's unified Todo inbox for \(dayKey).

        Return strict JSON only:
        {
          "decisions": [
            {
              "candidateID": "...",
              "action": "create|merge|ignore",
              "confidence": "high|medium|low",
              "targetTodoID": null,
              "reason": "..."
            }
          ]
        }

        Rules:
        - Use create only for clear, actionable, unresolved tasks that remain useful across days.
        - Use merge when a candidate is semantically the same task as an existing open or completed todo.
        - Use ignore for vague suggestions, repeated completed tasks, generic reminders, or unsupported guesses.
        - Treat Codex, Xcode, branch, worktree, build, test, commit, and similar development-tool process notes as temporary noise unless they clearly represent a durable cross-day deliverable.
        - Prefer medium or low confidence for candidates that might be real but are too small, temporary, or already covered by a broader todo.
        - Only high confidence create or merge will be applied.

        Existing todos:
        \(todoLines.isEmpty ? "(none)" : todoLines)

        Today candidates:
        \(candidateLines)
        """
    }

    private static func decodePayload(_ raw: String) throws -> ReconciliationPayload {
        let data = try jsonObjectData(from: raw)
        return try JSONDecoder().decode(ReconciliationPayload.self, from: data)
    }
}

struct TodoCompletion: Equatable, Sendable {
    let todoID: String
    let confidence: TodoConfidence
    let evidenceEventIDs: [UUID]
    let reason: String
}

struct TodoCompletionSweepResult: Equatable, Sendable {
    let completions: [TodoCompletion]
    let isDegraded: Bool

    var highConfidenceCompletions: [TodoCompletion] {
        completions.filter { $0.confidence == .high }
    }

    var reviewRecommendations: [TodoCompletion] {
        completions.filter { $0.confidence != .high }
    }
}

struct TodoCompletionSweep: Sendable {
    let summarizer: (any SummaryGenerating)?

    init(summarizer: (any SummaryGenerating)?) {
        self.summarizer = summarizer
    }

    func sweep(
        openTodos: [UnifiedTodoItem],
        story: DailyStory,
        dayKey: String
    ) async throws -> TodoCompletionSweepResult {
        guard !openTodos.isEmpty else {
            return TodoCompletionSweepResult(completions: [], isDegraded: false)
        }
        guard let summarizer else {
            return TodoCompletionSweepResult(completions: [], isDegraded: true)
        }

        do {
            let raw = try await summarizer.summarize(
                dayKey: dayKey,
                markdown: Self.prompt(openTodos: openTodos, story: story, dayKey: dayKey),
                context: .defaultBehavior
            )
            let payload = try Self.decodePayload(raw)
            let todoIDs = Set(openTodos.map(\.id))
            let evidenceIDs = Set(story.sections.flatMap(\.paragraphs).flatMap(\.sourceEventIDs))
            let completions = payload.completed.compactMap { item -> TodoCompletion? in
                guard todoIDs.contains(item.todoID) else { return nil }
                guard let confidence = item.confidence.flatMap(TodoConfidence.init(rawValue:)) else {
                    return nil
                }
                let ids = item.evidenceEventIDs.compactMap(UUID.init(uuidString:))
                guard !ids.isEmpty, Set(ids).isSubset(of: evidenceIDs) else {
                    return nil
                }
                return TodoCompletion(
                    todoID: item.todoID,
                    confidence: confidence,
                    evidenceEventIDs: ids,
                    reason: item.reason
                )
            }
            return TodoCompletionSweepResult(completions: completions, isDegraded: false)
        } catch {
            return TodoCompletionSweepResult(completions: [], isDegraded: true)
        }
    }

    private static func prompt(openTodos: [UnifiedTodoItem], story: DailyStory, dayKey: String) -> String {
        let todoLines = openTodos.map { item in
            "- todoID: \(item.id)\n  title: \(item.title)"
        }.joined(separator: "\n")
        let evidenceLines = story.sections
            .flatMap(\.paragraphs)
            .map { paragraph in
                """
                - paragraphID: \(paragraph.id)
                  sourceEventIDs: \(paragraph.sourceEventIDs.map(\.uuidString).joined(separator: ", "))
                  text: \(paragraph.text)
                """
            }
            .joined(separator: "\n")

        return """
        Conservatively decide whether open todos have already been completed based on new diary evidence for \(dayKey).

        Return strict JSON only:
        {
          "completed": [
            {
              "todoID": "...",
              "confidence": "high|medium|low",
              "evidenceEventIDs": ["uuid"],
              "reason": "..."
            }
          ]
        }

        Rules:
        - Use high confidence only when the evidence clearly says the whole todo was already done, sent, submitted, confirmed, scheduled, or agreed.
        - Use medium confidence when the evidence suggests progress or partial completion, but a person should confirm before closing.
        - Use low confidence for weak possible matches; include them only when still useful for review.
        - Do not infer completion from related work, intention, planning, or vague progress.
        - Every completion must cite at least one evidenceEventID from the evidence below.

        Open todos:
        \(todoLines)

        Evidence:
        \(evidenceLines)
        """
    }

    private static func decodePayload(_ raw: String) throws -> CompletionPayload {
        let data = try jsonObjectData(from: raw)
        return try JSONDecoder().decode(CompletionPayload.self, from: data)
    }
}

private struct ReconciliationPayload: Decodable {
    let decisions: [ReconciliationDecisionPayload]
}

private struct ReconciliationDecisionPayload: Decodable {
    let candidateID: String
    let action: String
    let confidence: String
    let targetTodoID: String?
    let reason: String
}

private struct CompletionPayload: Decodable {
    let completed: [CompletionDecisionPayload]
}

private struct CompletionDecisionPayload: Decodable {
    let todoID: String
    let confidence: String?
    let evidenceEventIDs: [String]
    let reason: String
}

private func jsonObjectData(from raw: String) throws -> Data {
    let cleaned = raw
        .trimmingCharacters(in: .whitespacesAndNewlines)
        .replacingOccurrences(of: "```json", with: "")
        .replacingOccurrences(of: "```", with: "")
        .trimmingCharacters(in: .whitespacesAndNewlines)

    guard let start = cleaned.firstIndex(of: "{"),
          let end = cleaned.lastIndex(of: "}"),
          start <= end,
          let data = String(cleaned[start...end]).data(using: .utf8)
    else {
        throw DecodingError.dataCorrupted(
            DecodingError.Context(codingPath: [], debugDescription: "Missing JSON object")
        )
    }
    return data
}
