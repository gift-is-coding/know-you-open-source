import XCTest
@testable import KnowYou

final class OnboardingContentTests: XCTestCase {
    private struct ValueRowExpectation: Equatable {
        let title: String
        let detail: String
    }

    private struct LinkExpectation: Equatable {
        let title: String
        let url: String
    }

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
        let valueRows: [ValueRowExpectation]
        let helperLinks: [LinkExpectation]
        let settingsNudge: String?
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
                preview: nil,
                valueRows: [],
                helperLinks: [],
                settingsNudge: nil
            ),
            StepExpectation(
                step: .capture,
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
            ),
            StepExpectation(
                step: .safety,
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
                ),
                valueRows: [],
                helperLinks: [],
                settingsNudge: nil
            ),
            StepExpectation(
                step: .permissions,
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
                    ValueRowExpectation(
                        title: "Clipboard fills in what you were reading and writing",
                        detail: "Copied text is captured automatically, so short notes, snippets, and pasted ideas can anchor the story without extra effort."
                    ),
                    ValueRowExpectation(
                        title: "Notifications explain who reached you and when",
                        detail: "Full Disk Access lets Know You read the local Notification Center store on this Mac so reminders and replies show up in the right place."
                    ),
                    ValueRowExpectation(
                        title: "Voice tools can feed context through the clipboard",
                        detail: "If you dictate into a clipboard-friendly helper, Know You can pick up that text automatically just like any other copied note."
                    ),
                ],
                helperLinks: [
                    LinkExpectation(
                        title: "Maccy clipboard helper",
                        url: "https://maccy.app/"
                    ),
                    LinkExpectation(
                        title: "MacWhisper voice input helper",
                        url: "https://www.macwhisper.com/"
                    ),
                ],
                settingsNudge: "Summarizer setup is optional. Finish onboarding first, then open Settings whenever you want Claude, Codex, Gemini, or OpenAI help with story drafting."
            )
        ]

        for expectation in expectations {
            let content = OnboardingContent.content(for: expectation.step)

            XCTAssertEqual(content.title, expectation.title, "\(expectation.step)")
            XCTAssertEqual(content.body, expectation.body, "\(expectation.step)")
            XCTAssertEqual(content.caption, expectation.caption, "\(expectation.step)")
            XCTAssertEqual(content.bullets, expectation.bullets, "\(expectation.step)")
            XCTAssertEqual(content.primaryCTA, expectation.primaryCTA, "\(expectation.step)")
            XCTAssertEqual(
                content.valueRows.map { ValueRowExpectation(title: $0.title, detail: $0.detail) },
                expectation.valueRows,
                "\(expectation.step)"
            )
            XCTAssertEqual(
                content.helperLinks.map { LinkExpectation(title: $0.title, url: $0.url.absoluteString) },
                expectation.helperLinks,
                "\(expectation.step)"
            )
            XCTAssertEqual(content.settingsNudge, expectation.settingsNudge, "\(expectation.step)")

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
