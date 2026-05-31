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
