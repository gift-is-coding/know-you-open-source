import XCTest
@testable import KnowYou

final class SettingsMetadataTests: XCTestCase {
    func testAppBuildMetadataBadgeTextIncludesVersionBuildAndGitSHA() {
        let metadata = AppBuildMetadata(
            marketingVersion: "1.0",
            buildNumber: "42",
            buildTimestamp: "04-17 20:32",
            gitShortSHA: "379aff5"
        )

        XCTAssertEqual(metadata.badgeText, "v1.0 · 04-17 20:32 (42) · 379aff5")
    }

    func testAppBuildMetadataBadgeTextFallsBackToVersionAndBuildWhenGitSHAMissing() {
        let metadata = AppBuildMetadata(
            marketingVersion: "1.0",
            buildNumber: "42",
            buildTimestamp: nil,
            gitShortSHA: nil
        )

        XCTAssertEqual(metadata.badgeText, "v1.0 (42)")
    }

    func testAppSupportMetadataMatchesPublicContactContract() {
        XCTAssertEqual(AppSupportMetadata.twitterURL.absoluteString, "https://x.com/TianfuW49629")
        XCTAssertEqual(AppSupportMetadata.contactEmail, "cestlouiswu@gmail.com")
        XCTAssertEqual(AppSupportMetadata.companyEnglishName, "Shanghai Erren Beiwu Software Co., Ltd.")
        XCTAssertEqual(
            AppSupportMetadata.copyrightLine,
            "Copyright © 2026 Shanghai Erren Beiwu Software Co., Ltd. All rights reserved."
        )
    }

    func testSettingsSupportCopyDefinesDiscordFallbackAndMailLink() {
        XCTAssertEqual(AppSupportMetadata.productTagline, "A local-first daily story for your workday on Mac.")
        XCTAssertEqual(
            AppSupportMetadata.discordURL?.absoluteString,
            "https://discord.gg/ZrqF5jwQ"
        )
        XCTAssertEqual(AppSupportMetadata.twitterButtonTitle, "Follow on X / Twitter")
        XCTAssertEqual(AppSupportMetadata.emailButtonTitle, "Send Email")
        XCTAssertEqual(AppSupportMetadata.discordButtonTitle, "Join Discord Community")
        XCTAssertEqual(
            AppSupportMetadata.discordDescription,
            "Discuss product ideas, share feedback, and compare journaling workflows with other users."
        )
        XCTAssertEqual(
            AppSupportMetadata.supportDescription,
            "For privacy-sensitive topics or anything that should not be discussed in public, please contact us by email."
        )
        XCTAssertEqual(
            AppSupportMetadata.emailURL.absoluteString,
            "mailto:cestlouiswu@gmail.com"
        )
    }

    func testRuntimeProfileDefaultsToProductionIdentityForNormalAndUnknownBundleIDs() {
        let normalProfile = AppRuntimeProfile(bundleIdentifier: "dev.knowyou.app")
        XCTAssertEqual(normalProfile.displayName, "KnowYou")
        XCTAssertEqual(normalProfile.supportDirectoryName, "KnowYou")
        XCTAssertEqual(normalProfile.keychainService, "com.knowyou.app")

        let unknownProfile = AppRuntimeProfile(bundleIdentifier: "com.example.local-debug")
        XCTAssertEqual(unknownProfile.displayName, "KnowYou")
        XCTAssertEqual(unknownProfile.supportDirectoryName, "KnowYou")
        XCTAssertEqual(unknownProfile.keychainService, "com.knowyou.app")

        let missingBundleProfile = AppRuntimeProfile(bundleIdentifier: nil)
        XCTAssertEqual(missingBundleProfile.displayName, "KnowYou")
        XCTAssertEqual(missingBundleProfile.supportDirectoryName, "KnowYou")
        XCTAssertEqual(missingBundleProfile.keychainService, "com.knowyou.app")
    }

    func testRuntimeProfileIsolatesNewUserTestingBundle() {
        let profile = AppRuntimeProfile(bundleIdentifier: "dev.knowyou.newuser")

        XCTAssertEqual(profile.displayName, "KnowYou New User")
        XCTAssertEqual(profile.supportDirectoryName, "KnowYou New User")
        XCTAssertEqual(profile.keychainService, "dev.knowyou.newuser")
    }

    func testRuntimeProfileCanUseRegressionProfileRootForApplicationSupport() throws {
        let profileRoot = FileManager.default.temporaryDirectory
            .appending(path: "knowyou-profile-\(UUID().uuidString)", directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: profileRoot) }

        let profile = AppRuntimeProfile(
            bundleIdentifier: "dev.knowyou.app",
            environment: ["KNOWYOU_PROFILE_ROOT": profileRoot.path]
        )

        let appSupportURL = try AppRuntimeProfile.applicationSupportDirectoryURL(profile: profile)

        XCTAssertEqual(
            appSupportURL.standardizedFileURL.path,
            profileRoot
                .appending(path: "Application Support", directoryHint: .isDirectory)
                .appending(path: "KnowYou", directoryHint: .isDirectory)
                .standardizedFileURL
                .path
        )
        XCTAssertTrue(FileManager.default.fileExists(atPath: appSupportURL.path))
    }

    func testRuntimeProfileCanUseRegressionDefaultsSuiteAndKeychainService() {
        let suiteName = "dev.knowyou.tests.\(UUID().uuidString)"
        let keychainService = "dev.knowyou.tests.keychain.\(UUID().uuidString)"
        defer {
            UserDefaults(suiteName: suiteName)?.removePersistentDomain(forName: suiteName)
        }

        let profile = AppRuntimeProfile(
            bundleIdentifier: "dev.knowyou.app",
            environment: [
                "KNOWYOU_USER_DEFAULTS_SUITE": suiteName,
                "KNOWYOU_KEYCHAIN_SERVICE": keychainService,
            ]
        )
        let defaults = AppRuntimeProfile.userDefaults(profile: profile)
        let key = "profile-isolation-\(UUID().uuidString)"

        defaults.set("isolated", forKey: key)

        XCTAssertEqual(profile.userDefaultsSuiteName, suiteName)
        XCTAssertEqual(profile.keychainService, keychainService)
        XCTAssertEqual(UserDefaults(suiteName: suiteName)?.string(forKey: key), "isolated")
        XCTAssertNil(UserDefaults.standard.string(forKey: key))
    }

    func testInAppDocumentsExposeReadableContentWithoutRepositoryLinks() {
        let privacy = AppSupportDocument.privacy
        XCTAssertEqual(privacy.buttonTitle, "Privacy Policy")
        XCTAssertTrue(privacy.body.contains("local-first"))
        XCTAssertTrue(privacy.body.contains("Privacy filtering"))

        let terms = AppSupportDocument.terms
        XCTAssertEqual(terms.buttonTitle, "Terms of Use")
        XCTAssertTrue(terms.body.contains("\"as is\""))

        let community = AppSupportDocument.community
        XCTAssertEqual(community.buttonTitle, "Community Guide")
        XCTAssertTrue(community.body.contains("https://discord.gg/ZrqF5jwQ"))

        let checklist = AppSupportDocument.launchChecklist
        XCTAssertEqual(checklist.buttonTitle, "Launch Checklist")
        XCTAssertTrue(checklist.body.contains("notarization"))
    }
}
