import Foundation

struct AppSupportMetadata {
    static let twitterURL = URL(string: "https://x.com/TianfuW49629")!
    static let contactEmail = "cestlouiswu@gmail.com"
    static let emailURL = URL(string: "mailto:\(contactEmail)")!
    static let discordURL = URL(string: "https://discord.gg/ZrqF5jwQ")
    static let productTagline = "A local-first daily story for your workday on Mac."
    static let twitterButtonTitle = "Follow on X / Twitter"
    static let emailButtonTitle = "Send Email"
    static let discordButtonTitle = "Join Discord Community"
    static let discordDescription = "Discuss product ideas, share feedback, and compare journaling workflows with other users."
    static let supportDescription = "For privacy-sensitive topics or anything that should not be discussed in public, please contact us by email."
    static let companyEnglishName = "Shanghai Erren Beiwu Software Co., Ltd."
    static let copyrightLine = "Copyright © 2026 Shanghai Erren Beiwu Software Co., Ltd. All rights reserved."
}

struct AppRuntimeProfile {
    static let newUserBundleIdentifier = "dev.knowyou.newuser"
    static let profileRootEnvironmentKey = "KNOWYOU_PROFILE_ROOT"
    static let keychainServiceEnvironmentKey = "KNOWYOU_KEYCHAIN_SERVICE"

    nonisolated(unsafe) private static var currentEnvironmentOverrideForTesting: [String: String]?

    let displayName: String
    let supportDirectoryName: String
    let keychainService: String
    private let profileRootPath: String?

    init(bundleIdentifier: String?, processEnvironment: [String: String] = ProcessInfo.processInfo.environment) {
        if bundleIdentifier == Self.newUserBundleIdentifier {
            displayName = "KnowYou New User"
            supportDirectoryName = "KnowYou New User"
            keychainService = Self.newUserBundleIdentifier
        } else {
            displayName = "KnowYou"
            supportDirectoryName = "KnowYou"
            keychainService = processEnvironment[Self.keychainServiceEnvironmentKey] ?? "com.knowyou.app"
        }
        profileRootPath = processEnvironment[Self.profileRootEnvironmentKey]
    }

    init(bundle: Bundle = .main) {
        self.init(
            bundleIdentifier: bundle.bundleIdentifier,
            processEnvironment: Self.currentEnvironmentOverrideForTesting ?? ProcessInfo.processInfo.environment
        )
    }

    static var current: AppRuntimeProfile {
        AppRuntimeProfile()
    }

    static func setCurrentEnvironmentForTesting(_ environment: [String: String]?) {
        currentEnvironmentOverrideForTesting = environment
    }

    func applicationSupportDirectoryURL(create: Bool = true) throws -> URL {
        let applicationSupportURL: URL
        if let profileRootPath, profileRootPath.isEmpty == false {
            applicationSupportURL = URL(fileURLWithPath: profileRootPath, isDirectory: true)
                .appending(path: "Application Support", directoryHint: .isDirectory)
            if create {
                try FileManager.default.createDirectory(at: applicationSupportURL, withIntermediateDirectories: true)
            }
        } else {
            applicationSupportURL = try FileManager.default.url(
                for: .applicationSupportDirectory,
                in: .userDomainMask,
                appropriateFor: nil,
                create: create
            )
        }
        let appDirectoryURL = applicationSupportURL.appending(
            path: supportDirectoryName,
            directoryHint: .isDirectory
        )
        if create {
            try FileManager.default.createDirectory(at: appDirectoryURL, withIntermediateDirectories: true)
        }
        return appDirectoryURL
    }

    static func applicationSupportDirectoryURL(create: Bool = true) throws -> URL {
        try current.applicationSupportDirectoryURL(create: create)
    }
}

struct AppBuildMetadata: Equatable {
    let marketingVersion: String
    let buildNumber: String
    let buildTimestamp: String?
    let gitShortSHA: String?

    init(marketingVersion: String, buildNumber: String, buildTimestamp: String?, gitShortSHA: String?) {
        self.marketingVersion = marketingVersion
        self.buildNumber = buildNumber
        let normalizedTimestamp = buildTimestamp?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let normalizedTimestamp, normalizedTimestamp.isEmpty == false {
            self.buildTimestamp = normalizedTimestamp
        } else {
            self.buildTimestamp = nil
        }

        let normalizedSHA = gitShortSHA?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let normalizedSHA, normalizedSHA.isEmpty == false, normalizedSHA != "unknown" {
            self.gitShortSHA = normalizedSHA
        } else {
            self.gitShortSHA = nil
        }
    }

