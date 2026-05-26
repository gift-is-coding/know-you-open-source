import XCTest
@testable import KnowYou

@MainActor
final class AppStateDefaultUserDefaultsTests: XCTestCase {
    func testDefaultAppStateCanUseTestScopedDefaultsWithoutTouchingStandardDefaults() {
        let suiteName = "AppStateDefaultUserDefaultsTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let key = AppState.UserDefaultsKeys.onboardingProgressState
        let originalStandardValue = UserDefaults.standard.string(forKey: key)

        AppState.setDefaultUserDefaultsForTesting(defaults)
        defer { AppState.setDefaultUserDefaultsForTesting(nil) }

        let appState = AppState(bootstrapServices: false)
        appState.completeOnboarding()

        XCTAssertEqual(defaults.string(forKey: key), OnboardingProgressState.complete.rawValue)
        XCTAssertEqual(UserDefaults.standard.string(forKey: key), originalStandardValue)
    }
}
