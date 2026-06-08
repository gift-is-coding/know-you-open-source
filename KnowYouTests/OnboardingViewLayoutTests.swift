import XCTest
@testable import KnowYou

final class OnboardingViewLayoutTests: XCTestCase {
    func testDemoReadStepUsesTheRealReaderChromePlan() {
        let plan = makeRenderPlan(for: .demoRead)

        XCTAssertTrue(plan.usesRealReaderChrome)
        XCTAssertTrue(plan.keepsSourcesPanelVisible)
        XCTAssertTrue(plan.showsEngineButton)
        XCTAssertEqual(plan.highlightedTarget, .storyPanel)
        XCTAssertEqual(plan.coachmarkTitle, "Start with this demo day")
    }

    func testDemoClickStepKeepsTheUserInTheStoryColumn() {
        let plan = makeRenderPlan(for: .demoClick)

        XCTAssertTrue(plan.usesRealReaderChrome)
        XCTAssertTrue(plan.keepsSourcesPanelVisible)
        XCTAssertEqual(plan.highlightedTarget, .storyPanel)
        XCTAssertEqual(plan.coachmarkTitle, "Click any paragraph in the story")
    }

    func testDemoReferenceStepMovesAttentionToTheRealSourcesPanel() {
        let plan = makeRenderPlan(for: .demoReference)

        XCTAssertTrue(plan.usesRealReaderChrome)
        XCTAssertTrue(plan.keepsSourcesPanelVisible)
        XCTAssertEqual(plan.highlightedTarget, .sourcesPanel)
        XCTAssertEqual(plan.coachmarkTitle, "The right side shows the source")
    }

    func testPermissionStepUsesTheTwoStepActivationCopy() {
        let plan = makeRenderPlan(for: .permissions)

        XCTAssertTrue(plan.usesRealReaderChrome)
        XCTAssertEqual(plan.highlightedTarget, .sharedCenterCard)
        XCTAssertEqual(plan.activationStepLabel, "1/2")
        XCTAssertEqual(plan.activationFollowupLabel, "2/2 Configure engine")
        XCTAssertTrue(plan.coachmarkBody.contains("Only two steps left"))
    }

    func testEnginePromptRendersARealConfigureEngineButton() {
        let plan = makeRenderPlan(for: .enginePrompt)

        XCTAssertTrue(plan.usesRealReaderChrome)
        XCTAssertTrue(plan.showsEngineButton)
        XCTAssertEqual(plan.highlightedTarget, .engineButton)
        XCTAssertEqual(plan.coachmarkTitle, "2/2 Configure engine")
    }

    func testEngineCoachmarkFallbackTracksTheTitlebarTrailingSelector() {
        let rect = OnboardingEngineCoachmarkFallbackPolicy.rect(in: CGSize(width: 1280, height: 720))

        XCTAssertTrue(OnboardingEngineCoachmarkFallbackPolicy.usesTitlebarFallbackWhenSwiftUIAnchorIsUnavailable)
        XCTAssertGreaterThan(rect.minX, 1000)
        XCTAssertEqual(rect.maxX, 1256, accuracy: 0.1)
        XCTAssertEqual(rect.minY, 14, accuracy: 0.1)
        XCTAssertEqual(rect.height, 42, accuracy: 0.1)
    }

    func testGeneratingStepStillRendersInsideTheRealReader() {
        let plan = makeRenderPlan(for: .generating)

        XCTAssertTrue(plan.usesRealReaderChrome)
        XCTAssertTrue(plan.keepsSourcesPanelVisible)
        XCTAssertTrue(plan.showsEngineButton)
        XCTAssertEqual(plan.coachmarkTitle, "We’re preparing your first 3 days")
        XCTAssertFalse(plan.coachmarkTitle.contains("Reader preview"))
    }

    private func makeRenderPlan(for step: OnboardingStep) -> OnboardingRenderPlan {
        OnboardingRenderPlan(step: step, content: OnboardingContent.content(for: step))
    }
}
