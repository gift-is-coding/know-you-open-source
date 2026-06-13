import SwiftUI
import AppKit
import CoreImage

struct DailyMarkdownView: View {
    let story: DailyStory?
    let selectedParagraphID: String?
    let dayKey: String?
    let refreshJob: DayRefreshJob?
    let refreshLogNotice: String?
    let isGenerating: Bool
    let isActive: Bool
    let searchQuery: String?
    let todoCandidates: [DailyTodoCandidatePresentation]
    let onSelectParagraph: (String) -> Void
    let onFocusStory: () -> Void
    let onAddTodoCandidate: (String) -> Void
    let onRefresh: () -> Void
    let onTodayFullRefresh: () -> Void
    var onShareDiary: (Bool, DiaryShareAction) -> Bool = { _, _ in false }
    var onShareParagraph: (DailyStoryParagraph, Bool, DiaryShareAction) -> Bool = { _, _, _ in false }
    let canFullRefresh: Bool
    let fullRefreshMenuTitle: String

    @State private var hoveredParagraphID: String?
    @State private var showsSharePopover = false
    @State private var shareRedacted = true
    @State private var shareRequest: DiaryShareRequest = .fullStory
    @State private var shareCopyFeedbackMessage: String?
    @State private var shareCopyFeedbackSucceeded = true
    @State private var shareToast: DiaryShareToast?

