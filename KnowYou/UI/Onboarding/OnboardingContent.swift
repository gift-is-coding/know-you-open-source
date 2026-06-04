import Foundation

enum OnboardingStep: Int, CaseIterable {
    case demoRead
    case demoClick
    case demoReference
    case privacy
    case installApp
    case permissions
    case enginePrompt
    case engineSetup
    case generating

    static let storyFlow: [OnboardingStep] = [
        .demoRead,
        .demoClick,
        .demoReference,
        .privacy,
        .installApp,
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
    case applicationInstalled
    case fullDiskAccess
}

struct OnboardingApplicationInstallPolicy {
    static let productionTargetBundleURL = URL(fileURLWithPath: "/Applications/KnowYou.app", isDirectory: true)
    static let newUserTargetBundleURL = URL(fileURLWithPath: "/Applications/KnowYou New User.app", isDirectory: true)
    private static let acceptedApplicationsDirectories: Set<String> = [
        "/Applications",
        "/System/Volumes/Data/Applications",
    ]

    static var targetBundleURL: URL {
        targetBundleURL(bundleIdentifier: Bundle.main.bundleIdentifier)
    }

    static func targetBundleURL(bundleIdentifier: String?) -> URL {
        if bundleIdentifier == AppRuntimeProfile.newUserBundleIdentifier {
            return newUserTargetBundleURL
        }
        return productionTargetBundleURL
    }

    static func isInstalledInApplications(bundleURL: URL) -> Bool {
        isInstalledInApplications(bundleURL: bundleURL, bundleIdentifier: Bundle.main.bundleIdentifier)
    }

    static func isInstalledInApplications(bundleURL: URL, bundleIdentifier: String?) -> Bool {
        let expectedBundleURL = targetBundleURL(bundleIdentifier: bundleIdentifier).standardizedFileURL
        let candidateURL = bundleURL.standardizedFileURL
        return candidateURL.lastPathComponent == expectedBundleURL.lastPathComponent
            && acceptedApplicationsDirectories.contains(candidateURL.deletingLastPathComponent().path)
    }
}

struct OnboardingPermissionBypassPolicy {
    static let developmentBypassDefaultsKey = "onboardingFullDiskAccessDevelopmentBypass"

    static func allowsFullDiskAccessBypass(bundleURL: URL) -> Bool {
        let components = Set(bundleURL.pathComponents)
        return components.contains("DerivedData")
            && components.contains("Build")
            && components.contains("Products")
            && components.contains("Debug")
    }

    static func hasStoredDevelopmentBypass(bundleURL: URL, userDefaults: UserDefaults = .standard) -> Bool {
        allowsFullDiskAccessBypass(bundleURL: bundleURL)
            && userDefaults.bool(forKey: developmentBypassDefaultsKey)
    }

    static func storeDevelopmentBypass(bundleURL: URL, userDefaults: UserDefaults = .standard) {
        guard allowsFullDiskAccessBypass(bundleURL: bundleURL) else { return }
        userDefaults.set(true, forKey: developmentBypassDefaultsKey)
    }
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

struct OnboardingFullDiskAccessGuidance: Equatable {
    let missingPermissionDetail: String
    let manualAddInstruction: String
    let openSettingsButtonTitle: String
    let revealAppButtonTitle: String
    let recheckButtonTitle: String
    let visualAssetName: String
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

enum OnboardingHistoryBootstrapConfirmation {
    static let title = "Your first 3 days are being prepared"
    static let message = "**KnowYou** will generate your recent 3 days from available history on this Mac only. All local. No backend server. This may take a few minutes."
    static let confirmButtonTitle = "Start generating"
}

enum OnboardingContent {
    static let blockingGateStep: OnboardingStep = .permissions
    static let fullDiskAccessGuidance = OnboardingFullDiskAccessGuidance(
        missingPermissionDetail: "Open Full Disk Access. If KnowYou is not listed, click + and choose the app from Applications.",
        manualAddInstruction: "If KnowYou does not appear in the list, click + in Full Disk Access and choose this app. Use the button below to reveal the exact app bundle.",
        openSettingsButtonTitle: "Open Full Disk Access",
        revealAppButtonTitle: "Show App to Add",
        recheckButtonTitle: "Check Again",
        visualAssetName: "FullDiskAccessAddGuide"
    )

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
                body: "Every file stays on this Mac as local Markdown. No KnowYou server.",
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

        case .installApp:
            return OnboardingStepContent(
                iconName: "arrow.down.app.fill",
                title: "Move KnowYou to Applications",
                body: "Install KnowYou at /Applications/KnowYou.app before granting permissions. This keeps macOS privacy permissions attached to the stable app.",
                primaryCTA: "Move to Applications and Relaunch",
                target: .sharedCenterCard,
                activationStepLabel: nil,
                activationFollowupLabel: nil,
                helperLinks: [],
                blockingGate: .applicationInstalled,
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
                body: "Only two steps left.\n\nKnowYou rebuilds your diary from notifications and clipboard context. Turn on Full Disk Access to read local history. Notifications are only used for the 8:30 PM daily review reminder.",
                primaryCTA: "I turned it on",
                target: .sharedCenterCard,
                activationStepLabel: "1/2",
                activationFollowupLabel: "2/2 Configure engine",
                helperLinks: voiceLinks,
                blockingGate: .fullDiskAccess,
                optionalEnhancement: OnboardingOptionalEnhancement(
                    title: "Optional: add richer context with voice input",
                    detail: "Voice tools often copy dictated text into the clipboard, which gives KnowYou more context.",
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
                body: "Finish setup here. Your first 3 days start generating right after.",
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
                title: "We’re preparing your first 3 days",
                body: "KnowYou will write your recent 3 days from available history on this Mac only. All local. No backend server.",
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
