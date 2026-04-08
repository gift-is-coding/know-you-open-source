import Foundation

enum OnboardingStep: Int, CaseIterable {
    case intro
    case capture
    case safety
    case preview
    case permissions

    static let storyFlow: [OnboardingStep] = [
        .intro,
        .capture,
        .safety,
        .preview,
        .permissions
    ]

    var next: OnboardingStep? {
        switch self {
        case .intro: .capture
        case .capture: .safety
        case .safety: .preview
        case .preview: .permissions
        case .permissions: nil
        }
    }

    var previous: OnboardingStep? {
        switch self {
        case .intro: nil
        case .capture: .intro
        case .safety: .capture
        case .preview: .safety
        case .permissions: .preview
        }
    }

    var isFirst: Bool { previous == nil }
    var isLast: Bool { next == nil }
}

struct OnboardingPreviewEntry: Equatable {
    let time: String
    let paragraph: String
    let sources: [String]
}

struct OnboardingPreview: Equatable {
    let title: String
    let entries: [OnboardingPreviewEntry]
}

struct OnboardingStepContent {
    let title: String
    let body: String
    let caption: String
    let bullets: [String]
    let primaryCTA: String
    let preview: OnboardingPreview?
}

enum OnboardingContent {
    static func content(for step: OnboardingStep) -> OnboardingStepContent {
        switch step {
        case .intro:
            return OnboardingStepContent(
                title: "Meet Know You",
                body: "A calm daily story, built from the moments already happening on your Mac.",
                caption: "Stored as Markdown on this Mac first, so trust starts before setup does.",
                bullets: [],
                primaryCTA: "Show me the story",
                preview: nil
            )
        case .capture:
            return OnboardingStepContent(
                title: "A day starts taking shape",
                body: "From the first copied note to the last notification at night, Know You gathers the signal already around you.",
                caption: "Clipboard and notifications become a day you can actually revisit.",
                bullets: [
                    "The quick copy from a morning planning note",
                    "The reminder that pulled you back into the afternoon",
                    "The late tab, message, or snippet that closed the loop",
                ],
                primaryCTA: "How it stays private",
                preview: nil
            )
        case .safety:
            return OnboardingStepContent(
                title: "Private before it becomes a story",
                body: "Before anything is saved, filtering keeps sensitive data out. Claude can help shape the story, Openclaw can help with local processing, and optional sync is there only if you want it.",
                caption: "Local-first by default, with extra help only when you ask for it.",
                bullets: [
                    "Filtering happens before storage",
                    "Claude can help summarize safely",
                    "Openclaw keeps the workflow local",
                ],
                primaryCTA: "Show me a real preview",
                preview: nil
            )
        case .preview:
            return OnboardingStepContent(
                title: "Preview a believable day",
                body: "The preview reads like the app itself: a short diary arc from morning to night with the source apps nearby.",
                caption: "Close to the real reader, not a detached marketing mock.",
                bullets: [
                    "See the diary before it lands in your archive",
                    "Keep the nearby apps visible for confidence",
                ],
                primaryCTA: "Set up permissions",
                preview: OnboardingPreview(
                    title: "Friday, April 10",
                    entries: [
                        OnboardingPreviewEntry(
                            time: "8:10 AM",
                            paragraph: "The morning started quietly in Notes, then a copied outline and a Calendar nudge turned the first hour into a clear plan instead of a scramble.",
                            sources: ["Notes", "Calendar", "Clipboard"]
                        ),
                        OnboardingPreviewEntry(
                            time: "1:45 PM",
                            paragraph: "By early afternoon, GitHub reviews, Slack replies, and one saved snippet kept the work moving even as the day kept changing shape.",
                            sources: ["GitHub", "Slack", "Clipboard"]
                        ),
                        OnboardingPreviewEntry(
                            time: "10:18 PM",
                            paragraph: "At night, Safari tabs, Messages, and one last copied thought closed the loop, leaving a day that felt lived before it was ever written down.",
                            sources: ["Safari", "Messages", "Clipboard"]
                        ),
                    ]
                )
            )
        case .permissions:
            return OnboardingStepContent(
                title: "Finish the first-run setup",
                body: "Grant the remaining permissions, choose where the vault lives, and start building your private day-by-day memory.",
                caption: "You can change permissions later in Settings.",
                bullets: [
                    "Clipboard access stays automatic",
                    "Notification import may need Full Disk Access",
                ],
                primaryCTA: "Start my first story",
                preview: nil
            )
        }
    }
}