    var body: some View {
        let presentation = DailyMarkdownPresentation(
            story: story,
            selectedParagraphID: selectedParagraphID,
            isGenerating: isGenerating,
            searchQuery: searchQuery
        )
        let sharePresentation = DiarySharePresentation(story: story, redacted: shareRedacted)
        let refreshPresentation = DayRefreshProgressPresentation(refreshJob: refreshJob)

        Group {
            if presentation.showsEmptyState == false {
                ScrollViewReader { proxy in
                    ScrollView {
                        VStack(alignment: .leading, spacing: 0) {
                            // Date header row
                            VStack(alignment: .leading, spacing: 10) {
                                HStack(alignment: .firstTextBaseline) {
                                    Text(formattedDayKey)
                                        .font(.title2.weight(.semibold))
                                        .foregroundStyle(.secondary)
                                    Spacer()
                                    VStack(alignment: .trailing, spacing: 6) {
                                        HStack(spacing: 6) {
                                            Button {
                                                openFullStorySharePopover()
                                            } label: {
                                                ShareToolbarLabel(presentation: sharePresentation)
                                            }
                                            .buttonStyle(.plain)
                                            .disabled(!sharePresentation.canShare || dayKey == OnboardingDemoStory.demoDayKey)
                                            .help(sharePresentation.disabledReason ?? sharePresentation.modeTitle)

                                            Button {
                                                onRefresh()
                                            } label: {
                                                if isRefreshing {
                                                    ProgressView()
                                                        .controlSize(.small)
                                                } else {
                                                    Image(systemName: "arrow.clockwise")
                                                        .foregroundStyle(.secondary)
                                                }
                                            }
                                            .buttonStyle(.plain)
                                            .disabled(isRefreshing || dayKey == OnboardingDemoStory.demoDayKey)
                                            .help(dayKey == OnboardingDemoStory.demoDayKey ? "Demo Day is read-only" : "Regenerate this day's journal")

                                            Menu {
                                                Button(fullRefreshMenuTitle) {
                                                    onTodayFullRefresh()
                                                }
                                                .disabled(isRefreshing || !canFullRefresh)
                                            } label: {
                                                Image(systemName: "chevron.down")
                                                    .font(.caption2.weight(.semibold))
                                                    .foregroundStyle(.secondary)
                                            }
                                            .menuStyle(.borderlessButton)
                                            .menuIndicator(.hidden)
                                            .fixedSize()
                                            .help(canFullRefresh
                                                ? "Run a full refresh in 50-event batches"
                                                : "Full refresh is unavailable for Demo Day")
                                        }

                                        if refreshPresentation.showsSteps {
                                            VStack(alignment: .trailing, spacing: 4) {
                                                ForEach(refreshPresentation.steps) { step in
                                                    HStack(spacing: 6) {
                                                        Image(systemName: step.symbolName)
                                                            .font(.caption2)
                                                            .foregroundStyle(step.color)
                                                        Text(step.title)
                                                            .font(.caption)
                                                            .foregroundStyle(step.color)
                                                    }
                                                    .frame(maxWidth: 220, alignment: .trailing)
                                                }

                                                if let currentDetail = refreshPresentation.currentDetail {
                                                    Text(currentDetail)
                                                        .font(.caption)
                                                        .foregroundStyle(.secondary)
                                                        .multilineTextAlignment(.trailing)
                                                        .frame(maxWidth: 220, alignment: .trailing)
                                                }

                                                if let refreshLogNotice {
                                                    Text(refreshLogNotice)
                                                        .font(.caption2)
                                                        .foregroundStyle(.secondary)
                                                        .multilineTextAlignment(.trailing)
                                                        .frame(maxWidth: 220, alignment: .trailing)
                                                }
                                            }
                                        } else if let summaryText = refreshPresentation.summaryText {
                                            VStack(alignment: .trailing, spacing: 4) {
                                                Text(summaryText)
                                                    .font(.caption)
                                                    .foregroundStyle(refreshPresentation.summaryColor)
                                                    .multilineTextAlignment(.trailing)
                                                    .frame(maxWidth: 220, alignment: .trailing)

                                                if let refreshLogNotice {
                                                    Text(refreshLogNotice)
                                                        .font(.caption2)
                                                        .foregroundStyle(.secondary)
                                                        .multilineTextAlignment(.trailing)
                                                        .frame(maxWidth: 220, alignment: .trailing)
                                                }
                                            }
                                        } else if let refreshLogNotice {
                                            Text(refreshLogNotice)
                                                .font(.caption2)
                                                .foregroundStyle(.secondary)
                                                .multilineTextAlignment(.trailing)
                                                .frame(maxWidth: 220, alignment: .trailing)
                                        }
                                    }
                                }

                            }
                            .padding(.horizontal, 28)
                            .padding(.top, 24)
                            .padding(.bottom, 16)
                            .onChange(of: sharePresentation.canShare) { _, canShare in
                                if !canShare {
                                    showsSharePopover = false
                                }
                            }
                            .onChange(of: dayKey) { _, _ in
                                showsSharePopover = false
                                shareRedacted = true
                                shareRequest = .fullStory
                                shareCopyFeedbackMessage = nil
                                shareCopyFeedbackSucceeded = true
                            }
                            .onChange(of: showsSharePopover) { _, isShowing in
                                if !isShowing {
                                    shareCopyFeedbackMessage = nil
                                    shareCopyFeedbackSucceeded = true
                                }
                            }

                            Divider()
                                .padding(.horizontal, 28)

                            VStack(alignment: .leading, spacing: 0) {
                                Text(presentation.storyHeading)
                                    .font(.title3.weight(.semibold))
                                    .foregroundStyle(.primary)
                                    .padding(.horizontal, 14)
                                    .padding(.top, 4)
                                    .padding(.bottom, 16)

                                ForEach(presentation.paragraphs) { paragraph in
                                    paragraphRow(paragraph)
                                        .id(paragraph.id)
                                }
                            }
                            .padding(.horizontal, 28)
                            .padding(.top, 16)
                            .padding(.bottom, 24)
                        }
                        .frame(maxWidth: .infinity, alignment: .topLeading)
                    }
                    .background(Color(nsColor: .textBackgroundColor))
                    .task(id: presentation.scrollRequest) {
                        await scrollToParagraphIfNeeded(
                            presentation.scrollTargetParagraphID,
                            using: proxy
                        )
                    }
                }
            } else {
                ContentUnavailableView(
                    presentation.emptyStateTitle,
                    systemImage: presentation.emptyStateSymbol,
                    description: presentation.emptyStateMessage.map(Text.init)
                )
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .popover(isPresented: $showsSharePopover, arrowEdge: .top) {
            sharePopover(sharePresentation)
        }
        .overlay(alignment: .topTrailing) {
            if let shareToast {
                diaryShareToast(shareToast)
                    .padding(.top, 18)
                    .padding(.trailing, 26)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .animation(.easeOut(duration: 0.18), value: shareToast)
        .task(id: shareToast?.id) {
            guard let toastID = shareToast?.id else { return }
            try? await Task.sleep(nanoseconds: 2_400_000_000)
            await MainActor.run {
                if shareToast?.id == toastID {
                    shareToast = nil
                }
            }
        }
    }

    @ViewBuilder
    private func paragraphRow(_ paragraph: DailyStoryParagraph) -> some View {
        let isSelected = isActive && paragraph.id == selectedParagraphID
        let isSearchHighlighted = MarkdownSearchHighlightPresentation.textContainsQuery(
            paragraph.text,
            query: searchQuery
        )
        let isHovered = hoveredParagraphID == paragraph.id
        let paragraphTodoCandidates = todoCandidates.filter { $0.paragraphID == paragraph.id }

        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top, spacing: 0) {
                Rectangle()
                    .fill(paragraphAccentColor(isSelected: isSelected, isSearchHighlighted: isSearchHighlighted))
                    .frame(width: 2)
                    .padding(.vertical, 4)

                MarkdownPreviewContent(markdown: paragraph.text, highlightQuery: searchQuery)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
            }
            .background(paragraphBackgroundColor(
                isSelected: isSelected,
                isSearchHighlighted: isSearchHighlighted,
                isHovered: isHovered
            ))
            .contentShape(Rectangle())
            .onTapGesture {
                onFocusStory()
                onSelectParagraph(paragraph.id)
            }
            .contextMenu {
                Button(shareMenuTitle(redacted: true, for: paragraph)) {
                    openParagraphSharePopover(paragraph, redacted: true)
                }
                Button(shareMenuTitle(redacted: false, for: paragraph)) {
                    openParagraphSharePopover(paragraph, redacted: false)
                }
            }

            if !paragraphTodoCandidates.isEmpty {
                DailyTodoCandidateActionsView(
                    candidates: paragraphTodoCandidates,
                    onAddTodoCandidate: onAddTodoCandidate
                )
                .padding(.leading, 16)
                .padding(.trailing, 14)
                .padding(.bottom, 10)
            }
        }
        .onHover { hovering in
            hoveredParagraphID = hovering ? paragraph.id : nil
        }
    }

    private func sharePopover(_ presentation: DiarySharePresentation) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Toggle(presentation.redactionToggleTitle, isOn: $shareRedacted)
                .toggleStyle(.checkbox)
                .font(.callout)
            Text(presentation.modeTitle)
                .font(.caption)
                .foregroundStyle(.secondary)

            if let payload = activeSharePayload {
                DiarySharePreviewImage(payload: payload)
            }

            DiaryShareEncouragementView(presentation: presentation)

            HStack(spacing: 10) {
                Button(presentation.copyButtonTitle) {
                    let copied = performShareAction(.copyImage)
                    shareCopyFeedbackSucceeded = copied
                    shareCopyFeedbackMessage = copied ? presentation.copySuccessMessage : presentation.copyFailureMessage
                    shareToast = DiaryShareToast(
                        message: copied ? presentation.copySuccessMessage : presentation.copyFailureMessage,
                        succeeded: copied
                    )
                }
                .disabled(!presentation.canShare)

                Button(presentation.saveButtonTitle) {
                    shareCopyFeedbackMessage = nil
                    _ = performShareAction(.saveImage)
                }
                .disabled(!presentation.canShare)
            }

            if let shareCopyFeedbackMessage {
                HStack(spacing: 6) {
                    Image(systemName: shareCopyFeedbackSucceeded ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                        .foregroundStyle(shareCopyFeedbackSucceeded ? .green : .orange)
                    Text(shareCopyFeedbackMessage)
                        .font(.caption)
                        .foregroundStyle(.primary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 6))
            }
        }
        .padding(14)
        .frame(width: 340, alignment: .leading)
    }

    private func openFullStorySharePopover() {
        shareRequest = .fullStory
        shareRedacted = true
        resetShareFeedback()
        showsSharePopover = true
    }

    private func openParagraphSharePopover(_ paragraph: DailyStoryParagraph, redacted: Bool) {
        shareRequest = .paragraph(DiaryShareSelectedTextResolver().paragraphForSharing(paragraph))
        shareRedacted = redacted
        resetShareFeedback()
        showsSharePopover = true
    }

    private func resetShareFeedback() {
        shareCopyFeedbackMessage = nil
        shareCopyFeedbackSucceeded = true
    }

    private func performShareAction(_ action: DiaryShareAction) -> Bool {
        switch shareRequest {
        case .fullStory:
            return onShareDiary(shareRedacted, action)
        case .paragraph(let paragraph):
            return onShareParagraph(paragraph, shareRedacted, action)
        }
    }

    private var activeSharePayload: DiarySharePayload? {
        switch shareRequest {
        case .fullStory:
            guard let story else { return nil }
            return DiaryShareContentBuilder().payload(source: .fullStory(story), redacted: shareRedacted)
        case .paragraph(let paragraph):
            let resolvedDayKey = dayKey ?? story?.dayKey ?? ISO8601DayKey.format(Date())
            return DiaryShareContentBuilder().payload(
                source: .paragraph(paragraph, dayKey: resolvedDayKey),
                redacted: shareRedacted
            )
        }
    }

    private func diaryShareToast(_ toast: DiaryShareToast) -> some View {
        HStack(spacing: 8) {
            Image(systemName: toast.succeeded ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                .foregroundStyle(toast.succeeded ? .green : .orange)
            Text(toast.message)
                .font(.callout.weight(.medium))
                .foregroundStyle(.primary)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .frame(maxWidth: 300, alignment: .leading)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
        .overlay {
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.primary.opacity(0.12), lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.16), radius: 10, y: 5)
        .accessibilityElement(children: .combine)
    }

    private func shareMenuTitle(redacted: Bool, for paragraph: DailyStoryParagraph) -> String {
        return redacted ? "Share Redacted" : "Share Original"
    }

    private func paragraphAccentColor(
        isSelected: Bool,
        isSearchHighlighted: Bool
    ) -> Color {
        if isSelected { return .accentColor }
        if isSearchHighlighted { return .yellow }
        return .clear
    }

    private func paragraphBackgroundColor(
        isSelected: Bool,
        isSearchHighlighted: Bool,
        isHovered: Bool
    ) -> Color {
        if isSelected { return Color.accentColor.opacity(0.07) }
        if isSearchHighlighted { return Color.yellow.opacity(0.16) }
        if isHovered { return Color.primary.opacity(0.04) }
        return .clear
    }

    private var formattedDayKey: String {
        guard let dayKey else { return "" }
        if dayKey == OnboardingDemoStory.demoDayKey {
            return "Demo Day"
        }
        let parser = DateFormatter()
        parser.dateFormat = "yyyy-MM-dd"
        parser.locale = Locale(identifier: "en_US_POSIX")
        guard let date = parser.date(from: dayKey) else { return dayKey }

        let monthDay = DateFormatter()
        monthDay.dateFormat = "MMM d"
        let weekday = DateFormatter()
        weekday.dateFormat = "EEEE"
        weekday.locale = Locale(identifier: "en_US")
        return "\(monthDay.string(from: date)) · \(weekday.string(from: date))"
    }

    private func scrollToParagraphIfNeeded(
        _ paragraphID: String?,
        using proxy: ScrollViewProxy
    ) async {
        guard let paragraphID else { return }

        await MainActor.run {
            proxy.scrollTo(paragraphID, anchor: .center)
        }

        try? await Task.sleep(nanoseconds: 150_000_000)
        await MainActor.run {
            withAnimation(.easeInOut(duration: 0.2)) {
                proxy.scrollTo(paragraphID, anchor: .center)
            }
        }
    }

    private var isRefreshing: Bool {
        refreshJob?.inFlight == true
    }
}

enum DiaryShareButtonTone: Equatable {
    case prominent
    case disabled
}

private struct DiaryShareToast: Equatable, Identifiable {
    let id = UUID()
    let message: String
    let succeeded: Bool
}

private enum DiaryShareRequest: Equatable {
    case fullStory
    case paragraph(DailyStoryParagraph)
}

private struct ShareToolbarLabel: View {
    let presentation: DiarySharePresentation

    var body: some View {
        Label {
            Text(presentation.buttonTitle)
                .font(.callout.weight(.semibold))
        } icon: {
            Image(systemName: "square.and.arrow.up")
                .font(.callout.weight(.semibold))
        }
        .labelStyle(.titleAndIcon)
        .foregroundStyle(presentation.buttonTone == .prominent ? Color.accentColor : Color.secondary)
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background {
            Capsule()
                .fill(
                    LinearGradient(
                        colors: [
                            Color.accentColor.opacity(presentation.buttonTone == .prominent ? 0.18 : 0.06),
                            Color.cyan.opacity(presentation.buttonTone == .prominent ? 0.10 : 0.04),
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
        }
        .overlay {
            Capsule()
                .stroke(Color.accentColor.opacity(presentation.buttonTone == .prominent ? 0.30 : 0.10), lineWidth: 1)
        }
    }
}

private struct DiaryShareEncouragementView: View {
    let presentation: DiarySharePresentation

    var body: some View {
        HStack(alignment: .top, spacing: 9) {
            Image(systemName: "paperplane.fill")
                .font(.caption.weight(.semibold))
                .foregroundStyle(Color.accentColor)
                .frame(width: 18, height: 18)

            VStack(alignment: .leading, spacing: 2) {
                Text(presentation.encouragementTitle)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.primary)
                Text(presentation.encouragementDetail)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.accentColor.opacity(0.07), in: RoundedRectangle(cornerRadius: 8))
        .overlay {
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.accentColor.opacity(0.12), lineWidth: 1)
        }
        .accessibilityElement(children: .combine)
    }
}

private struct DiarySharePreviewImage: View {
    let payload: DiarySharePayload

    var body: some View {
        let image = DiaryShareImageRenderer().image(for: payload)
        let aspectRatio = image.size.width / max(image.size.height, 1)

        ScrollView(.vertical) {
            Image(nsImage: image)
                .resizable()
                .aspectRatio(aspectRatio, contentMode: .fit)
                .frame(width: 306)
                .accessibilityHidden(true)
        }
        .scrollIndicators(.visible)
        .frame(maxWidth: .infinity)
        .frame(height: 240)
        .background(Color(nsColor: .windowBackgroundColor), in: RoundedRectangle(cornerRadius: 8))
        .overlay {
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.primary.opacity(0.12), lineWidth: 1)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Share image preview")
        .accessibilityHint("Scrollable preview of the image that will be copied or saved")
    }
}

private struct DailyTodoCandidateActionsView: View {
    let candidates: [DailyTodoCandidatePresentation]
    let onAddTodoCandidate: (String) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(candidates) { candidate in
                HStack(spacing: 8) {
                    Text(candidate.title)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                    Spacer(minLength: 12)
                    Button(candidate.statusTitle) {
                        onAddTodoCandidate(candidate.id)
                    }
                    .buttonStyle(.borderless)
                    .disabled(candidate.isTracked)
                    .help(candidate.isTracked ? "Already in Todo" : "Add to Todo")
                }
            }
        }
    }
}

struct DayRefreshProgressPresentation {
    enum StepState: Equatable {
        case completed
        case current
        case pending
    }

    struct Step: Identifiable, Equatable {
        let id: DayRefreshStage
        let title: String
        let state: StepState

        var symbolName: String {
            switch state {
            case .completed: "checkmark.circle.fill"
            case .current: "arrow.triangle.2.circlepath.circle.fill"
            case .pending: "circle"
            }
        }

        var color: Color {
            switch state {
            case .completed: .green
            case .current: .accentColor
            case .pending: .secondary.opacity(0.5)
            }
        }
    }

    private static let visibleStages: [DayRefreshStage] = [
        .syncingNotifications,
        .loadingEvents,
        .preparingStory,
        .generatingStory,
        .writingFiles,
    ]

    let steps: [Step]
    let currentDetail: String?
    let summaryText: String?
    let summaryColor: Color

    init(refreshJob: DayRefreshJob?) {
        guard let refreshJob else {
            steps = []
            currentDetail = nil
            summaryText = nil
            summaryColor = .secondary
            return
        }

        if refreshJob.inFlight {
            steps = Self.visibleStages.map { stage in
                let state: StepState
                if refreshJob.completedStages.contains(stage) {
                    state = .completed
                } else if refreshJob.stage == stage {
                    state = .current
                } else {
                    state = .pending
                }
                return Step(id: stage, title: stage.progressTitle, state: state)
            }
            currentDetail = refreshJob.detail
            summaryText = nil
            summaryColor = .secondary
        } else {
            steps = []
            currentDetail = nil
            summaryText = refreshJob.summary
            summaryColor = refreshJob.error == nil ? .secondary : .red
        }
    }

    var showsSteps: Bool {
        !steps.isEmpty
    }
}

private extension DayRefreshStage {
    var progressTitle: String {
        switch self {
        case .syncingNotifications:
            return "Sync notifications"
        case .loadingEvents:
            return "Load events"
        case .preparingStory:
            return "Prepare journal"
        case .generatingStory:
            return "Generate journal (may take minutes, come back later)"
        case .writingFiles:
            return "Write files"
        case .completed, .failed:
            return detail
        }
    }
}

struct DailyMarkdownPresentation: Equatable {
    struct ScrollRequest: Equatable {
        let targetParagraphID: String?
        let dayKey: String?
        let paragraphIDs: [String]
    }

    let paragraphs: [DailyStoryParagraph]
    let selectedParagraphID: String?
    let searchHighlightedParagraphID: String?
    let scrollTargetParagraphID: String?
    let scrollRequest: ScrollRequest
    let storyHeading: String
    let emptyStateTitle: String
    let emptyStateMessage: String?
    let emptyStateSymbol: String

    init(
        story: DailyStory?,
        selectedParagraphID: String? = nil,
        isGenerating: Bool = false,
        searchQuery: String? = nil
    ) {
        paragraphs = story?.sections.flatMap(\.paragraphs) ?? []
        self.selectedParagraphID = selectedParagraphID
        searchHighlightedParagraphID = Self.searchHighlightedParagraphID(
            paragraphs: paragraphs,
            searchQuery: searchQuery
        )
        if let searchHighlightedParagraphID {
            scrollTargetParagraphID = searchHighlightedParagraphID
        } else if let selectedParagraphID,
           paragraphs.contains(where: { $0.id == selectedParagraphID }) {
            scrollTargetParagraphID = selectedParagraphID
        } else {
            scrollTargetParagraphID = paragraphs.first?.id
        }
        scrollRequest = ScrollRequest(
            targetParagraphID: scrollTargetParagraphID,
            dayKey: story?.dayKey,
            paragraphIDs: paragraphs.map(\.id)
        )
        storyHeading = Self.resolvedStoryHeading(for: story, paragraphs: paragraphs)
        if isGenerating {
            emptyStateTitle = "Generating your diary…"
            emptyStateMessage = "KnowYou is building this day from your local context. Come back 2 minutes later."
            emptyStateSymbol = "arrow.triangle.2.circlepath"
        } else {
            emptyStateTitle = "No Story Yet"
            emptyStateMessage = nil
            emptyStateSymbol = "text.book.closed"
        }
    }

    var showsEmptyState: Bool {
        paragraphs.isEmpty
    }

    var initialScrollParagraphID: String? {
        scrollTargetParagraphID
    }

    private static func resolvedStoryHeading(
        for story: DailyStory?,
        paragraphs: [DailyStoryParagraph]
    ) -> String {
        let combinedText = paragraphs.map(\.text).joined(separator: "\n")
        if combinedText.contains(where: \.isChineseIdeograph) {
            return "今日小记"
        }

        if story?.dayKey.isEmpty == false {
            return "Story"
        }

        return "Story"
    }

    private static func searchHighlightedParagraphID(
        paragraphs: [DailyStoryParagraph],
        searchQuery: String?
    ) -> String? {
        let query = searchQuery?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard query.isEmpty == false else { return nil }
        return paragraphs.first { paragraph in
            MarkdownSearchHighlightPresentation.textContainsQuery(paragraph.text, query: query)
        }?.id
    }
}

enum DiaryShareAction: Equatable {
    case copyImage
    case saveImage
}

struct DiarySharePresentation: Equatable {
    let canShare: Bool
    let buttonTitle: String
    let buttonTone: DiaryShareButtonTone
    let redactionToggleTitle: String
    let copyButtonTitle: String
    let saveButtonTitle: String
    let modeTitle: String
    let encouragementTitle: String
    let encouragementDetail: String
    let copySuccessMessage: String
    let copyFailureMessage: String
    let disabledReason: String?

    init(story: DailyStory?, redacted: Bool) {
        let paragraphs = story?.sections.flatMap(\.paragraphs) ?? []
        canShare = paragraphs.contains { paragraph in
            paragraph.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
        }
        disabledReason = canShare ? nil : "No diary text to share yet."
        buttonTitle = "Share Redacted"
        buttonTone = canShare ? .prominent : .disabled
        redactionToggleTitle = "Redact sensitive details"
        copyButtonTitle = "Copy Image"
        saveButtonTitle = "Save Image"
        modeTitle = redacted ? "Redacted share" : "Original share"
        encouragementTitle = "Share the interesting parts."
        encouragementDetail = "Keep the rest private."
        copySuccessMessage = "Copied. You can paste it elsewhere."
        copyFailureMessage = "Could not copy share image"
    }
}

struct DiaryShareSelectedTextResolver {
    @MainActor
    func paragraphForSharing(_ paragraph: DailyStoryParagraph) -> DailyStoryParagraph {
        guard let selectedText = selectedTextFromKeyWindow(containedBy: paragraph) else {
            return paragraph
        }
        return DailyStoryParagraph(
            id: "\(paragraph.id)-selection",
            text: selectedText,
            sourceEventIDs: paragraph.sourceEventIDs
        )
    }

    func selectedText(
        in text: String,
        ranges: [NSRange],
        fallbackParagraph paragraph: DailyStoryParagraph
    ) -> String? {
        let selected = ranges
            .filter { $0.length > 0 }
            .compactMap { range -> String? in
                guard let stringRange = Range(range, in: text) else { return nil }
                return String(text[stringRange])
            }
            .joined(separator: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard selected.isEmpty == false else { return nil }
        guard selection(selected, belongsTo: paragraph) else { return nil }
        return selected
    }

    @MainActor
    private func selectedTextFromKeyWindow(containedBy paragraph: DailyStoryParagraph) -> String? {
        guard let textView = NSApp.keyWindow?.firstResponder as? NSTextView else {
            return nil
        }
        return selectedText(
            in: textView.string,
            ranges: textView.selectedRanges.map(\.rangeValue),
            fallbackParagraph: paragraph
        )
    }

    private func selection(_ selected: String, belongsTo paragraph: DailyStoryParagraph) -> Bool {
        if paragraph.text.contains(selected) {
            return true
        }

        let plainParagraph = DailyMarkdownRenderer.blocks(from: paragraph.text)
            .map(Self.plainText)
            .joined(separator: "\n")
        return plainParagraph.contains(selected)
    }

    private static func plainText(from block: DailyMarkdownRenderer.Block) -> String {
        switch block {
        case .heading(_, let content):
            content.plainText
        case .paragraph(let content):
            content.plainText
        case .bulletList(let items):
            items.map(\.plainText).joined(separator: "\n")
        case .orderedList(let items):
            items.map(\.content.plainText).joined(separator: "\n")
        case .taskList(let items):
            items.map(\.content.plainText).joined(separator: "\n")
        case .quote(let items):
            items.map(\.plainText).joined(separator: "\n")
        case .table(let table):
            (table.headers + table.rows.flatMap { $0 }).map(\.plainText).joined(separator: "\n")
        case .codeBlock(let text):
            text
        }
    }
}

protocol DiarySharePasteboardWriting: AnyObject {
    @discardableResult
    func clearContents() -> Int
    func setData(_ data: Data?, forType dataType: NSPasteboard.PasteboardType) -> Bool
}

extension NSPasteboard: DiarySharePasteboardWriting {}

extension NSPasteboard.PasteboardType {
    static let knowYouPNG = NSPasteboard.PasteboardType("public.png")
}

struct DiarySharePasteboardWriter {
    let pasteboard: DiarySharePasteboardWriting

    init(pasteboard: DiarySharePasteboardWriting = NSPasteboard.general) {
        self.pasteboard = pasteboard
    }

    func write(image: NSImage) -> Bool {
        guard let pngData = DiaryShareImageRenderer().pngData(from: image),
              let tiffData = image.tiffRepresentation else {
            return false
        }

        pasteboard.clearContents()
        let wrotePNG = pasteboard.setData(pngData, forType: .knowYouPNG)
        let wroteTIFF = pasteboard.setData(tiffData, forType: .tiff)
        return wrotePNG && wroteTIFF
    }
}

struct DiaryShareImageRenderer {
    private let cardWidth: CGFloat = 900
    private let minimumCardHeight: CGFloat = 1_200
    private let margin: CGFloat = 72
    private let bodyWidth: CGFloat = 680
    private let primaryTextColor = NSColor(calibratedWhite: 0.12, alpha: 1)
    private let secondaryTextColor = NSColor(calibratedWhite: 0.36, alpha: 1)

    func qrImage(for url: URL, size: CGFloat = 144) -> NSImage? {
        let filter = CIFilter(name: "CIQRCodeGenerator")
        filter?.setValue(Data(url.absoluteString.utf8), forKey: "inputMessage")
        filter?.setValue("M", forKey: "inputCorrectionLevel")
        guard let outputImage = filter?.outputImage else { return nil }

        let scale = size / max(outputImage.extent.width, outputImage.extent.height)
        let transformed = outputImage.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        let representation = NSCIImageRep(ciImage: transformed)
        let image = NSImage(size: representation.size)
        image.addRepresentation(representation)
        return image
    }

    func image(for payload: DiarySharePayload) -> NSImage {
        let bodyText = plainText(from: payload.body)
        let bodyHeight = measuredTextHeight(
            bodyText,
            width: bodyWidth,
            font: .systemFont(ofSize: 28, weight: .regular)
        )
        let cardHeight = max(minimumCardHeight, 510 + bodyHeight)
        let cardSize = NSSize(width: cardWidth, height: cardHeight)
        let image = NSImage(size: cardSize)
        image.lockFocus()
        defer { image.unlockFocus() }

        NSColor(calibratedRed: 0.98, green: 0.97, blue: 0.94, alpha: 1).setFill()
        NSRect(origin: .zero, size: cardSize).fill()

        let contentRect = NSRect(
            x: margin,
            y: margin,
            width: cardSize.width - margin * 2,
            height: cardSize.height - margin * 2
        )
        let cardPath = NSBezierPath(roundedRect: contentRect, xRadius: 18, yRadius: 18)
        NSColor.white.setFill()
        cardPath.fill()

        drawText(
            "KnowYou Diary",
            in: NSRect(x: 110, y: cardHeight - 170, width: 420, height: 44),
            font: .systemFont(ofSize: 32, weight: .semibold),
            color: primaryTextColor
        )
        drawText(
            "\(payload.dayKey) · \(modeTitle(for: payload.mode))",
            in: NSRect(x: 110, y: cardHeight - 212, width: 520, height: 32),
            font: .systemFont(ofSize: 18, weight: .medium),
            color: secondaryTextColor
        )
        drawText(
            bodyText,
            in: NSRect(x: 110, y: 255, width: bodyWidth, height: cardHeight - 510),
            font: .systemFont(ofSize: 28, weight: .regular),
            color: primaryTextColor
        )

        if let qr = qrImage(for: payload.downloadURL, size: 128) {
            qr.draw(in: NSRect(x: 640, y: 108, width: 128, height: 128))
        }

        drawText(
            "Shared from KnowYou",
            in: NSRect(x: 110, y: 170, width: 360, height: 30),
            font: .systemFont(ofSize: 19, weight: .semibold),
            color: primaryTextColor
        )
        drawText(
            payload.downloadURL.hostAndPathDisplay,
            in: NSRect(x: 110, y: 138, width: 460, height: 28),
            font: .systemFont(ofSize: 18, weight: .regular),
            color: secondaryTextColor
        )

        return image
    }

    func pngData(for payload: DiarySharePayload) -> Data? {
        pngData(from: image(for: payload))
    }

    func pngData(from image: NSImage) -> Data? {
        guard let tiffData = image.tiffRepresentation,
              let representation = NSBitmapImageRep(data: tiffData) else {
            return nil
        }
        return representation.representation(using: .png, properties: [:])
    }

    private func drawText(_ text: String, in rect: NSRect, font: NSFont, color: NSColor) {
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.lineBreakMode = .byWordWrapping
        paragraphStyle.lineSpacing = 5
        let attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: color,
            .paragraphStyle: paragraphStyle,
        ]
        NSString(string: text).draw(in: rect, withAttributes: attributes)
    }

    private func measuredTextHeight(_ text: String, width: CGFloat, font: NSFont) -> CGFloat {
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.lineBreakMode = .byWordWrapping
        paragraphStyle.lineSpacing = 5
        let attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .paragraphStyle: paragraphStyle,
        ]
        let boundingRect = NSString(string: text).boundingRect(
            with: NSSize(width: width, height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            attributes: attributes
        )
        return max(44, ceil(boundingRect.height) + 16)
    }

    private func plainText(from markdown: String) -> String {
        DailyMarkdownRenderer.blocks(from: markdown)
            .map { block in
                switch block {
                case .heading(_, let content):
                    content.plainText
                case .paragraph(let content):
                    content.plainText
                case .bulletList(let items):
                    items.map { "- \($0.plainText)" }.joined(separator: "\n")
                case .orderedList(let items):
                    items.map { "\($0.index). \($0.content.plainText)" }.joined(separator: "\n")
                case .taskList(let items):
                    items.map { "- [\($0.isCompleted ? "x" : " ")] \($0.content.plainText)" }.joined(separator: "\n")
                case .quote(let items):
                    items.map { "> \($0.plainText)" }.joined(separator: "\n")
                case .codeBlock(let code):
                    code
                case .table(let table):
                    (table.headers + table.rows.flatMap { $0 }).map(\.plainText).joined(separator: " · ")
                }
            }
            .joined(separator: "\n\n")
    }

    private func modeTitle(for mode: DiaryShareMode) -> String {
        switch mode {
        case .redacted: "Redacted share"
        case .original: "Original share"
        }
    }
}

struct DiaryShareExportFilename {
    static func defaultName(dayKey: String, mode: DiaryShareMode) -> String {
        let modeSuffix: String
        switch mode {
        case .redacted:
            modeSuffix = "redacted"
        case .original:
            modeSuffix = "original"
        }

        let safeDayKey = dayKey
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: ":", with: "-")
        let datePart = safeDayKey.isEmpty ? ISO8601DayKey.format(Date()) : safeDayKey
        return "KnowYou-\(datePart)-\(modeSuffix)-share.png"
    }
}

private extension URL {
    var hostAndPathDisplay: String {
        guard let host else { return absoluteString }
        return host + path
    }
}

struct SourceBrand: Equatable {
    enum Identity: Equatable {
        case chatGPT
        case notes
        case mail
        case calendar
        case drafts
        case taio
        case teams
        case ghostty
        case weChat
        case feishu
        case claude
        case perplexity
        case notion
        case gitHub
        case slack
        case x
        case google
        case genericApp
    }

