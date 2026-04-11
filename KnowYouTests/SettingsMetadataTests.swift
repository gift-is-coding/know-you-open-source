import XCTest
@testable import KnowYou

final class SettingsMetadataTests: XCTestCase {
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
        XCTAssertEqual(AppSupportMetadata.discordButtonTitle, "加入 Discord 社区")
        XCTAssertEqual(AppSupportMetadata.discordDescription, "适合讨论产品想法、反馈体验、分享你的日记工作流。")
        XCTAssertEqual(
            AppSupportMetadata.supportDescription,
            "隐私问题或不适合公开讨论的内容，请直接发邮件联系。"
        )
        XCTAssertEqual(
            AppSupportMetadata.emailURL.absoluteString,
            "mailto:cestlouiswu@gmail.com"
        )
    }

    func testInAppDocumentsExposeReadableContentWithoutRepositoryLinks() {
        let privacy = AppSupportDocument.privacy
        XCTAssertEqual(privacy.buttonTitle, "隐私政策")
        XCTAssertTrue(privacy.body.contains("本地优先"))
        XCTAssertTrue(privacy.body.contains("过滤"))

        let terms = AppSupportDocument.terms
        XCTAssertEqual(terms.buttonTitle, "使用条款")
        XCTAssertTrue(terms.body.contains("按“现状”提供"))

        let community = AppSupportDocument.community
        XCTAssertEqual(community.buttonTitle, "社区说明")
        XCTAssertTrue(community.body.contains("https://discord.gg/ZrqF5jwQ"))

        let checklist = AppSupportDocument.launchChecklist
        XCTAssertEqual(checklist.buttonTitle, "上线清单")
        XCTAssertTrue(checklist.body.contains("notarization"))
    }
}
