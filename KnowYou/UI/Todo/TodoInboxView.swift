import SwiftUI

struct TodoInboxView: View {
    let items: [UnifiedTodoItem]
    let automationStatusMessage: String?
    let onAdd: (String) -> Void
    let onComplete: (String) -> Void
    @State private var draftTitle = ""

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                HStack(alignment: .firstTextBaseline) {
                    Text("Todo")
                        .font(.title2.weight(.semibold))
                    Spacer()
                    Text("\(openItems.count) open")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.secondary)
                }

                if let automationStatusMessage {
                    Text(automationStatusMessage)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(.vertical, 6)
                }

                HStack(spacing: 8) {
                    TextField("New todo", text: $draftTitle)
                        .textFieldStyle(.roundedBorder)
                        .onSubmit(addDraft)
                    Button(action: addDraft) {
                        Image(systemName: "plus.circle.fill")
                            .frame(width: 18, height: 18)
                    }
                    .buttonStyle(.borderless)
                    .disabled(draftTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    .help("Add Todo")
                }
                .frame(maxWidth: 520)

                if openItems.isEmpty && completedItems.isEmpty {
                    ContentUnavailableView(
                        "No Todo Items",
                        systemImage: "checklist",
                        description: Text("Daily candidates can be added here when they are real tasks.")
                    )
                } else {
                    VStack(alignment: .leading, spacing: 10) {
                        ForEach(openItems) { item in
                            TodoInboxRow(item: item, onComplete: onComplete)
                        }
                    }

                    if !completedItems.isEmpty {
                        Divider()
                            .padding(.vertical, 6)

                        VStack(alignment: .leading, spacing: 10) {
                            Text("Completed")
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(.secondary)
                            ForEach(completedItems) { item in
                                TodoInboxRow(item: item, onComplete: onComplete)
                            }
                        }
                    }
                }
            }
            .padding(28)
            .frame(maxWidth: 760, alignment: .topLeading)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Color(nsColor: .textBackgroundColor))
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
                Image(systemName: item.status == .completed ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(
                        item.status == .completed
                            ? AnyShapeStyle(.secondary)
                            : AnyShapeStyle(Color.accentColor)
                    )
                    .frame(width: 18, height: 18)
            }
            .buttonStyle(.plain)
            .disabled(item.status == .completed)
            .help(item.status == .completed ? "Completed" : "Mark Complete")

            VStack(alignment: .leading, spacing: 4) {
                Text(item.title)
                    .font(.body)
                    .strikethrough(item.status == .completed, color: .secondary)
                    .foregroundStyle(item.status == .completed ? .secondary : .primary)
                HStack(spacing: 8) {
                    Text(item.sourceDayKey)
                    Text(item.promotionKind == .auto ? "auto" : "manual")
                    if let completionKind = item.completionKind {
                        Text(completionKind.rawValue)
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
    }
}
