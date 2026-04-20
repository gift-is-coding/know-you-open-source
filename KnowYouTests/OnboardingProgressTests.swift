import XCTest
@testable import KnowYou

final class OnboardingProgressTests: XCTestCase {
    private var defaults: UserDefaults!
    private var suiteName: String!

    override func setUp() {
        super.setUp()
        suiteName = "OnboardingProgressTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
        defaults.removePersistentDomain(forName: suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        suiteName = nil
        super.tearDown()
    }

    @MainActor
    func testInitialLaunchStartsAtDemoRead() {
        let appState = AppState(bootstrapServices: false, userDefaults: defaults)

        XCTAssertEqual(appState.onboardingProgress.state, .demoReadPending)
        XCTAssertEqual(appState.currentOnboardingStep, .demoRead)
        XCTAssertTrue(appState.shouldShowOnboarding)
    }

    @MainActor
    func testEnginePromptPersistsAcrossRelaunch() {
        let appState = AppState(bootstrapServices: false, userDefaults: defaults)

        appState.resumeOnboardingStep(.enginePrompt)

        let relaunched = AppState(bootstrapServices: false, userDefaults: defaults)

        XCTAssertEqual(relaunched.onboardingProgress.state, .enginePromptPending)
        XCTAssertEqual(relaunched.currentOnboardingStep, .enginePrompt)
    }

    @MainActor
    func testEngineSetupPersistsAcrossRelaunchUntilTheUserFinishesConfiguringIt() {
        let appState = AppState(bootstrapServices: false, userDefaults: defaults)

        appState.resumeOnboardingStep(.engineSetup)

        let relaunched = AppState(bootstrapServices: false, userDefaults: defaults)

        XCTAssertEqual(relaunched.onboardingProgress.state, .engineSetupPending)
        XCTAssertEqual(relaunched.currentOnboardingStep, .engineSetup)
    }

    @MainActor
    func testMissingFullDiskAccessCannotSkipPermissionsDuringRestore() {
        let appState = AppState(bootstrapServices: false, userDefaults: defaults)

        appState.resumeOnboardingStep(.engineSetup)
        appState.restoreOnboardingProgress(
            isFullDiskAccessReady: false,
            isEngineReady: true,
            hasVoiceTool: false,
            hasLaunchAtLogin: false
        )

        XCTAssertEqual(appState.onboardingProgress.state, .permissionsPending)
        XCTAssertEqual(appState.currentOnboardingStep, .permissions)
    }

    @MainActor
    func testReadyPermissionsStillLeadToEnginePromptEvenIfAnEngineIsAlreadyConfigured() {
        let appState = AppState(bootstrapServices: false, userDefaults: defaults)

        appState.resumeOnboardingStep(.permissions)
        appState.restoreOnboardingProgress(
            isFullDiskAccessReady: true,
            isEngineReady: true,
            hasVoiceTool: false,
            hasLaunchAtLogin: false
        )

        XCTAssertEqual(appState.onboardingProgress.state, .enginePromptPending)
        XCTAssertEqual(appState.currentOnboardingStep, .enginePrompt)
    }

    @MainActor
    func testMissingEngineKeepsTheUserInsideTheEngineSetupStageAfterPermissionIsReady() {
        let appState = AppState(bootstrapServices: false, userDefaults: defaults)

        appState.resumeOnboardingStep(.engineSetup)
        appState.restoreOnboardingProgress(
            isFullDiskAccessReady: true,
            isEngineReady: false,
            hasVoiceTool: false,
            hasLaunchAtLogin: false
        )

        XCTAssertEqual(appState.onboardingProgress.state, .engineSetupPending)
        XCTAssertEqual(appState.currentOnboardingStep, .engineSetup)
    }

    @MainActor
    func testEngineSetupWithPermissionAndEngineReadyAutomaticallyEntersFirstGenerationInProgress() {
        let appState = AppState(bootstrapServices: false, userDefaults: defaults)

        appState.resumeOnboardingStep(.engineSetup)
        appState.restoreOnboardingProgress(
            isFullDiskAccessReady: true,
            isEngineReady: true,
            hasVoiceTool: false,
            hasLaunchAtLogin: false
        )

        XCTAssertEqual(appState.onboardingProgress.state, .firstGenerationInProgress)
        XCTAssertEqual(appState.currentOnboardingStep, .generating)
    }

    @MainActor
    func testCompletingOnboardingLetsTheAppLeaveOnboardingAfterRelaunch() {
        let appState = AppState(bootstrapServices: false, userDefaults: defaults)

        appState.completeOnboarding()

        let relaunched = AppState(bootstrapServices: false, userDefaults: defaults)

        XCTAssertEqual(relaunched.onboardingProgress.state, .complete)
        XCTAssertFalse(relaunched.shouldShowOnboarding)
        XCTAssertNil(relaunched.currentOnboardingStep)
    }

    @MainActor
    func testCompletingOnboardingQueuesOneTimeSevenDayBootstrap() {
        let now = DateComponents(calendar: Calendar(identifier: .gregorian), year: 2026, month: 4, day: 20, hour: 9).date!
        let appState = AppState(
            bootstrapServices: false,
            currentDate: { now },
            userDefaults: defaults
        )

        appState.completeOnboarding()

        XCTAssertEqual(appState.onboardingBootstrapState, OnboardingBootstrapState.pending)
        XCTAssertEqual(
            appState.onboardingBootstrapDayKeys,
            ["2026-04-20", "2026-04-19", "2026-04-18", "2026-04-17", "2026-04-16", "2026-04-15", "2026-04-14"]
        )
    }

    @MainActor
    func testCompletedBootstrapDoesNotRequeueOnLaterRelaunch() {
        let now = DateComponents(calendar: Calendar(identifier: .gregorian), year: 2026, month: 4, day: 20, hour: 9).date!
        let appState = AppState(
            bootstrapServices: false,
            currentDate: { now },
            userDefaults: defaults
        )

        appState.completeOnboarding()
        appState.markOnboardingBootstrapComplete()

        let relaunched = AppState(
            bootstrapServices: false,
            currentDate: { now },
            userDefaults: defaults
        )

        XCTAssertEqual(relaunched.onboardingBootstrapState, OnboardingBootstrapState.complete)
        XCTAssertTrue(relaunched.onboardingBootstrapDayKeys.isEmpty)
    }
}
