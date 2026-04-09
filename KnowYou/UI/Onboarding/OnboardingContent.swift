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

struct OnboardingValueRow: Equatable {
    let title: String
    let detail: String
}

struct OnboardingHelperLink: Equatable {
    let title: String
    let url: URL
}

struct OnboardingStepContent {
    let title: String
    let body: String
    let caption: String
    let bullets: [String]
    let primaryCTA: String
    let preview: OnboardingPreview?
    let valueRows: [OnboardingValueRow]
    let helperLinks: [OnboardingHelperLink]
    let settingsNudge: String?
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
                preview: nil,
                valueRows: [],
                helperLinks: [],
                settingsNudge: nil
            )
        case .capture:
            return OnboardingStepContent(
                title: "A day starts taking shape",
                body: "From the first copied note to the last notification at night, Know You captures the signal around you automatically.",
                caption: "Clipboard and notifications become a day you can actually revisit.",
                bullets: [
                    "The quick copy from a morning planning note",
                    "The reminder that pulled you back into the afternoon",
                    "The late tab, message, or snippet that closed the loop",
                ],
                primaryCTA: "How it stays private",
                preview: nil,
                valueRows: [],
                helperLinks: [],
                settingsNudge: nil
            )
        case .safety:
            return OnboardingStepContent(
                title: "Private before it becomes a story",
                body: "Before anything is saved, filtering keeps sensitive data out. Sensitive items should not be retained in local Markdown files or uploaded in cloud sync.",
                caption: "You can now or later sync filtered Markdown files to Openclaw or Claude for better agent memory and context.",
                bullets: [
                    "Filtering happens before storage",
                    "Capture stays automatic even while filtering protects the archive",
                    "Sync is optional and improves agent memory and context when you want it",
                ],
                primaryCTA: "Show me a real preview",
                preview: nil,
                valueRows: [],
                helperLinks: [],
                settingsNudge: nil
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
                ),
                valueRows: [],
                helperLinks: [],
                settingsNudge: nil
            )
        case .permissions:
            return OnboardingStepContent(
                title: "Turn on the signals that let Know You rebuild your day",
                body: "Each permission fills in a specific part of the story. Know You explains the value first so local-reading access never feels abstract.",
                caption: "Your files stay local as Markdown, and Settings is the place to revisit permissions or add an optional summarizer later.",
                bullets: [
                    "Clipboard capture is automatic",
                    "Notifications are captured automatically after Full Disk Access is granted",
                    "Sensitive details are filtered before anything is kept locally or synced",
                ],
                primaryCTA: "Start my first story",
                preview: nil,
                valueRows: [
                    OnboardingValueRow(
                        title: "Clipboard fills in what you were reading and writing",
                        detail: "Copied text is captured automatically, so short notes, snippets, and pasted ideas can anchor the story without extra effort."
                    ),
                    OnboardingValueRow(
                        title: "Notifications explain who reached you and when",
                        detail: "Full Disk Access lets Know You read the local Notification Center store on this Mac so reminders and replies show up in the right place."
                    ),
                    OnboardingValueRow(
                        title: "Voice tools can feed context through the clipboard",
                        detail: "If you dictate into a clipboard-friendly helper, Know You can pick up that text automatically just like any other copied note."
                    ),
                ],
                helperLinks: [
                    OnboardingHelperLink(
                        title: "Maccy clipboard helper",
                        url: URL(string: "https://maccy.app/")!
                    ),
                    OnboardingHelperLink(
                        title: "MacWhisper voice input helper",
                        url: URL(string: "https://www.macwhisper.com/")!
                    ),
                ],
                settingsNudge: "Summarizer setup is optional. Finish onboarding first, then open Settings whenever you want Claude, Codex, Gemini, or OpenAI help with story drafting."
            )
        }
    }
}
