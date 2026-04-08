import Foundation

enum OnboardingStep: Int, CaseIterable {
    case intro
    case capture
    case safety
    case preview
    case permissions
}

struct OnboardingStepContent {
    let title: String
    let body: String
    let caption: String
    let bullets: [String]
    let primaryCTA: String
}

enum OnboardingContent {
    static func content(for step: OnboardingStep) -> OnboardingStepContent {
        switch step {
        case .intro:
            return OnboardingStepContent(
                title: "Meet Know You",
                body: "Turn the moments you already live on your Mac into a private daily story.",
                caption: "Write in Markdown and keep everything on your own Mac.",
                bullets: [],
                primaryCTA: "Continue"
            )
        case .capture:
            return OnboardingStepContent(
                title: "Capture what matters",
                body: "Know You watches the signal you already create and collects the useful bits without extra work.",
                caption: "Automatic, low-friction capture.",
                bullets: [
                    "Clipboard snippets you actually need",
                    "Notifications worth remembering",
                ],
                primaryCTA: "Continue"
            )
        case .safety:
            return OnboardingStepContent(
                title: "Stay safe by default",
                body: "Before anything is saved, filtering keeps sensitive data out. Claude can help shape the story, Openclaw can help with local processing, and optional sync is there only if you want it.",
                caption: "Private first.",
                bullets: [
                    "Filtering happens before storage",
                    "Claude can help summarize safely",
                    "Openclaw keeps the workflow local",
                ],
                primaryCTA: "Continue"
            )
        case .preview:
            return OnboardingStepContent(
                title: "Preview the day",
                body: "See the story before it becomes part of your archive and adjust the tone if needed.",
                caption: "Review before saving.",
                bullets: [
                    "Check the draft for accuracy",
                    "Tune the story style",
                ],
                primaryCTA: "Continue"
            )
        case .permissions:
            return OnboardingStepContent(
                title: "Finish setup",
                body: "Grant the remaining permissions and start building a day-by-day memory of your life.",
                caption: "You can change permissions later in Settings.",
                bullets: [
                    "Clipboard access stays automatic",
                    "Notification import may need Full Disk Access",
                ],
                primaryCTA: "Start remembering my days"
            )
        }
    }
}