    enum Glyph: Equatable {
        enum Symbol: String, Equatable {
            case app = "app.fill"
        }

        case asset(String)
        case symbol(Symbol)
    }

    let identity: Identity
    let glyph: Glyph
    let fallbackSymbol: Glyph.Symbol

    var assetName: String? {
        guard case .asset(let assetName) = glyph else { return nil }
        return assetName
    }

    var fallbackSymbolName: String {
        fallbackSymbol.rawValue
    }
}

enum SourceBrandResolver {
    private struct BrandEntry {
        let aliases: [String]
        let brand: SourceBrand
    }

    private static let fallbackBrand = SourceBrand(
        identity: .genericApp,
        glyph: .symbol(.app),
        fallbackSymbol: .app
    )

    private static let brandLookup: [String: SourceBrand] = {
        var lookup: [String: SourceBrand] = [:]
        for entry in entries {
            for alias in entry.aliases {
                lookup[normalize(alias)] = entry.brand
            }
        }
        return lookup
    }()

    static func resolve(appName: String) -> SourceBrand {
        let normalizedName = normalize(appName)
        if let exactBrand = brandLookup[normalizedName] {
            return exactBrand
        }

        return fuzzyMatch(normalizedName) ?? fallbackBrand
    }

    private static func normalize(_ appName: String) -> String {
        appName
            .unicodeScalars
            .map { scalar in
                if CharacterSet.alphanumerics.contains(scalar) || (0x4E00...0x9FFF).contains(scalar.value) {
                    return String(scalar)
                }
                return " "
            }
            .joined()
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .split(whereSeparator: \.isWhitespace)
            .joined(separator: " ")
            .lowercased()
    }

