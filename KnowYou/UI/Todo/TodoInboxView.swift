import SwiftUI

enum TodoInboxCopy {
    static let draftPlaceholder = "+ Add a task to keep tracking across days"
    static let candidatesTitle = "Candidates"
    static let readyToCloseTitle = "Ready to close"

    static var visibleStrings: [String] {
        [
            draftPlaceholder,
            candidatesTitle,
            readyToCloseTitle,
        ]
    }
}

struct TodoAutomationPresentation: Equatable {
    let title = "Todo automation"
    let nextUpdateTitle = "Next update"
    let nextUpdateValue: String
    let lastUpdateTitle = "Last update"
    let lastUpdateValue: String
    let updateNowTitle: String
    let isUpdateNowDisabled: Bool
    let statusMessage: String?

    init(
        nextUpdateDate: Date?,
        lastUpdateDate: Date?,
        statusMessage: String?,
        isUpdating: Bool = false,
        displayTimeZone: TimeZone = .current
    ) {
        nextUpdateValue = nextUpdateDate.map { Self.timeText(for: $0, timeZone: displayTimeZone) } ?? "After Diary"
        lastUpdateValue = lastUpdateDate.map { Self.timeText(for: $0, timeZone: displayTimeZone) } ?? "Not updated yet"
        updateNowTitle = isUpdating ? "Updating..." : "Update Now"
        isUpdateNowDisabled = isUpdating
        self.statusMessage = isUpdating ? "Updating Todo..." : statusMessage
    }

    private static func timeText(for date: Date, timeZone: TimeZone) -> String {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        formatter.dateStyle = .none
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = timeZone
        return formatter.string(from: date)
            .replacingOccurrences(of: "\u{202F}", with: " ")
            .replacingOccurrences(of: "\u{00A0}", with: " ")
    }
}

struct TodoInboxView: View {
    let items: [UnifiedTodoItem]
    let reviewCandidates: [TodoReviewCandidatePresentation]
    let closeRecommendations: [TodoCloseRecommendationPresentation]
    let automationStatusMessage: String?
    let nextUpdateDate: Date?
    let lastUpdateDate: Date?
    let isUpdating: Bool
    let onAdd: (String) -> Void
    let onAddCandidate: (String) -> Void
    let onDismissCandidate: (String) -> Void
    let onComplete: (String) -> Void
    let onCloseRecommendation: (String) -> Void
    let onKeepRecommendation: (String) -> Void
    let onUpdateNow: () -> Void
    @State private var draftTitle = ""
    @State private var showCompleted = true

    var body: some View {
        HStack(spacing: 0) {
            mainList
            Divider()
            inboxList
                .frame(width: 340)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(nsColor: .textBackgroundColor))
    }

    private var mainList: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                HStack(alignment: .firstTextBaseline) {
                    Text("Todo")
                        .font(.title2.weight(.semibold))
                    Spacer()
                    Text("Vault/Todo.md")
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                }

                if let automationStatusMessage {
                    Text(automationStatusMessage)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                automationSchedule

                HStack(spacing: 8) {
                    TextField(TodoInboxCopy.draftPlaceholder, text: $draftTitle)
                        .textFieldStyle(.roundedBorder)
                        .onSubmit(addDraft)
                    Button("Add", action: addDraft)
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)
                        .disabled(draftTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }

                TodoSectionHeader(title: "Open", detail: "\(openItems.count) items")

                if openItems.isEmpty {
                    Text("No open todo items.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .padding(.vertical, 12)
                } else {
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(openItems) { item in
                            TodoInboxRow(item: item, onComplete: onComplete)
                        }
                    }
                }

                if !completedItems.isEmpty {
                    DisclosureGroup(isExpanded: $showCompleted) {
                        VStack(alignment: .leading, spacing: 0) {
                            ForEach(completedItems) { item in
                                TodoInboxRow(item: item, onComplete: onComplete)
                            }
                        }
                        .padding(.top, 4)
                    } label: {
                        TodoSectionHeader(title: "Completed", detail: "\(completedItems.count) items")
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(28)
            .frame(maxWidth: 760, alignment: .topLeading)
        }
    }

    private var inboxList: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Text("Inbox")
                    .font(.headline)
                    .padding(.top, 2)

                TodoInboxPanel(title: TodoInboxCopy.candidatesTitle, count: reviewCandidates.count) {
                    if reviewCandidates.isEmpty {
                        TodoInboxEmptyText("No candidates.")
                    } else {
                        ForEach(reviewCandidates) { candidate in
                            TodoReviewCandidateRow(
                                candidate: candidate,
                                onAdd: onAddCandidate,
                                onDismiss: onDismissCandidate
                            )
                        }
                    }
                }

                TodoInboxPanel(title: TodoInboxCopy.readyToCloseTitle, count: closeRecommendations.count) {
                    if closeRecommendations.isEmpty {
                        TodoInboxEmptyText("No close recommendations.")
                    } else {
                        ForEach(closeRecommendations) { recommendation in
                            TodoCloseRecommendationRow(
                                recommendation: recommendation,
                                onClose: onCloseRecommendation,
                                onKeep: onKeepRecommendation
                            )
                        }
                    }
                }
            }
            .padding(18)
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .background(Color(nsColor: .controlBackgroundColor))
    }

    private var automationSchedule: some View {
        let presentation = TodoAutomationPresentation(
            nextUpdateDate: nextUpdateDate,
            lastUpdateDate: lastUpdateDate,
            statusMessage: automationStatusMessage,
            isUpdating: isUpdating
        )
        return HStack(alignment: .center, spacing: 14) {
            Label(presentation.title, systemImage: "checklist")
                .font(.headline)

            Spacer(minLength: 10)

            VStack(alignment: .trailing, spacing: 3) {
                Text(presentation.lastUpdateTitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(presentation.lastUpdateValue)
                    .font(.callout.weight(.semibold))
            }

            VStack(alignment: .trailing, spacing: 3) {
                Text(presentation.nextUpdateTitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(presentation.nextUpdateValue)
                    .font(.callout.weight(.semibold))
            }

            Button(presentation.updateNowTitle, action: onUpdateNow)
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .disabled(presentation.isUpdateNowDisabled)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 8))
    }

    private var openItems: [UnifiedTodoItem] {
        items.filter { $0.status == .open }
    }

    private var completedItems: [UnifiedTodoItem] {
        items.filter { $0.status == .completed }
    }

    private func addDraft() {
        let title = draftTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { return }
        onAdd(title)
        draftTitle = ""
    }
}

