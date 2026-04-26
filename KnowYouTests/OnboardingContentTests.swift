import XCTest
@testable import KnowYou

final class OnboardingContentTests: XCTestCase {
    func testOnboardingStepStoryFlowUsesTheRealReaderCoachmarkOrder() {
        XCTAssertEqual(
            OnboardingStep.storyFlow,
            [.demoRead, .demoClick, .demoReference, .privacy, .permissions, .enginePrompt, .engineSetup, .generating]
        )
    }

    func testOnboardingStepNavigationContractUsesTheCoachmarkFlow() {
        XCTAssertTrue(OnboardingStep.demoRead.isFirst)
        XCTAssertEqual(OnboardingStep.demoRead.next, .demoClick)

        XCTAssertEqual(OnboardingStep.demoClick.previous, .demoRead)
        XCTAssertEqual(OnboardingStep.demoClick.next, .demoReference)

        XCTAssertEqual(OnboardingStep.demoReference.previous, .demoClick)
        XCTAssertEqual(OnboardingStep.demoReference.next, .privacy)

        XCTAssertEqual(OnboardingStep.privacy.previous, .demoReference)
        XCTAssertEqual(OnboardingStep.privacy.next, .permissions)

        XCTAssertEqual(OnboardingStep.permissions.previous, .privacy)
        XCTAssertEqual(OnboardingStep.permissions.next, .enginePrompt)

        XCTAssertEqual(OnboardingStep.enginePrompt.previous, .permissions)
        XCTAssertEqual(OnboardingStep.enginePrompt.next, .engineSetup)

        XCTAssertEqual(OnboardingStep.engineSetup.previous, .enginePrompt)
        XCTAssertEqual(OnboardingStep.engineSetup.next, .generating)

        XCTAssertEqual(OnboardingStep.generating.previous, .engineSetup)
        XCTAssertTrue(OnboardingStep.generating.isLast)
        XCTAssertNil(OnboardingStep.generating.next)
    }

    func testDemoClickTargetsTheRealStoryAreaAndRequiresARealParagraphSelection() {
        let content = OnboardingContent.content(for: .demoClick)

        XCTAssertEqual(content.target, .storyPanel)
        XCTAssertTrue(content.requiresParagraphSelection)
        XCTAssertFalse(content.blocksProgress)
    }

    func testReferenceStepTargetsTheRealSourcesAreaAndExplainsWhereContextComesFrom() {
        let content = OnboardingContent.content(for: .demoReference)

        XCTAssertEqual(content.target, .sourcesPanel)
        XCTAssertFalse(content.requiresParagraphSelection)
        XCTAssertFalse(content.blocksProgress)
        XCTAssertNil(content.blockingRequirement)
        XCTAssertEqual(content.body, "These references come from notifications and your input.")
    }

    func testPrivacyAndPermissionsReuseTheSharedCenteredCard() {
        let privacy = OnboardingContent.content(for: .privacy)
        let permissions = OnboardingContent.content(for: .permissions)

        XCTAssertEqual(privacy.target, .sharedCenterCard)
        XCTAssertEqual(permissions.target, .sharedCenterCard)
        XCTAssertTrue(privacy.usesSharedCenterCard)
        XCTAssertTrue(permissions.usesSharedCenterCard)
    }

    func testPermissionStepFramesActivationAsOnlyTwoRemainingSteps() {
        let content = OnboardingContent.content(for: .permissions)

        XCTAssertEqual(content.blockingRequirement, .fullDiskAccess)
        XCTAssertEqual(content.activationStepLabel, "1/2")
        XCTAssertEqual(content.activationFollowupLabel, "2/2 Configure engine")
        XCTAssertTrue(content.body.contains("Only two steps left"))
        XCTAssertTrue(content.body.contains("Full Disk Access"))
        XCTAssertTrue(content.body.contains("8:30 PM"))
        XCTAssertTrue(content.body.contains("daily review reminder"))
        XCTAssertTrue(content.body.localizedCaseInsensitiveContains("clipboard"))
        XCTAssertTrue(content.blocksProgress)
        XCTAssertEqual(content.optionalEnhancement?.helperLinks.count, 2)
        XCTAssertEqual(content.optionalEnhancement?.helperLinks.map(\.title), ["Typeless", "Shandianshuo"])
    }

    func testEnginePromptUsesTheRealButtonInsteadOfEmbeddingTheForm() {
        let content = OnboardingContent.content(for: .enginePrompt)

        XCTAssertEqual(content.target, .engineButton)
        XCTAssertTrue(content.requiresEngineButtonTap)
        XCTAssertEqual(content.activationStepLabel, "2/2")
        XCTAssertFalse(content.blocksProgress)
        XCTAssertEqual(content.body, "Click the highlighted button to choose your default engine.")
    }

    func testEngineSetupUsesTheSharedConfigurationModule() {
        let content = OnboardingContent.content(for: .engineSetup)

        XCTAssertEqual(content.target, .engineSheet)
        XCTAssertTrue(content.requiresEngineConfiguration)
        XCTAssertFalse(content.requiresEngineButtonTap)
    }

    func testGeneratingStepIsAutomaticAndDoesNotExposeManualAdvanceActions() {
        let generating = OnboardingContent.content(for: .generating)

        XCTAssertTrue(generating.autoStartsFirstGeneration)
        XCTAssertFalse(generating.showsManualRefreshAction)
        XCTAssertFalse(generating.showsContinueAction)
        XCTAssertEqual(generating.lifecycleAction, .autoAdvanceToFirstGeneration)
        XCTAssertEqual(generating.progression, .automaticGeneration)
        XCTAssertEqual(generating.title, "We’re generating today and yesterday")
        XCTAssertTrue(generating.body.contains("first two entries"))
    }

    func testDemoStoryCarriesRealStoryAndReferenceData() {
        XCTAssertEqual(OnboardingDemoStory.demoDayKey, "demo-day")
        XCTAssertFalse(OnboardingDemoStory.demoStory.sections.isEmpty)
        XCTAssertFalse(OnboardingDemoStory.demoEvents.isEmpty)
        let paragraphs = OnboardingDemoStory.demoStory.sections.flatMap(\.paragraphs)

        XCTAssertGreaterThanOrEqual(paragraphs.count, 12)
        XCTAssertGreaterThanOrEqual(OnboardingDemoStory.demoEvents.count, 120)
        XCTAssertTrue(
            paragraphs.allSatisfy { $0.sourceEventIDs.count >= 10 },
            "Each demo paragraph should expose a dense, cross-app set of references so the right-side panel feels rich and believable."
        )
        XCTAssertGreaterThanOrEqual(Set(OnboardingDemoStory.demoEvents.map(\.sourceApp)).count, 10)
    }

    func testCoachmarkCopyStaysShortAndDoesNotLeakInternalProductCommentary() {
        let steps: [OnboardingStep] = [.demoRead, .demoClick, .demoReference, .privacy, .permissions, .enginePrompt, .engineSetup, .generating]
        let bannedPhrases = [
            "this is the product itself",
            "not a welcome screen",
            "the goal is not only to summarize you",
            "hidden remote copy"
        ]

        for step in steps {
            let body = OnboardingContent.content(for: step).body.lowercased()
            XCTAssertLessThan(body.count, 220, "Coachmark body for \(step) should stay compact.")
            XCTAssertFalse(bannedPhrases.contains(where: body.contains), "Coachmark body for \(step) still sounds like internal commentary.")
        }
    }
}