    private static func fuzzyMatch(_ normalizedName: String) -> SourceBrand? {
        let nameTokens = normalizedName.split(separator: " ").map(String.init)

        for entry in entries {
            for alias in entry.aliases {
                let normalizedAlias = normalize(alias)

                if normalizedAlias.contains(" ") {
                    if normalizedName.contains(normalizedAlias) {
                        return entry.brand
                    }
                    continue
                }

                guard normalizedAlias.count >= 4 || normalizedAlias.contains(where: \.isChineseIdeograph) else {
                    continue
                }

                let matched = nameTokens.contains { token in
                    token == normalizedAlias || token.hasSuffix(normalizedAlias) || token.hasPrefix(normalizedAlias)
                }
                if matched {
                    return entry.brand
                }
            }
        }

        return nil
    }

    private static func brand(
        assetName: String,
        aliases: [String],
        identity: SourceBrand.Identity = .genericApp
    ) -> BrandEntry {
        BrandEntry(
            aliases: aliases,
            brand: SourceBrand(
                identity: identity,
                glyph: .asset(assetName),
                fallbackSymbol: .app
            )
        )
    }

    private static let entries: [BrandEntry] = [
        brand(
            assetName: "SourceLogoChatGPT",
            aliases: ["ChatGPT", "OpenAI ChatGPT"],
            identity: .chatGPT
        ),
        brand(
            assetName: "SourceLogoClaude",
            aliases: ["Claude", "Anthropic Claude"],
            identity: .claude
        ),
        brand(
            assetName: "SourceLogoPerplexity",
            aliases: ["Perplexity"],
            identity: .perplexity
        ),
        brand(
            assetName: "SourceLogoNotion",
            aliases: ["Notion"],
            identity: .notion
        ),
        brand(
            assetName: "SourceLogoGitHub",
            aliases: ["GitHub"],
            identity: .gitHub
        ),
        brand(
            assetName: "SourceLogoGitHubDesktop",
            aliases: ["GitHub Desktop"]
        ),
        brand(
            assetName: "SourceLogoSlack",
            aliases: ["Slack"],
            identity: .slack
        ),
        brand(
            assetName: "SourceLogoX",
            aliases: ["X", "Twitter"],
            identity: .x
        ),
        brand(
            assetName: "SourceLogoGoogle",
            aliases: ["Google", "Gmail", "Google Calendar", "Google Docs"],
            identity: .google
        ),
        brand(
            assetName: "SourceLogoChrome",
            aliases: ["Google Chrome", "Chrome", "Chrome Browser", "谷歌浏览器", "com.google.Chrome"]
        ),
        brand(
            assetName: "SourceLogoSafari",
            aliases: ["Safari"]
        ),
        brand(
            assetName: "SourceLogoFinder",
            aliases: ["Finder"]
        ),
        brand(
            assetName: "SourceLogoMail",
            aliases: ["Mail", "Apple Mail", "邮件"],
            identity: .mail
        ),
        brand(
            assetName: "SourceLogoNotes",
            aliases: ["Notes", "Apple Notes", "备忘录"],
            identity: .notes
        ),
        brand(
            assetName: "SourceLogoCalendar",
            aliases: ["Calendar", "Apple Calendar", "日历"],
            identity: .calendar
        ),
        brand(
            assetName: "SourceLogoMessages",
            aliases: ["Messages", "iMessage", "信息", "MobileSMS"]
        ),
        brand(
            assetName: "SourceLogoPreview",
            aliases: ["Preview", "预览"]
        ),
        brand(
            assetName: "SourceLogoTextEdit",
            aliases: ["TextEdit"]
        ),
        brand(
            assetName: "SourceLogoReminders",
            aliases: ["Reminders", "提醒事项"]
        ),
        brand(
            assetName: "SourceLogoContacts",
            aliases: ["Contacts", "通讯录"]
        ),
        brand(
            assetName: "SourceLogoPhotos",
            aliases: ["Photos", "照片"]
        ),
        brand(
            assetName: "SourceLogoMusic",
            aliases: ["Music", "Apple Music", "音乐"]
        ),
        brand(
            assetName: "SourceLogoMaps",
            aliases: ["Maps", "地图"]
        ),
        brand(
            assetName: "SourceLogoAppStore",
            aliases: ["App Store"]
        ),
        brand(
            assetName: "SourceLogoSystemSettings",
            aliases: ["System Settings", "Settings", "系统设置"]
        ),
        brand(
            assetName: "SourceLogoActivityMonitor",
            aliases: ["Activity Monitor"]
        ),
        brand(
            assetName: "SourceLogoDiskUtility",
            aliases: ["Disk Utility"]
        ),
        brand(
            assetName: "SourceLogoCalculator",
            aliases: ["Calculator"]
        ),
        brand(
            assetName: "SourceLogoClock",
            aliases: ["Clock"]
        ),
        brand(
            assetName: "SourceLogoBooks",
            aliases: ["Books", "Apple Books"]
        ),
        brand(
            assetName: "SourceLogoFaceTime",
            aliases: ["FaceTime"]
        ),
        brand(
            assetName: "SourceLogoFreeform",
            aliases: ["Freeform"]
        ),
        brand(
            assetName: "SourceLogoShortcuts",
            aliases: ["Shortcuts", "快捷指令"]
        ),
        brand(
            assetName: "SourceLogoConsole",
            aliases: ["Console"]
        ),
        brand(
            assetName: "SourceLogoFontBook",
            aliases: ["Font Book"]
        ),
        brand(
            assetName: "SourceLogoImageCapture",
            aliases: ["Image Capture"]
        ),
        brand(
            assetName: "SourceLogoWeather",
            aliases: ["Weather"]
        ),
        brand(
            assetName: "SourceLogoNews",
            aliases: ["News"]
        ),
        brand(
            assetName: "SourceLogoHome",
            aliases: ["Home"]
        ),
        brand(
            assetName: "SourceLogoStocks",
            aliases: ["Stocks"]
        ),
        brand(
            assetName: "SourceLogoTV",
            aliases: ["TV", "Apple TV"]
        ),
        brand(
            assetName: "SourceLogoQuickTime",
            aliases: ["QuickTime", "QuickTime Player"]
        ),
        brand(
            assetName: "SourceLogoPhotoBooth",
            aliases: ["Photo Booth"]
        ),
        brand(
            assetName: "SourceLogoJournal",
            aliases: ["Journal"]
        ),
        brand(
            assetName: "SourceLogoVoiceMemos",
            aliases: ["Voice Memos", "VoiceMemos"]
        ),
        brand(
            assetName: "SourceLogoFindMy",
            aliases: ["Find My", "FindMy"]
        ),
        brand(
            assetName: "SourceLogoPhone",
            aliases: ["Phone"]
        ),
        brand(
            assetName: "SourceLogoDrafts",
            aliases: ["Drafts"],
            identity: .drafts
        ),
        brand(
            assetName: "SourceLogoTaio",
            aliases: ["Taio"],
            identity: .taio
        ),
        brand(
            assetName: "SourceLogoTeams",
            aliases: ["Microsoft Teams", "Teams", "com.microsoft.teams2"],
            identity: .teams
        ),
        brand(
            assetName: "SourceLogoWord",
            aliases: ["Microsoft Word", "Word"]
        ),
        brand(
            assetName: "SourceLogoExcel",
            aliases: ["Microsoft Excel", "Excel", "com.microsoft.Excel"]
        ),
        brand(
            assetName: "SourceLogoPowerPoint",
            aliases: ["Microsoft PowerPoint", "PowerPoint", "PPT"]
        ),
        brand(
            assetName: "SourceLogoOutlook",
            aliases: ["Microsoft Outlook", "Outlook"]
        ),
        brand(
            assetName: "SourceLogoPages",
            aliases: ["Pages"]
        ),
        brand(
            assetName: "SourceLogoNumbers",
            aliases: ["Numbers"]
        ),
        brand(
            assetName: "SourceLogoGhostty",
            aliases: ["Ghostty"],
            identity: .ghostty
        ),
        brand(
            assetName: "SourceLogoAntigravity",
            aliases: ["Antigravity", "com.google.antigravity"]
        ),
        brand(
            assetName: "SourceLogoTerminal",
            aliases: ["Terminal"]
        ),
        brand(
            assetName: "SourceLogoITerm",
            aliases: ["iTerm", "iTerm2"]
        ),
        brand(
            assetName: "SourceLogoXcode",
            aliases: ["Xcode"]
        ),
        brand(
            assetName: "SourceLogoVSCode",
            aliases: ["Visual Studio Code", "VS Code", "VSCode", "Code"]
        ),
        brand(
            assetName: "SourceLogoCursor",
            aliases: ["Cursor"]
        ),
        brand(
            assetName: "SourceLogoFigma",
            aliases: ["Figma"]
        ),
        brand(
            assetName: "SourceLogoDocker",
            aliases: ["Docker", "Docker Desktop"]
        ),
        brand(
            assetName: "SourceLogoOBS",
            aliases: ["OBS", "OBS Studio"]
        ),
        brand(
            assetName: "SourceLogoDBBrowser",
            aliases: ["DB Browser for SQLite", "DB Browser"]
        ),
        brand(
            assetName: "SourceLogoObsidian",
            aliases: ["Obsidian"]
        ),
        brand(
            assetName: "SourceLogoOneDrive",
            aliases: ["OneDrive", "Microsoft OneDrive"]
        ),
        brand(
            assetName: "SourceLogoTelegram",
            aliases: ["Telegram"]
        ),
        brand(
            assetName: "SourceLogoWhatsApp",
            aliases: ["WhatsApp"]
        ),
        brand(
            assetName: "SourceLogoZoom",
            aliases: ["Zoom", "zoom.us", "Zoom Workplace"]
        ),
        brand(
            assetName: "SourceLogoCisco",
            aliases: ["Cisco Secure Client", "Cisco"]
        ),
        brand(
            assetName: "SourceLogoSpotify",
            aliases: ["Spotify"]
        ),
        brand(
            assetName: "SourceLogoWeChat",
            aliases: ["微信", "WeChat", "Weixin"],
            identity: .weChat
        ),
        brand(
            assetName: "SourceLogoFeishu",
            aliases: ["飞书", "Feishu", "Lark", "LarkSuite"],
            identity: .feishu
        ),
        brand(
            assetName: "SourceLogoDingTalk",
            aliases: ["DingTalk", "钉钉"]
        ),
        brand(
            assetName: "SourceLogoTencentMeeting",
            aliases: ["TencentMeeting", "Tencent Meeting", "腾讯会议"]
        ),
        brand(
            assetName: "SourceLogoArc",
            aliases: ["Arc"]
        ),
        brand(
            assetName: "SourceLogoFirefox",
            aliases: ["Firefox", "Mozilla Firefox"]
        ),
        brand(
            assetName: "SourceLogoBrave",
            aliases: ["Brave", "Brave Browser"]
        ),
        brand(
            assetName: "SourceLogoOpera",
            aliases: ["Opera"]
        ),
        brand(
            assetName: "SourceLogoVivaldi",
            aliases: ["Vivaldi"]
        ),
        brand(
            assetName: "SourceLogoDiscord",
            aliases: ["Discord"]
        ),
        brand(
            assetName: "SourceLogoLinear",
            aliases: ["Linear"]
        ),
        brand(
            assetName: "SourceLogoJira",
            aliases: ["Jira"]
        ),
        brand(
            assetName: "SourceLogoConfluence",
            aliases: ["Confluence"]
        ),
        brand(
            assetName: "SourceLogoAsana",
            aliases: ["Asana"]
        ),
        brand(
            assetName: "SourceLogoTrello",
            aliases: ["Trello"]
        ),
        brand(
            assetName: "SourceLogoClickUp",
            aliases: ["ClickUp"]
        ),
        brand(
            assetName: "SourceLogoMiro",
            aliases: ["Miro"]
        ),
        brand(
            assetName: "SourceLogoLoom",
            aliases: ["Loom"]
        ),
        brand(
            assetName: "SourceLogoGoogleMeet",
            aliases: ["Google Meet", "GoogleMeet"]
        ),
        brand(
            assetName: "SourceLogoSignal",
            aliases: ["Signal"]
        ),
        brand(
            assetName: "SourceLogoSketch",
            aliases: ["Sketch"]
        ),
        brand(
            assetName: "SourceLogoFramer",
            aliases: ["Framer"]
        ),
        brand(
            assetName: "SourceLogoReddit",
            aliases: ["Reddit"]
        ),
        brand(
            assetName: "SourceLogoYouTube",
            aliases: ["YouTube", "Youtube"]
        ),
        brand(
            assetName: "SourceLogoThreads",
            aliases: ["Threads"]
        ),
        brand(
            assetName: "SourceLogoBluesky",
            aliases: ["Bluesky", "BlueSky"]
        ),
        brand(
            assetName: "SourceLogoInstagram",
            aliases: ["Instagram"]
        ),
        brand(
            assetName: "SourceLogoFacebook",
            aliases: ["Facebook"]
        ),
        brand(
            assetName: "SourceLogoTikTok",
            aliases: ["TikTok", "Tiktok"]
        ),
        brand(
            assetName: "SourceLogoGemini",
            aliases: ["Gemini", "Google Gemini"]
        ),
        brand(
            assetName: "SourceLogoCopilot",
            aliases: ["Copilot", "GitHub Copilot", "Github Copilot"]
        ),
        brand(
            assetName: "SourceLogoPoe",
            aliases: ["Poe"]
        ),
        brand(
            assetName: "SourceLogoPostman",
            aliases: ["Postman"]
        ),
        brand(
            assetName: "SourceLogoWarp",
            aliases: ["Warp"]
        ),
        brand(
            assetName: "SourceLogoInsomnia",
            aliases: ["Insomnia"]
        ),
        brand(
            assetName: "SourceLogoRaycast",
            aliases: ["Raycast"]
        ),
        brand(
            assetName: "SourceLogoDropbox",
            aliases: ["Dropbox"]
        ),
        brand(
            assetName: "SourceLogoGoogleDrive",
            aliases: ["Google Drive", "GoogleDrive"]
        )
    ]
}

enum DailyMarkdownRenderer {
    struct TaskItem: Equatable {
        let isCompleted: Bool
        let content: InlineContent
    }

