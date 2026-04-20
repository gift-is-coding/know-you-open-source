import XCTest
@testable import KnowYou

final class OnboardingReferenceAdvancePolicyTests: XCTestCase {
    func testFirstValidParagraphClickDoesNotAdvanceImmediately() {
        var policy = OnboardingReferenceAdvancePolicy()
        let now = Date(timeIntervalSince1970: 1_776_000_000)

        let shouldAdvance = policy.registerValidParagraphSelection(at: now)

        XCTAssertFalse(shouldAdvance)
        XCTAssertFalse(policy.shouldAdvanceReferenceStep(at: now.addingTimeInterval(1)))
    }

    func testSecondValidParagraphClickAdvances() {
        var policy = OnboardingReferenceAdvancePolicy()
        let now = Date(timeIntervalSince1970: 1_776_000_000)

        _ = policy.registerValidParagraphSelection(at: now)
        let shouldAdvance = policy.registerValidParagraphSelection(at: now.addingTimeInterval(2))

        XCTAssertTrue(shouldAdvance)
    }

    func testSingleValidParagraphClickAdvancesAfterSixSeconds() {
        var policy = OnboardingReferenceAdvancePolicy()
        let now = Date(timeIntervalSince1970: 1_776_000_000)

        _ = policy.registerValidParagraphSelection(at: now)

        XCTAssertFalse(policy.shouldAdvanceReferenceStep(at: now.addingTimeInterval(5.5)))
        XCTAssertTrue(policy.shouldAdvanceReferenceStep(at: now.addingTimeInterval(6.0)))
    }
}
