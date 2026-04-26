import Foundation

enum OnboardingStep: Int, CaseIterable {
    case demoRead
    case demoClick
    case demoReference
    case privacy
    case permissions
    case enginePrompt
    case engineSetup
    case generating

    static let storyFlow: [OnboardingStep] = [
        .demoRead,
        .demoClick,
        .demoReference,
        .privacy,
        .permissions,
        .enginePrompt,
        .engineSetup,
        .generating
    ]

    var next: OnboardingStep? {
        guard let index = Self.storyFlow.firstIndex(of: self), index + 1 < Self.storyFlow.count else {
            return nil
        }

        return Self.storyFlow[index + 1]
    }

    var previous: OnboardingStep? {
        guard let index = Self.storyFlow.firstIndex(of: self), index > 0 else {
            return nil
        }

        return Self.storyFlow[index - 1]
    }

    var isFirst: Bool { previous == nil }
    var isLast: Bool { next == nil }
}

enum OnboardingRequirement: String, Equatable, Hashable {
    case fullDiskAccess
}

enum OnboardingEnhancementKind: Equatable {
    case voiceInput
}

enum OnboardingRecommendedBehavior: Equatable, Hashable {
    case launchAtLogin

    var isRecommendedDefault: Bool {
        switch self {
        case .launchAtLogin:
            return true
        }
    }
}

enum OnboardingLifecycleAction: Equatable, Hashable {
    case autoAdvanceToFirstGeneration
}

enum OnboardingStepProgression: Equatable {
    case continueFlow
    case automaticGeneration
}

enum OnboardingCoachmarkTarget: Equatable, Hashable {
    case storyPanel
    case sourcesPanel
    case sharedCenterCard
    case engineButton
    case engineSheet
}

struct OnboardingHelperLink: Equatable, Identifiable {
    let title: String
    let detail: String
    let url: URL
    let iconURL: URL?

    var id: URL { url }
}

struct OnboardingOptionalEnhancement: Equatable {
    let title: String
    let detail: String
    let enhancementKind: OnboardingEnhancementKind
    let helperLinks: [OnboardingHelperLink]
}

struct OnboardingStepContent {
    let iconName: String
    let title: String
    let body: String
    let primaryCTA: String
    let target: OnboardingCoachmarkTarget
    let activationStepLabel: String?
    let activationFollowupLabel: String?
    let helperLinks: [OnboardingHelperLink]
    let blockingGate: OnboardingRequirement?
    let optionalEnhancement: OnboardingOptionalEnhancement?
    let recommendedBehavior: OnboardingRecommendedBehavior?
    let lifecycleAction: OnboardingLifecycleAction?
    let progression: OnboardingStepProgression
    let requiresParagraphSelection: Bool
    let requiresEngineButtonTap: Bool
    let requiresEngineConfiguration: Bool

    var blocksProgress: Bool {
        blockingGate != nil
    }

    var blockingRequirement: OnboardingRequirement? {
        blockingGate
    }

    var autoStartsFirstGeneration: Bool {
        progression == .automaticGeneration
    }

    var showsManualRefreshAction: Bool {
        false
    }

    var showsContinueAction: Bool {
        progression == .continueFlow
    }

    var usesSharedCenterCard: Bool {
        target == .sharedCenterCard
    }
}

enum OnboardingContent {
    static let blockingGateStep: OnboardingStep = .permissions

    private static let voiceLinks = [
        OnboardingHelperLink(
            title: "Typeless",
            detail: "AI voice dictation for Mac that can add richer clipboard context. Optional, install later.",
            url: URL(string: "https://www.typeless.com/downloads")!,
            iconURL: URL(string: "https://www.typeless.com/favicon.ico")
        ),
        OnboardingHelperLink(
            title: "Shandianshuo",
            detail: "Local-first voice input for Mac. Optional, install later.",
            url: URL(string: "https://shandianshuo.cn/")!,
            iconURL: URL(string: "https://shandianshuo.cn/apple-touch-icon.png?v=3")
        )
    ]

