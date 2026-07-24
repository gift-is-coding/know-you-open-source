import XCTest
@testable import KnowYou

final class OnboardingContentTests: XCTestCase {
    func testOnboardingStepStoryFlowUsesTheRealReaderCoachmarkOrder() {
        XCTAssertEqual(
            OnboardingStep.storyFlow,
            [.demoRead, .demoClick, .demoReference, .privacy, .installApp, .permissions, .enginePrompt, .engineSetup, .generating]
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
        XCTAssertEqual(OnboardingStep.privacy.next, .installApp)

        XCTAssertEqual(OnboardingStep.installApp.previous, .privacy)
        XCTAssertEqual(OnboardingStep.installApp.next, .permissions)

        XCTAssertEqual(OnboardingStep.permissions.previous, .installApp)
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

    func testPrivacyInstallAndPermissionsReuseTheSharedCenteredCard() {
        let privacy = OnboardingContent.content(for: .privacy)
        let install = OnboardingContent.content(for: .installApp)
        let permissions = OnboardingContent.content(for: .permissions)

        XCTAssertEqual(privacy.target, .sharedCenterCard)
        XCTAssertEqual(install.target, .sharedCenterCard)
        XCTAssertEqual(permissions.target, .sharedCenterCard)
        XCTAssertTrue(privacy.usesSharedCenterCard)
        XCTAssertTrue(install.usesSharedCenterCard)
        XCTAssertTrue(permissions.usesSharedCenterCard)
    }

    func testInstallAppStepRequiresApplicationsInstallBeforePermissions() {
        let content = OnboardingContent.content(for: .installApp)

        XCTAssertEqual(content.blockingRequirement, .applicationInstalled)
        XCTAssertEqual(content.title, "Move KnowYou to Applications")
        XCTAssertEqual(content.primaryCTA, "Move to Applications and Relaunch")
        XCTAssertTrue(content.body.contains("/Applications"))
        XCTAssertTrue(content.blocksProgress)
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

    func testFullDiskAccessGuidanceExplainsHowToAddKnowYouWhenItIsNotListed() {
        let guidance = OnboardingContent.fullDiskAccessGuidance

        XCTAssertTrue(guidance.missingPermissionDetail.contains("click +"))
        XCTAssertTrue(guidance.missingPermissionDetail.contains("Applications"))
        XCTAssertTrue(guidance.manualAddInstruction.contains("does not appear"))
        XCTAssertTrue(guidance.manualAddInstruction.contains("choose this app"))
        XCTAssertTrue(guidance.manualAddInstruction.contains("+"))
        XCTAssertEqual(guidance.openSettingsButtonTitle, "Open Full Disk Access")
        XCTAssertEqual(guidance.revealAppButtonTitle, "Show App to Add")
        XCTAssertEqual(guidance.recheckButtonTitle, "Check Again")
        XCTAssertEqual(guidance.visualAssetName, "FullDiskAccessAddGuide")
        XCTAssertFalse(guidance.manualAddInstruction.contains("Show KnowYou in Finder"))
    }

    func testRegressionDocsUseInstalledNewUserAppForPermissionCleanRuns() throws {
        let resources = try XCTUnwrap(Bundle(for: Self.self).resourceURL)
        let readme = try String(
            contentsOf: resources.appending(path: "regression/README.md"),
            encoding: .utf8
        )
        let firstRun = try String(
            contentsOf: resources.appending(path: "regression/test-cases/01-first-run-onboarding.md"),
            encoding: .utf8
        )
        let installer = try String(
            contentsOf: resources.appending(path: "install-new-user-app.sh"),
            encoding: .utf8
        )

        XCTAssertTrue(readme.contains("scripts/install-new-user-app.sh --no-launch"))
        XCTAssertTrue(readme.contains("/Applications/KnowYou New User.app"))
        XCTAssertTrue(readme.contains("dev.knowyou.newuser"))
        XCTAssertTrue(readme.contains("not a DerivedData app"))
        XCTAssertFalse(readme.contains("dev.knowyou.regression"))

        XCTAssertTrue(firstRun.contains("/Applications/KnowYou New User.app"))
        XCTAssertTrue(firstRun.contains("dev.knowyou.newuser"))
        XCTAssertTrue(firstRun.contains("not a DerivedData app"))
        XCTAssertFalse(firstRun.contains("dev.knowyou.regression"))

        XCTAssertTrue(installer.contains("installed_app=\"${INSTALL_APP_PATH:-/Applications/KnowYou New User.app}\""))
        XCTAssertTrue(installer.contains("derived_data_path=\"${DERIVED_DATA_PATH:-$repo_root/.derived-data/new-user}\""))
    }

    func testFullDiskAccessGuideImageAssetIsBundled() {
        let assetURL = Bundle(for: Self.self).resourceURL?
            .appending(path: "FullDiskAccessAddGuide.imageset/Contents.json")

        XCTAssertTrue(
            assetURL.map { FileManager.default.fileExists(atPath: $0.path) } ?? false,
            "Missing bundled FullDiskAccessAddGuide.imageset/Contents.json"
        )
    }

    func testApplicationInstallPolicyRequiresApplicationsKnowYouBundle() {
        let installedAppURL = URL(fileURLWithPath: "/Applications/KnowYou.app")
        let installedNewUserURL = URL(fileURLWithPath: "/Applications/KnowYou New User.app")
        let dataVolumeInstalledAppURL = URL(fileURLWithPath: "/System/Volumes/Data/Applications/KnowYou.app")
        let dataVolumeInstalledNewUserURL = URL(
            fileURLWithPath: "/System/Volumes/Data/Applications/KnowYou New User.app"
        )
        let mountedDMGURL = URL(fileURLWithPath: "/Volumes/KnowYou/KnowYou.app")
        let downloadsURL = URL(fileURLWithPath: "/Users/me/Downloads/KnowYou.app")
        let developmentBuildURL = URL(
            fileURLWithPath: "/Users/me/Library/Developer/Xcode/DerivedData/KnowYou/Build/Products/Debug/KnowYou.app"
        )

        XCTAssertTrue(OnboardingApplicationInstallPolicy.isInstalledInApplications(bundleURL: installedAppURL))
        XCTAssertTrue(OnboardingApplicationInstallPolicy.isInstalledInApplications(bundleURL: dataVolumeInstalledAppURL))
        XCTAssertTrue(
            OnboardingApplicationInstallPolicy.isInstalledInApplications(
                bundleURL: installedNewUserURL,
                bundleIdentifier: AppRuntimeProfile.newUserBundleIdentifier
            )
        )
        XCTAssertTrue(
            OnboardingApplicationInstallPolicy.isInstalledInApplications(
                bundleURL: dataVolumeInstalledNewUserURL,
                bundleIdentifier: AppRuntimeProfile.newUserBundleIdentifier
            )
        )
        XCTAssertFalse(OnboardingApplicationInstallPolicy.isInstalledInApplications(bundleURL: mountedDMGURL))
        XCTAssertFalse(OnboardingApplicationInstallPolicy.isInstalledInApplications(bundleURL: downloadsURL))
        XCTAssertFalse(OnboardingApplicationInstallPolicy.isInstalledInApplications(bundleURL: developmentBuildURL))
        XCTAssertFalse(
            OnboardingApplicationInstallPolicy.isInstalledInApplications(
                bundleURL: installedAppURL,
                bundleIdentifier: AppRuntimeProfile.newUserBundleIdentifier
            )
        )
        XCTAssertFalse(
            OnboardingApplicationInstallPolicy.isInstalledInApplications(
                bundleURL: installedNewUserURL,
                bundleIdentifier: "dev.knowyou.app"
            )
        )
    }

    func testApplicationInstallAutoMovePolicySkipsInstalledApps() {
        XCTAssertNil(
            ApplicationInstallAutoMovePolicy.request(
                bundleURL: URL(fileURLWithPath: "/Applications/KnowYou.app"),
                bundleIdentifier: "dev.knowyou.app",
                launchMode: .interactive,
                isRunningUnderXCTest: false
            )
        )
        XCTAssertNil(
            ApplicationInstallAutoMovePolicy.request(
                bundleURL: URL(fileURLWithPath: "/System/Volumes/Data/Applications/KnowYou.app"),
                bundleIdentifier: "dev.knowyou.app",
                launchMode: .interactive,
                isRunningUnderXCTest: false
            )
        )
    }

    func testApplicationInstallAutoMovePolicyMovesMountedDMGAppToApplications() {
        let request = ApplicationInstallAutoMovePolicy.request(
            bundleURL: URL(fileURLWithPath: "/Volumes/KnowYou/KnowYou.app"),
            bundleIdentifier: "dev.knowyou.app",
            launchMode: .interactive,
            isRunningUnderXCTest: false
        )

        XCTAssertEqual(request?.sourceURL.path, "/Volumes/KnowYou/KnowYou.app")
        XCTAssertEqual(request?.targetURL.path, "/Applications/KnowYou.app")
    }

    func testApplicationInstallAutoMovePolicyUsesNewUserTargetBundle() {
        let request = ApplicationInstallAutoMovePolicy.request(
            bundleURL: URL(fileURLWithPath: "/Volumes/KnowYou New User/KnowYou New User.app"),
            bundleIdentifier: AppRuntimeProfile.newUserBundleIdentifier,
            launchMode: .interactive,
            isRunningUnderXCTest: false
        )

        XCTAssertEqual(request?.sourceURL.path, "/Volumes/KnowYou New User/KnowYou New User.app")
        XCTAssertEqual(request?.targetURL.path, "/Applications/KnowYou New User.app")
    }

    func testApplicationInstallAutoMovePolicySkipsTestsCliAndDerivedData() {
        let mountedDMGURL = URL(fileURLWithPath: "/Volumes/KnowYou/KnowYou.app")
        let derivedDataURL = URL(
            fileURLWithPath: "/Users/me/Library/Developer/Xcode/DerivedData/KnowYou/Build/Products/Debug/KnowYou.app"
        )
        let repoLocalDerivedDataURL = URL(
            fileURLWithPath: "/Users/me/Documents/code/know-you/.derived-data/dev/Build/Products/Debug/KnowYou.app"
        )

        XCTAssertNil(
            ApplicationInstallAutoMovePolicy.request(
                bundleURL: mountedDMGURL,
                bundleIdentifier: "dev.knowyou.app",
                launchMode: .interactive,
                isRunningUnderXCTest: true
            )
        )
        XCTAssertNil(
            ApplicationInstallAutoMovePolicy.request(
                bundleURL: mountedDMGURL,
                bundleIdentifier: "dev.knowyou.app",
                launchMode: .myWikiMCP,
                isRunningUnderXCTest: false
            )
        )
        XCTAssertNil(
            ApplicationInstallAutoMovePolicy.request(
                bundleURL: mountedDMGURL,
                bundleIdentifier: "dev.knowyou.app",
                launchMode: .myWikiContext,
                isRunningUnderXCTest: false
            )
        )
        XCTAssertNil(
            ApplicationInstallAutoMovePolicy.request(
                bundleURL: mountedDMGURL,
                bundleIdentifier: "dev.knowyou.app",
                launchMode: .endOfDayReminder,
                isRunningUnderXCTest: false
            )
        )
        XCTAssertNil(
            ApplicationInstallAutoMovePolicy.request(
                bundleURL: derivedDataURL,
                bundleIdentifier: "dev.knowyou.app",
                launchMode: .interactive,
                isRunningUnderXCTest: false
            )
        )
        XCTAssertNil(
            ApplicationInstallAutoMovePolicy.request(
                bundleURL: repoLocalDerivedDataURL,
                bundleIdentifier: "dev.knowyou.app",
                launchMode: .interactive,
                isRunningUnderXCTest: false
            )
        )
    }

    func testApplicationInstallMoverCopiesOpensAndReplacesExistingTarget() {
        var removedURLs: [URL] = []
        var copiedPairs: [(source: URL, target: URL)] = []
        var openedURLs: [URL] = []
        let sourceURL = URL(fileURLWithPath: "/Volumes/KnowYou/KnowYou.app")
        let targetURL = URL(fileURLWithPath: "/Applications/KnowYou.app")
        let mover = ApplicationInstallMover(
            fileExists: { $0 == targetURL },
            removeItem: { removedURLs.append($0) },
            copyItem: { copiedPairs.append((source: $0, target: $1)) },
            open: {
                openedURLs.append($0)
                return true
            }
        )

        let result = mover.moveToApplicationsAndOpen(
            request: ApplicationInstallMoveRequest(sourceURL: sourceURL, targetURL: targetURL)
        )

        XCTAssertEqual(result, .movedAndOpened(targetURL: targetURL))
        XCTAssertEqual(removedURLs, [targetURL])
        XCTAssertEqual(copiedPairs.map(\.source), [sourceURL])
        XCTAssertEqual(copiedPairs.map(\.target), [targetURL])
        XCTAssertEqual(openedURLs, [targetURL])
    }

    func testApplicationInstallMoverReportsCopyFailureWithoutOpening() {
        enum CopyFailure: Error {
            case denied
        }
        var openedURLs: [URL] = []
        let sourceURL = URL(fileURLWithPath: "/Volumes/KnowYou/KnowYou.app")
        let targetURL = URL(fileURLWithPath: "/Applications/KnowYou.app")
        let mover = ApplicationInstallMover(
            fileExists: { _ in false },
            removeItem: { _ in },
            copyItem: { _, _ in throw CopyFailure.denied },
            open: {
                openedURLs.append($0)
                return true
            }
        )

        let result = mover.moveToApplicationsAndOpen(
            request: ApplicationInstallMoveRequest(sourceURL: sourceURL, targetURL: targetURL)
        )

        XCTAssertEqual(result, .failed)
        XCTAssertTrue(openedURLs.isEmpty)
    }

    func testFullDiskAccessBypassIsLimitedToDerivedDataDebugBuilds() {
        let developmentBuildURL = URL(
            fileURLWithPath: "/Users/me/Library/Developer/Xcode/DerivedData/KnowYou/Build/Products/Debug/KnowYou.app"
        )
        let worktreeLocalDevelopmentBuildURL = URL(
            fileURLWithPath: "/Users/me/project/.derived-data/dev/Build/Products/Debug/KnowYou.app"
        )
        let repoLocalDevelopmentBuildURL = URL(
            fileURLWithPath: "/Users/me/Documents/code/know-you/.derived-data/dev/Build/Products/Debug/KnowYou.app"
        )
        let installedAppURL = URL(fileURLWithPath: "/Applications/KnowYou.app")

        XCTAssertTrue(OnboardingPermissionBypassPolicy.allowsFullDiskAccessBypass(bundleURL: developmentBuildURL))
        XCTAssertTrue(
            OnboardingPermissionBypassPolicy.allowsFullDiskAccessBypass(
                bundleURL: worktreeLocalDevelopmentBuildURL
            )
        )
        XCTAssertTrue(OnboardingPermissionBypassPolicy.allowsFullDiskAccessBypass(bundleURL: repoLocalDevelopmentBuildURL))
        XCTAssertFalse(OnboardingPermissionBypassPolicy.allowsFullDiskAccessBypass(bundleURL: installedAppURL))
    }

    func testDevelopmentFullDiskAccessBypassCanBePersistedForDerivedDataBuilds() {
        let suiteName = "OnboardingContentTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let developmentBuildURL = URL(
            fileURLWithPath: "/Users/me/Library/Developer/Xcode/DerivedData/KnowYou/Build/Products/Debug/KnowYou.app"
        )
        let installedAppURL = URL(fileURLWithPath: "/Applications/KnowYou.app")

        XCTAssertFalse(
            OnboardingPermissionBypassPolicy.hasStoredDevelopmentBypass(
                bundleURL: developmentBuildURL,
                userDefaults: defaults
            )
        )

        OnboardingPermissionBypassPolicy.storeDevelopmentBypass(
            bundleURL: developmentBuildURL,
            userDefaults: defaults
        )

        XCTAssertTrue(
            OnboardingPermissionBypassPolicy.hasStoredDevelopmentBypass(
                bundleURL: developmentBuildURL,
                userDefaults: defaults
            )
        )
        XCTAssertFalse(
            OnboardingPermissionBypassPolicy.hasStoredDevelopmentBypass(
                bundleURL: installedAppURL,
                userDefaults: defaults
            )
        )
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
        XCTAssertEqual(generating.title, "We’re preparing your first 3 days")
        XCTAssertTrue(generating.body.contains("All local"))
        XCTAssertTrue(generating.body.contains("No backend server"))
    }

    func testHistoryBootstrapConfirmationCopyEmphasizesLocalPrivacy() {
        XCTAssertEqual(OnboardingHistoryBootstrapConfirmation.title, "Your first 3 days are being prepared")
        XCTAssertTrue(OnboardingHistoryBootstrapConfirmation.message.contains("**KnowYou**"))
        XCTAssertTrue(OnboardingHistoryBootstrapConfirmation.message.contains("All local"))
        XCTAssertTrue(OnboardingHistoryBootstrapConfirmation.message.contains("No backend server"))
        XCTAssertEqual(OnboardingHistoryBootstrapConfirmation.confirmButtonTitle, "Start generating")
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
