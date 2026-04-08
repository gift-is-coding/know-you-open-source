import XCTest
@testable import KnowYou

final class OnboardingContentTests: XCTestCase {
    private struct PreviewExpectation {
        let title: String
        let time: String
        let paragraph: String
        let sources: [String]
    }

    private struct StepExpectation {
        let step: OnboardingStep
        let title: String
        let body: String
        let caption: String
        let bullets: [String]
        let primaryCTA: String
        let preview: PreviewExpectation?
    }

    func testOnboardingStepAllCasesAreInStoryOrder() {
        XCTAssertEqual(
            OnboardingStep.allCases,
            [.intro, .capture, .safety, .preview, .permissions]
        )
    }

    func testOnboardingStepNavigationContractUsesExplicitStoryFlow() {
        XCTAssertTrue(OnboardingStep.intro.isFirst)
        XCTAssertFalse(OnboardingStep.intro.isLast)
        XCTAssertNil(OnboardingStep.intro.previous)
        XCTAssertEqual(OnboardingStep.intro.next, .capture)

        XCTAssertEqual(OnboardingStep.capture.previous, .intro)
        XCTAssertEqual(OnboardingStep.capture.next, .safety)
        XCTAssertEqual(OnboardingStep.safety.previous, .capture)
        XCTAssertEqual(OnboardingStep.safety.next, .preview)
        XCTAssertEqual(OnboardingStep.preview.previous, .safety)
        XCTAssertEqual(OnboardingStep.preview.next, .permissions)

        XCTAssertTrue(OnboardingStep.permissions.isLast)
        XCTAssertFalse(OnboardingStep.permissions.isFirst)
        XCTAssertEqual(OnboardingStep.permissions.previous, .preview)
        XCTAssertNil(OnboardingStep.permissions.next)
    }

    func testOnboardingStepContentMatchesTheFullStepContract() throws {
        let expectations: [StepExpectation] = [
            StepExpectation(
                step: .intro,
                title: "Meet Know You",
                body: "A calm daily story, built from the moments already happening on your Mac.",
                caption: "Stored as Markdown on this Mac first, so trust starts before setup does.",
                bullets: [],
                primaryCTA: "Show me the story",
                preview: nil
            ),
            StepExpectation(
                step: .capture,
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
            ),
            StepExpectation(
                step: .safety,
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
            ),
            StepExpectation(
                step: .preview,
                title: "Preview a believable day",
                body: "The preview reads like the app itself: a short diary arc from morning to night with the source apps nearby.",
                caption: "Close to the real reader, not a detached marketing mock.",
                bullets: [
                    "See the diary before it lands in your archive",
                    "Keep the nearby apps visible for confidence",
                ],
                primaryCTA: "Set up permissions",
                preview: PreviewExpectation(
                    title: "Friday, April 10",
                    time: "8:10 AM",
                    paragraph: "The morning started quietly in Notes, then a copied outline and a Calendar nudge turned the first hour into a clear plan instead of a scramble.",
                    sources: ["Notes", "Calendar", "Clipboard"]
                )
            ),
            StepExpectation(
                step: .permissions,
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
        ]

        for expectation in expectations {
            let content = OnboardingContent.content(for: expectation.step)

            XCTAssertEqual(content.title, expectation.title, "\(expectation.step)")
            XCTAssertEqual(content.body, expectation.body, "\(expectation.step)")
            XCTAssertEqual(content.caption, expectation.caption, "\(expectation.step)")
            XCTAssertEqual(content.bullets, expectation.bullets, "\(expectation.step)")
            XCTAssertEqual(content.primaryCTA, expectation.primaryCTA, "\(expectation.step)")

            if let expectedPreview = expectation.preview {
                let preview = try XCTUnwrap(content.preview, "\(expectation.step)")
                XCTAssertEqual(preview.title, expectedPreview.title, "\(expectation.step)")
                XCTAssertEqual(preview.entries.count, 3, "\(expectation.step)")
                XCTAssertEqual(preview.entries.first?.time, expectedPreview.time, "\(expectation.step)")
                XCTAssertEqual(preview.entries.first?.paragraph, expectedPreview.paragraph, "\(expectation.step)")
                XCTAssertEqual(preview.entries.first?.sources, expectedPreview.sources, "\(expectation.step)")
            } else {
                XCTAssertNil(content.preview, "\(expectation.step)")
            }
        }
    }
}