    init(bundle: Bundle) {
        let info = bundle.infoDictionary ?? [:]
        let resource = BuildMetadataResource.load(from: bundle)
        self.init(
            marketingVersion: info["CFBundleShortVersionString"] as? String ?? "0",
            buildNumber: resource?.buildNumber ?? (info["CFBundleVersion"] as? String ?? "0"),
            buildTimestamp: resource?.buildTimestamp,
            gitShortSHA: resource?.gitShortSHA
        )
    }

    static var current: AppBuildMetadata {
        AppBuildMetadata(bundle: .main)
    }

    var badgeText: String {
        let base: String
        if let buildTimestamp {
            base = "v\(marketingVersion) · \(buildTimestamp) (\(buildNumber))"
        } else {
            base = "v\(marketingVersion) (\(buildNumber))"
        }
        guard let gitShortSHA else { return base }
        return "\(base) · \(gitShortSHA)"
    }
}

private struct BuildMetadataResource: Decodable {
    let buildNumber: String?
    let buildTimestamp: String?
    let gitShortSHA: String?

    static func load(from bundle: Bundle) -> BuildMetadataResource? {
        guard let url = bundle.url(forResource: "BuildMetadata", withExtension: "json"),
              let data = try? Data(contentsOf: url) else {
            return nil
        }

        return try? JSONDecoder().decode(BuildMetadataResource.self, from: data)
    }
}

struct AppSupportDocument: Identifiable {
    let id: String
    let buttonTitle: String
    let title: String
    let body: String

    static let privacy = AppSupportDocument(
        id: "privacy",
        buttonTitle: "Privacy Policy",
        title: "Privacy Policy",
        body: """
        KnowYou is a local-first macOS application.

        We currently process data from this Mac's system clipboard, the local Notification Center database, and related metadata such as source apps, capture timestamps, and day keys.

        Privacy filtering happens before content is persisted. That means obviously sensitive content should not be written verbatim into local SQLite storage, and local Markdown output is not intended to be an unfiltered dump of raw context.

        By default, KnowYou stores runtime data locally on this Mac, including:
        - ~/Library/Application Support/\(AppRuntimeProfile.current.supportDirectoryName)/events.sqlite
        - ~/Library/Application Support/\(AppRuntimeProfile.current.supportDirectoryName)/Vault

        External summarizers are optional enhancements. They are not required for onboarding or for generating your first local story.

        Contact:
        - X / Twitter: https://x.com/TianfuW49629
        - Email: cestlouiswu@gmail.com
        """
    )

    static let terms = AppSupportDocument(
        id: "terms",
        buttonTitle: "Terms of Use",
        title: "Terms of Use",
        body: """
        KnowYou is provided on an "as is" basis, without express or implied warranties.

        You are responsible for deciding whether KnowYou is appropriate for your device, work environment, and data context. You are also responsible for reviewing locally stored content, protecting your devices and accounts, and deciding whether to enable any third-party summarizers.

        If you configure and use third-party summarizers or related external tools, your relationship with those services is governed by their own terms and privacy policies.

        You may not use KnowYou for unlawful purposes or to violate the privacy, intellectual property, or other legitimate rights of others.

        Copyright © 2026 Shanghai Erren Beiwu Software Co., Ltd. All rights reserved.
        """
    )

    static let community = AppSupportDocument(
        id: "community",
        buttonTitle: "Community Guide",
        title: "Community Guide",
        body: """
        Discord is the primary community space for KnowYou. It is the right place to discuss product ideas, share feedback, and compare journaling workflows.

        Current invite link:
        https://discord.gg/ZrqF5jwQ

        Recommended channels:
        - #welcome
        - #announcements
        - #general
        - #show-your-story
        - #feedback
        - #bug-reports
        - #off-topic

        If the topic involves private information, sensitive work context, or anything that should not be shared publicly, please contact us by email: cestlouiswu@gmail.com
        """
    )

    static let launchChecklist = AppSupportDocument(
        id: "launch-checklist",
        buttonTitle: "Launch Checklist",
        title: "Launch Checklist",
        body: """
        Legal and documentation
        - Privacy policy
        - Terms of use
        - Community guide
        - Support email

        Community
        - Discord server
        - Stable invite link
        - #welcome copy
        - Community rules

        Product and distribution
        - App icon
        - Product screenshots
        - Release notes
        - Download page or official website landing page

        macOS release readiness
        - Developer ID signing
        - notarization
        - Release package verification
        - First-install instructions
        - Permission guidance screenshots
        """
    )
}