    struct OrderedItem: Equatable {
        let index: Int
        let content: InlineContent
    }

    struct Table: Equatable {
        let headers: [InlineContent]
        let rows: [[InlineContent]]
    }

    struct InlineContent: Equatable {
        let attributed: AttributedString?
        let plainText: String

        init(markdown: String) {
            plainText = markdown
            attributed = try? AttributedString(
                markdown: markdown,
                options: AttributedString.MarkdownParsingOptions(interpretedSyntax: .inlineOnlyPreservingWhitespace)
            )
        }
    }

    enum Block: Equatable {
        case heading(level: Int, content: InlineContent)
        case paragraph(InlineContent)
        case bulletList([InlineContent])
        case orderedList([OrderedItem])
        case taskList([TaskItem])
        case quote([InlineContent])
        case codeBlock(String)
        case table(Table)
    }

    static func blocks(from markdown: String) -> [Block] {
        let lines = markdown
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .components(separatedBy: "\n")

        var blocks: [Block] = []
        var index = 0

        while index < lines.count {
            let rawLine = lines[index]
            let trimmed = rawLine.trimmingCharacters(in: .whitespaces)

            if trimmed.isEmpty {
                index += 1
                continue
            }

            if trimmed.hasPrefix("```") {
                var codeLines: [String] = []
                index += 1
                while index < lines.count && lines[index].trimmingCharacters(in: .whitespaces) != "```" {
                    codeLines.append(lines[index])
                    index += 1
                }
                if index < lines.count {
                    index += 1
                }
                blocks.append(.codeBlock(codeLines.joined(separator: "\n")))
                continue
            }

            if let heading = parseHeading(from: trimmed) {
                blocks.append(heading)
                index += 1
                continue
            }

            if let table = parseTable(lines: lines, startIndex: index) {
                blocks.append(.table(table.value))
                index = table.nextIndex
                continue
            }

            if let task = parseTaskItem(from: trimmed) {
                var items = [task]
                index += 1
                while index < lines.count, let nextTask = parseTaskItem(from: lines[index].trimmingCharacters(in: .whitespaces)) {
                    items.append(nextTask)
                    index += 1
                }
                blocks.append(.taskList(items))
                continue
            }

            if let bullet = parseBulletItem(from: trimmed) {
                var items = [bullet]
                index += 1
                while index < lines.count, let nextBullet = parseBulletItem(from: lines[index].trimmingCharacters(in: .whitespaces)) {
                    items.append(nextBullet)
                    index += 1
                }
                blocks.append(.bulletList(items))
                continue
            }

            if let ordered = parseOrderedItem(from: trimmed) {
                var items = [ordered]
                index += 1
                while index < lines.count, let nextOrdered = parseOrderedItem(from: lines[index].trimmingCharacters(in: .whitespaces)) {
                    items.append(nextOrdered)
                    index += 1
                }
                blocks.append(.orderedList(items))
                continue
            }

            if trimmed.hasPrefix(">") {
                var quotes = [InlineContent(markdown: String(trimmed.dropFirst().trimmingCharacters(in: .whitespaces)))]
                index += 1
                while index < lines.count {
                    let nextTrimmed = lines[index].trimmingCharacters(in: .whitespaces)
                    guard nextTrimmed.hasPrefix(">") else { break }
                    quotes.append(InlineContent(markdown: String(nextTrimmed.dropFirst().trimmingCharacters(in: .whitespaces))))
                    index += 1
                }
                blocks.append(.quote(quotes))
                continue
            }

            var paragraphLines = [trimmed]
            index += 1
            while index < lines.count {
                let nextTrimmed = lines[index].trimmingCharacters(in: .whitespaces)
                if nextTrimmed.isEmpty || startsNewBlock(nextTrimmed) {
                    break
                }
                paragraphLines.append(nextTrimmed)
                index += 1
            }
            blocks.append(.paragraph(InlineContent(markdown: paragraphLines.joined(separator: "\n"))))
        }

        return blocks
    }

