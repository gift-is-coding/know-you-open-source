import SwiftUI

struct DailyMarkdownView: View {
    let story: DailyStory?
    let selectedParagraphID: String?
    let onSelectParagraph: (String) -> Void
    let onMoveSelection: (Int) -> Void

    var body: some View {
        Group {
            if let story, story.sections.flatMap(\.paragraphs).isEmpty == false {
                ScrollView {
                    VStack(alignment: .leading, spacing: 28) {
                        ForEach(story.sections) { section in
                            if !section.paragraphs.isEmpty {
                                VStack(alignment: .leading, spacing: 14) {
                                    Text(section.title)
                                        .font(.title3.weight(.semibold))
                                        .foregroundStyle(.secondary)

                                    ForEach(section.paragraphs) { paragraph in
                                        Button {
                                            onSelectParagraph(paragraph.id)
                                        } label: {
                                            VStack(alignment: .leading, spacing: 10) {
                                                Text(paragraph.text)
                                                    .font(.body)
                                                    .multilineTextAlignment(.leading)
                                                    .frame(maxWidth: .infinity, alignment: .leading)

                                                Text("\(paragraph.sourceEventIDs.count) linked source\(paragraph.sourceEventIDs.count == 1 ? "" : "s")")
                                                    .font(.caption)
                                                    .foregroundStyle(.secondary)
                                            }
                                            .padding(18)
                                            .background(paragraph.id == selectedParagraphID ? selectedBackground : normalBackground)
                                            .overlay(
                                                RoundedRectangle(cornerRadius: 18, style: .continuous)
                                                    .stroke(paragraph.id == selectedParagraphID ? Color.accentColor.opacity(0.6) : Color.primary.opacity(0.08), lineWidth: 1)
                                            )
                                            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                                        }
                                        .buttonStyle(.plain)
                                    }
                                }
                            }
                        }
                    }
                    .padding(.horizontal, 28)
                    .padding(.vertical, 24)
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                }
                .background(Color(nsColor: .textBackgroundColor))
                .onMoveCommand { direction in
                    switch direction {
                    case .down:
                        onMoveSelection(1)
                    case .up:
                        onMoveSelection(-1)
                    default:
                        break
                    }
                }
            } else {
                ContentUnavailableView("No Story Yet", systemImage: "text.book.closed")
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var normalBackground: Color {
        Color(nsColor: .controlBackgroundColor)
    }

    private var selectedBackground: Color {
        Color.accentColor.opacity(0.12)
    }
}

struct StorySourceDetailView: View {
    let selectedParagraph: DailyStoryParagraph?
    let selectedEvents: [EventRecord]
    let allEvents: [EventRecord]
    @State private var showAllSources = false

    var body: some View {
        Group {
            if selectedParagraph != nil || !allEvents.isEmpty {
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Sources")
                                .font(.title3.weight(.semibold))

                            if let selectedParagraph {
                                Text(selectedParagraph.text)
                                    .font(.callout)
                                    .foregroundStyle(.secondary)
                            } else {
                                Text("Select a story paragraph to inspect the original source items.")
                                    .font(.callout)
                                    .foregroundStyle(.secondary)
                            }
                        }

                        if selectedEvents.isEmpty {
                            Text("No linked sources for this paragraph.")
                                .font(.callout)
                                .foregroundStyle(.secondary)
                        } else {
                            VStack(alignment: .leading, spacing: 12) {
                                ForEach(selectedEvents, id: \.id) { event in
                                    SourceEventCard(event: event)
                                }
                            }
                        }

                        DisclosureGroup(isExpanded: $showAllSources) {
                            VStack(alignment: .leading, spacing: 12) {
                                ForEach(allEvents, id: \.id) { event in
                                    SourceEventCard(event: event)
                                }
                            }
                            .padding(.top, 12)
                        } label: {
                            Text("View All Sources")
                                .font(.callout.weight(.medium))
                        }
                        .disabled(allEvents.isEmpty)
                    }
                    .padding(.horizontal, 22)
                    .padding(.vertical, 20)
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                }
                .background(Color(nsColor: .controlBackgroundColor))
            } else {
                ContentUnavailableView("No Sources Loaded", systemImage: "tray")
            }
        }
        .frame(minWidth: 320, idealWidth: 360, maxWidth: 420, maxHeight: .infinity)
    }
}

private struct SourceEventCard: View {
    let event: EventRecord

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text(timeText)
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                Text(event.sourceApp)
                    .font(.callout.weight(.semibold))
                Spacer(minLength: 8)
                Text(event.sourceType.rawValue.capitalized)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
            }

            Text(event.text ?? event.auditText ?? "")
                .font(.body)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(14)
        .background(Color(nsColor: .textBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private var timeText: String {
        Self.formatter.string(from: event.capturedAt)
    }

    private static let formatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        return formatter
    }()
}
