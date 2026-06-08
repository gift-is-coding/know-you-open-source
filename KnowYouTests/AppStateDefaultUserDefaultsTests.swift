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

    func testDefaultUserDefaultsCanResolveRegressionSuiteFromEnvironment() {
        let suiteName = "AppStateRegressionDefaults-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let key = AppState.UserDefaultsKeys.onboardingProgressState
        let originalStandardValue = UserDefaults.standard.string(forKey: key)

        AppState.setDefaultUserDefaultsEnvironmentForTesting([
            "KNOWYOU_USER_DEFAULTS_SUITE": suiteName,
        ])
        defer { AppState.setDefaultUserDefaultsEnvironmentForTesting(nil) }

        let appState = AppState(bootstrapServices: false)
        appState.completeOnboarding()

        XCTAssertEqual(defaults.string(forKey: key), OnboardingProgressState.complete.rawValue)
        XCTAssertEqual(UserDefaults.standard.string(forKey: key), originalStandardValue)
    }

    func testDefaultVaultURLUsesRegressionProfileRoot() throws {
        let profileRoot = URL(fileURLWithPath: NSTemporaryDirectory())
            .appending(path: "KnowYouRegression-\(UUID().uuidString)", directoryHint: .isDirectory)

        AppRuntimeProfile.setCurrentEnvironmentForTesting([
            "KNOWYOU_PROFILE_ROOT": profileRoot.path,
        ])
        defer { AppRuntimeProfile.setCurrentEnvironmentForTesting(nil) }

        XCTAssertEqual(
            try AppState.defaultVaultURL().path,
            profileRoot
                .appending(path: "Application Support", directoryHint: .isDirectory)
                .appending(path: "KnowYou", directoryHint: .isDirectory)
                .appending(path: "Vault", directoryHint: .isDirectory)
                .path
        )
    }
}