    private static func startsNewBlock(_ line: String) -> Bool {
        parseHeading(from: line) != nil
            || parseTaskItem(from: line) != nil
            || parseBulletItem(from: line) != nil
            || parseOrderedItem(from: line) != nil
            || line.hasPrefix(">")
            || line.hasPrefix("```")
            || isTableRow(line)
    }

    private static func parseHeading(from line: String) -> Block? {
        guard line.hasPrefix("#") else { return nil }
        let hashes = line.prefix(while: { $0 == "#" }).count
        guard hashes > 0, hashes <= 6 else { return nil }
        let text = line.dropFirst(hashes).trimmingCharacters(in: .whitespaces)
        guard text.isEmpty == false else { return nil }
        return .heading(level: hashes, content: InlineContent(markdown: text))
    }

    private static func parseBulletItem(from line: String) -> InlineContent? {
        guard line.hasPrefix("- ") || line.hasPrefix("* ") else { return nil }
        let content = String(line.dropFirst(2))
        guard content.isEmpty == false else { return nil }
        return InlineContent(markdown: content)
    }

    private static func parseTaskItem(from line: String) -> TaskItem? {
        guard line.hasPrefix("- [") || line.hasPrefix("* [") else { return nil }
        guard line.count >= 6 else { return nil }
        let marker = line[line.index(line.startIndex, offsetBy: 3)]
        guard marker == " " || marker == "x" || marker == "X" else { return nil }
        guard line[line.index(line.startIndex, offsetBy: 4)] == "]" else { return nil }
        let contentStart = line.index(line.startIndex, offsetBy: 6)
        let content = String(line[contentStart...])
        return TaskItem(isCompleted: marker == "x" || marker == "X", content: InlineContent(markdown: content))
    }