private struct TodoSectionHeader: View {
    let title: String
    let detail: String

    var body: some View {
        HStack {
            Text(title)
                .font(.subheadline.weight(.semibold))
            Spacer()
            Text(detail)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.bottom, 6)
        .overlay(alignment: .bottom) {
            Divider()
        }
    }
}

private struct TodoInboxRow: View {
    let item: UnifiedTodoItem
    let onComplete: (String) -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Button {
                if item.status == .open {
                    onComplete(item.id)
                }
            } label: {
                Image(systemName: item.status == .completed ? "checkmark.square.fill" : "square")
                    .foregroundStyle(item.status == .completed ? .secondary : Color.accentColor)
                    .frame(width: 18, height: 18)
            }
            .buttonStyle(.plain)
            .disabled(item.status == .completed)
            .help(item.status == .completed ? "Completed" : "Complete")

            VStack(alignment: .leading, spacing: 3) {
                Text(item.title)
                    .font(.body)
                    .strikethrough(item.status == .completed, color: .secondary)
                    .foregroundStyle(item.status == .completed ? .secondary : .primary)
                    .lineLimit(3)
                HStack(spacing: 8) {
                    Text(item.sourceDayKey)
                    Text(item.promotionKind.rawValue)
                    if let completionKind = item.completionKind {
                        Text(completionKind.rawValue)
                    }
                }
                .font(.caption.monospaced())
                .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 8)
        .overlay(alignment: .bottom) {
            Divider().opacity(0.7)
        }
    }
}

private struct TodoInboxPanel<Content: View>: View {
    let title: String
    let count: Int
    let content: Content

    init(title: String, count: Int, @ViewBuilder content: () -> Content) {
        self.title = title
        self.count = count
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text(title)
                    .font(.caption.weight(.semibold))
                Spacer()
                Text("\(count)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 9)

            Divider()
            content
        }
        .background(Color(nsColor: .textBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 7))
        .overlay {
            RoundedRectangle(cornerRadius: 7)
                .stroke(Color(nsColor: .separatorColor).opacity(0.45), lineWidth: 1)
        }
    }
}

private struct TodoReviewCandidateRow: View {
    let candidate: TodoReviewCandidatePresentation
    let onAdd: (String) -> Void
    let onDismiss: (String) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(candidate.title)
                .font(.caption)
                .foregroundStyle(.primary)
                .lineLimit(3)
            Text("\(candidate.confidence.rawValue) · \(candidate.reason)")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(2)
            HStack(spacing: 6) {
                Button(candidate.recommendedActionTitle) {
                    onAdd(candidate.id)
                }
                .controlSize(.mini)
                Button("Dismiss") {
                    onDismiss(candidate.id)
                }
                .controlSize(.mini)
            }
        }
        .padding(10)
        .overlay(alignment: .bottom) {
            Divider().opacity(0.7)
        }
    }
}

private struct TodoCloseRecommendationRow: View {
    let recommendation: TodoCloseRecommendationPresentation
    let onClose: (String) -> Void
    let onKeep: (String) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(recommendation.title)
                .font(.caption)
                .foregroundStyle(.primary)
                .lineLimit(3)
            Text("\(recommendation.confidence.rawValue) · \(recommendation.reason)")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(2)
            HStack(spacing: 6) {
                Button("Close") {
                    onClose(recommendation.todoID)
                }
                .controlSize(.mini)
                Button("Keep") {
                    onKeep(recommendation.todoID)
                }
                .controlSize(.mini)
            }
        }
        .padding(10)
        .overlay(alignment: .bottom) {
            Divider().opacity(0.7)
        }
    }
}

private struct TodoInboxEmptyText: View {
    let text: String

    init(_ text: String) {
        self.text = text
    }

    var body: some View {
        Text(text)
            .font(.caption)
            .foregroundStyle(.secondary)
            .padding(10)
    }
}