    static func content(for step: OnboardingStep) -> OnboardingStepContent {
        switch step {
        case .demoRead:
            return OnboardingStepContent(
                iconName: "book.closed.fill",
                title: "Start with this demo day",
                body: "Read the diary in the middle.",
                primaryCTA: "Continue",
                target: .storyPanel,
                activationStepLabel: nil,
                activationFollowupLabel: nil,
                helperLinks: [],
                blockingGate: nil,
                optionalEnhancement: nil,
                recommendedBehavior: nil,
                lifecycleAction: nil,
                progression: .continueFlow,
                requiresParagraphSelection: false,
                requiresEngineButtonTap: false,
                requiresEngineConfiguration: false
            )

        case .demoClick:
            return OnboardingStepContent(
                iconName: "hand.tap.fill",
                title: "Click any paragraph in the story",
                body: "Click one paragraph in the middle.",
                primaryCTA: "",
                target: .storyPanel,
                activationStepLabel: nil,
                activationFollowupLabel: nil,
                helperLinks: [],
                blockingGate: nil,
                optionalEnhancement: nil,
                recommendedBehavior: nil,
                lifecycleAction: nil,
                progression: .continueFlow,
                requiresParagraphSelection: true,
                requiresEngineButtonTap: false,
                requiresEngineConfiguration: false
            )

        case .demoReference:
            return OnboardingStepContent(
                iconName: "link.circle.fill",
                title: "The right side shows the source",
                body: "These references come from notifications and your input.",
                primaryCTA: "Continue",
                target: .sourcesPanel,
                activationStepLabel: nil,
                activationFollowupLabel: nil,
                helperLinks: [],
                blockingGate: nil,
                optionalEnhancement: nil,
                recommendedBehavior: nil,
                lifecycleAction: nil,
                progression: .continueFlow,
                requiresParagraphSelection: false,
                requiresEngineButtonTap: false,
                requiresEngineConfiguration: false
            )

        case .privacy:
            return OnboardingStepContent(
                iconName: "lock.shield.fill",
                title: "Everything stays local as Markdown",
                body: "Every file stays on this Mac as local Markdown. No Know You server.",
                primaryCTA: "Continue",
                target: .sharedCenterCard,
                activationStepLabel: nil,
                activationFollowupLabel: nil,
                helperLinks: [],
                blockingGate: nil,
                optionalEnhancement: nil,
                recommendedBehavior: nil,
                lifecycleAction: nil,
                progression: .continueFlow,
                requiresParagraphSelection: false,
                requiresEngineButtonTap: false,
                requiresEngineConfiguration: false
            )

        case .permissions:
            return OnboardingStepContent(
                iconName: "checkmark.shield.fill",
                title: "1/2 Turn on permissions",
                body: "Only two steps left.\n\nKnow You rebuilds your diary from notifications and clipboard context. Turn on Full Disk Access to read local history. Notifications are only used for the 8:30 PM daily review reminder.",
                primaryCTA: "I turned it on",
                target: .sharedCenterCard,
                activationStepLabel: "1/2",
                activationFollowupLabel: "2/2 Configure engine",
                helperLinks: voiceLinks,
                blockingGate: .fullDiskAccess,
                optionalEnhancement: OnboardingOptionalEnhancement(
                    title: "Optional: add richer context with voice input",
                    detail: "Voice tools often copy dictated text into the clipboard, which gives Know You more context.",
                    enhancementKind: .voiceInput,
                    helperLinks: voiceLinks
                ),
                recommendedBehavior: nil,
                lifecycleAction: nil,
                progression: .continueFlow,
                requiresParagraphSelection: false,
                requiresEngineButtonTap: false,
                requiresEngineConfiguration: false
            )

        case .enginePrompt:
            return OnboardingStepContent(
                iconName: "sparkles.rectangle.stack.fill",
                title: "2/2 Configure engine",
                body: "Click the highlighted button to choose your default engine.",
                primaryCTA: "",
                target: .engineButton,
                activationStepLabel: "2/2",
                activationFollowupLabel: nil,
                helperLinks: [],
                blockingGate: nil,
                optionalEnhancement: nil,
                recommendedBehavior: .launchAtLogin,
                lifecycleAction: nil,
                progression: .continueFlow,
                requiresParagraphSelection: false,
                requiresEngineButtonTap: true,
                requiresEngineConfiguration: false
            )

        case .engineSetup:
            return OnboardingStepContent(
                iconName: "cpu.fill",
                title: "Choose the engine you already use",
                body: "Finish setup here. Your first real diary starts right after.",
                primaryCTA: "Start my diary",
                target: .engineSheet,
                activationStepLabel: "2/2",
                activationFollowupLabel: nil,
                helperLinks: [],
                blockingGate: nil,
                optionalEnhancement: nil,
                recommendedBehavior: .launchAtLogin,
                lifecycleAction: nil,
                progression: .continueFlow,
                requiresParagraphSelection: false,
                requiresEngineButtonTap: false,
                requiresEngineConfiguration: true
            )

        case .generating:
            return OnboardingStepContent(
                iconName: "wand.and.stars.inverse",
                title: "We’re generating your first real diary",
                body: "Know You is importing your local context and writing your first diary.",
                primaryCTA: "Generating",
                target: .sharedCenterCard,
                activationStepLabel: nil,
                activationFollowupLabel: nil,
                helperLinks: [],
                blockingGate: nil,
                optionalEnhancement: nil,
                recommendedBehavior: nil,
                lifecycleAction: .autoAdvanceToFirstGeneration,
                progression: .automaticGeneration,
                requiresParagraphSelection: false,
                requiresEngineButtonTap: false,
                requiresEngineConfiguration: false
            )
        }
    }
}