    private static func parseOrderedItem(from line: String) -> OrderedItem? {
        let digits = line.prefix(while: { $0.isNumber })
        guard digits.isEmpty == false else { return nil }
        let remainder = line.dropFirst(digits.count)
        guard remainder.hasPrefix(". ") else { return nil }
        let content = String(remainder.dropFirst(2))
        guard let index = Int(digits), content.isEmpty == false else { return nil }
        return OrderedItem(index: index, content: InlineContent(markdown: content))
    }

    private static func parseTable(lines: [String], startIndex: Int) -> (value: Table, nextIndex: Int)? {
        guard startIndex + 1 < lines.count else { return nil }
        let headerLine = lines[startIndex].trimmingCharacters(in: .whitespaces)
        let separatorLine = lines[startIndex + 1].trimmingCharacters(in: .whitespaces)
        guard isTableRow(headerLine), isTableSeparator(separatorLine) else { return nil }

        let headers = tableCells(from: headerLine).map(InlineContent.init(markdown:))
        guard headers.isEmpty == false else { return nil }

        var rows: [[InlineContent]] = []
        var index = startIndex + 2
        while index < lines.count {
            let rowLine = lines[index].trimmingCharacters(in: .whitespaces)
            guard isTableRow(rowLine), isTableSeparator(rowLine) == false else { break }
            rows.append(tableCells(from: rowLine).map(InlineContent.init(markdown:)))
            index += 1
        }

        return (Table(headers: headers, rows: rows), index)
    }

    private static func isTableRow(_ line: String) -> Bool {
        line.hasPrefix("|") && line.dropFirst().contains("|")
    }

    private static func isTableSeparator(_ line: String) -> Bool {
        guard isTableRow(line) else { return false }
        let cells = tableCells(from: line)
        guard cells.isEmpty == false else { return false }
        return cells.allSatisfy { cell in
            let trimmed = cell.trimmingCharacters(in: .whitespaces)
            let withoutAlignment = trimmed.trimmingCharacters(in: CharacterSet(charactersIn: ":"))
            return withoutAlignment.count >= 3 && withoutAlignment.allSatisfy { $0 == "-" }
        }
    }

    private static func tableCells(from line: String) -> [String] {
        var trimmed = line.trimmingCharacters(in: .whitespaces)
        if trimmed.hasPrefix("|") {
            trimmed.removeFirst()
        }
        if trimmed.hasSuffix("|") {
            trimmed.removeLast()
        }
        return trimmed
            .split(separator: "|", omittingEmptySubsequences: false)
            .map { String($0).trimmingCharacters(in: .whitespaces) }
    }
}

struct MarkdownSearchHighlightPresentation: Equatable {
    static func blockContainsQuery(
        _ block: DailyMarkdownRenderer.Block,
        query: String?
    ) -> Bool {
        textContainsQuery(blockPlainText(block), query: query)
    }

    static func textContainsQuery(
        _ text: String,
        query: String?
    ) -> Bool {
        let normalizedText = text.lowercased()
        return SearchHighlightedTextPresentation.highlightTerms(for: query).contains { term in
            normalizedText.contains(term.lowercased())
        }
    }

    private static func blockPlainText(_ block: DailyMarkdownRenderer.Block) -> String {
        switch block {
        case .heading(_, let content):
            return content.plainText
        case .paragraph(let content):
            return content.plainText
        case .bulletList(let items):
            return items.map(\.plainText).joined(separator: "\n")
        case .orderedList(let items):
            return items.map(\.content.plainText).joined(separator: "\n")
        case .taskList(let items):
            return items.map(\.content.plainText).joined(separator: "\n")
        case .quote(let items):
            return items.map(\.plainText).joined(separator: "\n")
        case .codeBlock(let code):
            return code
        case .table(let table):
            return (table.headers + table.rows.flatMap { $0 })
                .map(\.plainText)
                .joined(separator: "\n")
        }
    }
}

struct SearchHighlightedTextPresentation: Equatable {
    static func highlightedAttributedString(
        _ text: String,
        query: String?
    ) -> AttributedString {
        highlightedAttributedString(AttributedString(text), query: query)
    }

    static func highlightedAttributedString(
        _ attributed: AttributedString,
        query: String?
    ) -> AttributedString {
        var highlighted = attributed
        for term in highlightTerms(for: query) {
            applyHighlight(term: term, to: &highlighted)
        }
        return highlighted
    }

    private static func applyHighlight(
        term: String,
        to attributed: inout AttributedString
    ) {
        var searchRange = attributed.startIndex..<attributed.endIndex
        while let match = attributed[searchRange].range(
            of: term,
            options: [.caseInsensitive, .diacriticInsensitive]
        ) {
            attributed[match].backgroundColor = Color.yellow.opacity(0.55)
            attributed[match].foregroundColor = .primary
            searchRange = match.upperBound..<attributed.endIndex
        }
    }

    static func highlightTerms(for query: String?) -> [String] {
        let normalized = query?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard normalized.isEmpty == false else { return [] }

        let tokens = normalized
            .components(separatedBy: CharacterSet.whitespacesAndNewlines.union(.punctuationCharacters))
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { $0.isEmpty == false }

        return ([normalized] + tokens).reduce(into: []) { terms, term in
            guard terms.contains(where: { $0.caseInsensitiveCompare(term) == .orderedSame }) == false else {
                return
            }
            terms.append(term)
        }
    }
}

struct MarkdownPreviewContent: View {
    let markdown: String
    var highlightQuery: String? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ForEach(Array(DailyMarkdownRenderer.blocks(from: markdown).enumerated()), id: \.offset) { _, block in
                MarkdownBlockView(
                    block: block,
                    isSearchHighlighted: MarkdownSearchHighlightPresentation.blockContainsQuery(
                        block,
                        query: highlightQuery
                    ),
                    highlightQuery: highlightQuery
                )
            }
        }
        .multilineTextAlignment(.leading)
        .textSelection(.enabled)
        .allowsHitTesting(false)
    }
}

private struct MarkdownBlockView: View {
    let block: DailyMarkdownRenderer.Block
    var isSearchHighlighted = false
    var highlightQuery: String? = nil

    var body: some View {
        blockBody
            .padding(isSearchHighlighted ? 8 : 0)
            .background(
                isSearchHighlighted
                    ? Color.yellow.opacity(0.16)
                    : Color.clear
            )
            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
    }

    @ViewBuilder
    private var blockBody: some View {
        switch block {
        case .heading(let level, let content):
            inlineText(content)
                .font(headingFont(for: level))
                .fontWeight(.semibold)
                .padding(.top, level == 1 ? 10 : 4)
        case .paragraph(let content):
            inlineText(content)
                .font(.body)
                .lineSpacing(3)
        case .bulletList(let items):
            VStack(alignment: .leading, spacing: 8) {
                ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                    HStack(alignment: .top, spacing: 10) {
                        Text("\u{2022}")
                            .font(.body.weight(.semibold))
                            .padding(.top, 1)
                        inlineText(item)
                            .font(.body)
                            .lineSpacing(3)
                    }
                }
            }
        case .orderedList(let items):
            VStack(alignment: .leading, spacing: 8) {
                ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                    HStack(alignment: .top, spacing: 10) {
                        Text("\(item.index).")
                            .font(.body.weight(.semibold))
                            .foregroundStyle(.secondary)
                        inlineText(item.content)
                            .font(.body)
                            .lineSpacing(3)
                    }
                }
            }
        case .taskList(let items):
            VStack(alignment: .leading, spacing: 8) {
                ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                    HStack(alignment: .top, spacing: 10) {
                        Image(systemName: item.isCompleted ? "checkmark.square.fill" : "square")
                            .foregroundStyle(item.isCompleted ? Color.accentColor : Color.secondary)
                            .padding(.top, 2)
                        inlineText(item.content)
                            .font(.body)
                            .lineSpacing(3)
                    }
                }
            }
        case .quote(let items):
            VStack(alignment: .leading, spacing: 8) {
                ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                    inlineText(item)
                        .font(.body)
                        .italic()
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.leading, 14)
            .overlay(alignment: .leading) {
                Rectangle()
                    .fill(Color.secondary.opacity(0.35))
                    .frame(width: 3)
            }
        case .codeBlock(let code):
            ScrollView(.horizontal, showsIndicators: false) {
                Text(verbatim: code)
                    .font(.system(.body, design: .monospaced))
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(12)
            .background(Color.primary.opacity(0.06))
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        case .table(let table):
            DailyMarkdownTableView(table: table, highlightQuery: highlightQuery)
        }
    }

    @ViewBuilder
    private func inlineText(_ content: DailyMarkdownRenderer.InlineContent) -> some View {
        if let attributed = content.attributed {
            Text(SearchHighlightedTextPresentation.highlightedAttributedString(
                attributed,
                query: highlightQuery
            ))
        } else {
            Text(SearchHighlightedTextPresentation.highlightedAttributedString(
                content.plainText,
                query: highlightQuery
            ))
        }
    }

    private func headingFont(for level: Int) -> Font {
        switch level {
        case 1:
            return .title2
        case 2:
            return .title3
        case 3:
            return .headline
        default:
            return .body
        }
    }
}

private struct DailyMarkdownTableView: View {
    let table: DailyMarkdownRenderer.Table
    let highlightQuery: String?

    var body: some View {
        ScrollView(.horizontal, showsIndicators: true) {
            Grid(alignment: .leading, horizontalSpacing: 0, verticalSpacing: 0) {
                GridRow {
                    ForEach(Array(table.headers.enumerated()), id: \.offset) { _, header in
                        cell(header, isHeader: true)
                    }
                }
                ForEach(Array(table.rows.enumerated()), id: \.offset) { _, row in
                    GridRow {
                        ForEach(0..<table.headers.count, id: \.self) { index in
                            cell(
                                row.indices.contains(index) ? row[index] : DailyMarkdownRenderer.InlineContent(markdown: ""),
                                isHeader: false
                            )
                        }
                    }
                }
            }
            .overlay {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(Color.secondary.opacity(0.22), lineWidth: 1)
            }
        }
    }

    private func cell(_ content: DailyMarkdownRenderer.InlineContent, isHeader: Bool) -> some View {
        MarkdownBlockView(
            block: .paragraph(content),
            isSearchHighlighted: MarkdownSearchHighlightPresentation.textContainsQuery(
                content.plainText,
                query: highlightQuery
            ),
            highlightQuery: highlightQuery
        )
            .font(isHeader ? .body.weight(.semibold) : .body)
            .frame(minWidth: 140, maxWidth: 260, alignment: .topLeading)
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(isHeader ? Color.secondary.opacity(0.08) : Color.clear)
            .border(Color.secondary.opacity(0.18), width: 0.5)
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

                            if selectedParagraph == nil {
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
                SourceBrandIcon(brand: SourceBrandResolver.resolve(appName: event.sourceApp))
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

private struct SourceBrandIcon: View {
    let brand: SourceBrand

    var body: some View {
        Group {
            switch brand.glyph {
            case .asset(let assetName):
                if let image = NSImage(named: assetName) {
                    Image(nsImage: image)
                        .resizable()
                        .scaledToFit()
                } else {
                    Image(systemName: brand.fallbackSymbol.rawValue)
                        .resizable()
                        .scaledToFit()
                        .foregroundStyle(.secondary)
                }
            case .symbol(let symbol):
                Image(systemName: symbol.rawValue)
                    .resizable()
                    .scaledToFit()
                    .foregroundStyle(.secondary)
            }
        }
        .frame(width: 14, height: 14)
    }
}

private extension Character {
    var isChineseIdeograph: Bool {
        unicodeScalars.contains { scalar in
            (0x4E00...0x9FFF).contains(scalar.value)
        }
    }
}
