import Foundation

enum NetworkingProfileDraftSource: String, Codable, Equatable {
    case myWiki
    case manual
}

enum NetworkingProfileApprovalStatus: String, Codable, Equatable {
    case draft
    case approved
}

struct NetworkingProfileDraft: Codable, Equatable, Identifiable {
    let id: String
    let personName: String
    let profileLabel: String
    let summary: String
    let body: String
    let source: NetworkingProfileDraftSource
    let approvalStatus: NetworkingProfileApprovalStatus

    var canPublish: Bool {
        approvalStatus == .approved
    }

    var publicSyncPayload: NetworkingProfileSyncPayload? {
        guard canPublish else { return nil }
        return NetworkingProfileSyncPayload(
            profileID: id,
            personName: personName,
            profileLabel: profileLabel,
            summary: summary,
            body: body
        )
    }
}

extension NetworkingProfileDraft {
    init(
        id: String,
        personName: String,
        profileLabel: String,
        summary: String,
        source: NetworkingProfileDraftSource,
        approvalStatus: NetworkingProfileApprovalStatus
    ) {
        self.init(
            id: id,
            personName: personName,
            profileLabel: profileLabel,
            summary: summary,
            body: summary,
            source: source,
            approvalStatus: approvalStatus
        )
    }
}

struct NetworkingMyWikiProfileSignal: Codable, Equatable, Identifiable {
    let id: String
    let personName: String
    let profileLabel: String
    let summary: String
    let body: String
}

struct NetworkingProfileScenario: Codable, Equatable, Identifiable {
    let id: String
    let label: String
    let prompt: String
    let platformID: String
    let description: String

    static let jobs = NetworkingProfileScenario(
        id: "jobs",
        label: "职业/求职",
        prompt: "结合 My Wiki，总结我适合什么工作、能负责什么项目、正在寻找什么机会或候选人。",
        platformID: "knowyou-jobs",
        description: "用于 Know You 求职，覆盖求职、招聘、合作和职业机会。"
    )

    static let friends = NetworkingProfileScenario(
        id: "friends",
        label: "认识新朋友",
        prompt: "结合 My Wiki，总结我的兴趣、活动、性格、社交节奏和适合认识什么样的新朋友。",
        platformID: "knowyou-friends",
        description: "用于 Know You 认识新朋友，覆盖兴趣、活动和轻社交。"
    )

    static let defaults: [NetworkingProfileScenario] = [.jobs, .friends]

    init(id: String, label: String, prompt: String, platformID: String = "", description: String = "") {
        self.id = id
        self.label = label
        self.prompt = prompt
        self.platformID = platformID
        self.description = description
    }
}

struct NetworkingProfileAvatar: Codable, Equatable {
    let imageURL: URL?
    let fallbackLetter: String
    let backgroundHex: String
    let avatarSeed: String
    let avatarStyle: String

    init(
        imageURL: URL? = nil,
        fallbackLetter: String,
        backgroundHex: String,
        avatarSeed: String = "",
        avatarStyle: String = "initials"
    ) {
        self.imageURL = imageURL
        self.fallbackLetter = fallbackLetter
        self.backgroundHex = backgroundHex
        self.avatarSeed = avatarSeed.isEmpty ? fallbackLetter : avatarSeed
        self.avatarStyle = avatarStyle
    }

    var displayLetter: String {
        String(fallbackLetter.prefix(1))
    }

    var usesFallback: Bool {
        imageURL == nil
    }
}

struct NetworkingProfileSummarySection: Codable, Equatable, Identifiable {
    var id: String { title }

    let title: String
    let body: String
}

struct NetworkingGeneratedProfile: Codable, Equatable, Identifiable {
    let id: String
    let personName: String
    let displayName: String
    let label: String
    let englishLabel: String
    let scenarioID: String
    let scenarioDescription: String
    let prompt: String
    let avatar: NetworkingProfileAvatar
    let summarySections: [NetworkingProfileSummarySection]
    let autoUpdate: Bool
    let lastUpdatedLabel: String?
    let platformIDs: [String]

    var hasGeneratedOutput: Bool {
        summarySections.isEmpty == false
    }

    var publicSummary: String {
        summarySections.map { "\($0.title): \($0.body)" }.joined(separator: "\n\n")
    }

    init(
        id: String,
        personName: String = "林书涵",
        displayName: String,
        label: String,
        englishLabel: String,
        scenarioID: String = "",
        scenarioDescription: String = "",
        prompt: String,
        avatar: NetworkingProfileAvatar,
        summarySections: [NetworkingProfileSummarySection],
        autoUpdate: Bool,
        lastUpdatedLabel: String?,
        platformIDs: [String] = []
    ) {
        self.id = id
        self.personName = personName
        self.displayName = displayName
        self.label = label
        self.englishLabel = englishLabel
        self.scenarioID = scenarioID
        self.scenarioDescription = scenarioDescription
        self.prompt = prompt
        self.avatar = avatar
        self.summarySections = summarySections
        self.autoUpdate = autoUpdate
        self.lastUpdatedLabel = lastUpdatedLabel
        self.platformIDs = platformIDs
    }
}

struct NetworkingPlatformDefinition: Codable, Equatable, Identifiable {
    let id: String
    let displayName: String
    let subtitle: String
    let defaultScenarioID: String

    static let defaultPlatforms: [NetworkingPlatformDefinition] = [
        NetworkingPlatformDefinition(
            id: "knowyou-jobs",
            displayName: "Know You 求职",
            subtitle: "求职、招聘、合作机会",
            defaultScenarioID: NetworkingProfileScenario.jobs.id
        ),
        NetworkingPlatformDefinition(
            id: "knowyou-friends",
            displayName: "Know You 认识新朋友",
            subtitle: "兴趣、活动、轻社交",
            defaultScenarioID: NetworkingProfileScenario.friends.id
        ),
    ]
}

enum NetworkingPlatformStatus: String, Codable, Equatable {
    case active
    case paused
    case disconnected
}

struct NetworkingPlatformActivity: Codable, Equatable {
    let outbound: Int
    let inbound: Int
    let highlights: Int
}

struct NetworkingPlatformConfiguration: Codable, Equatable, Identifiable {
    let id: String
    let name: String
    let subtitle: String
    let assignedProfileID: String
    let status: NetworkingPlatformStatus
    let activity: NetworkingPlatformActivity

    func assignedProfile(in profiles: [NetworkingGeneratedProfile]) -> NetworkingGeneratedProfile? {
        profiles.first { $0.id == assignedProfileID }
    }

    func canRunAutomation(with profiles: [NetworkingGeneratedProfile]) -> Bool {
        guard status == .active,
              let profile = assignedProfile(in: profiles) else {
            return false
        }
        return profile.hasGeneratedOutput
    }

    func canRunAutomation(
        with profiles: [NetworkingGeneratedProfile],
        approvedProfileIDs: Set<String>
    ) -> Bool {
        guard status == .active,
              let profile = assignedProfile(in: profiles),
              profile.hasGeneratedOutput else {
            return false
        }
        return approvedProfileIDs.contains(profile.id)
    }
}

struct NetworkingProfileApprovalState: Codable, Equatable {
    let approvedProfileIDs: Set<String>

    init(approvedProfileIDs: Set<String> = []) {
        self.approvedProfileIDs = approvedProfileIDs
    }

    init(approvedProfileIDs: [String]) {
        self.approvedProfileIDs = Set(approvedProfileIDs)
    }

    func contains(_ profileID: String) -> Bool {
        approvedProfileIDs.contains(profileID)
    }

    func approving(_ profileID: String) -> NetworkingProfileApprovalState {
        var nextIDs = approvedProfileIDs
        nextIDs.insert(profileID)
        return NetworkingProfileApprovalState(approvedProfileIDs: nextIDs)
    }
}

struct NetworkingProfileSyncPayload: Codable, Equatable {
    let profileID: String
    let personName: String
    let profileLabel: String
    let summary: String
    let body: String
}

enum NetworkingContentKind: String, Codable, Equatable {
    case post
    case comment
}

enum NetworkingAuthorType: String, Codable, Equatable {
    case human
    case ai
}

struct NetworkingPublicContent: Codable, Equatable, Identifiable {
    let id: String
    let kind: NetworkingContentKind
    let authorType: NetworkingAuthorType
    let personName: String
    let profileLabel: String
    let body: String
    let createdAt: Date
}

enum NetworkingCockpitDirection: String, Codable, Equatable, CaseIterable {
    case highlight
    case inbound
    case outbound
    case activity
}

struct NetworkingCockpitItem: Codable, Equatable, Identifiable {
    let id: String
    let direction: NetworkingCockpitDirection
    let title: String
    let publicSummary: String
    let privateReason: String
    let publicReferenceID: String?
    let platformID: String

    init(
        id: String,
        direction: NetworkingCockpitDirection,
        title: String,
        publicSummary: String,
        privateReason: String,
        publicReferenceID: String?,
        platformID: String = "knowyou-careers"
    ) {
        self.id = id
        self.direction = direction
        self.title = title
        self.publicSummary = publicSummary
        self.privateReason = privateReason
        self.publicReferenceID = publicReferenceID
        self.platformID = platformID
    }
}

struct NetworkingCockpitSection: Codable, Equatable, Identifiable {
    var id: String { direction.rawValue }

    let direction: NetworkingCockpitDirection
    let title: String
    let items: [NetworkingCockpitItem]
}

enum NetworkingAgentActionKind: String, Codable, Equatable {
    case post
    case comment
}

enum NetworkingAgentActionStatus: String, Codable, Equatable {
    case queued
    case sent
    case skipped
}

struct NetworkingAgentAction: Codable, Equatable, Identifiable {
    let id: String
    let kind: NetworkingAgentActionKind
    let platformID: String
    let profileID: String
    let profileLabel: String
    let body: String
    let publicReferenceID: String?
    let privateReason: String
    let createdAt: Date
    let status: NetworkingAgentActionStatus

    var publicWritePayload: NetworkingAgentPublicWritePayload {
        NetworkingAgentPublicWritePayload(
            kind: kind,
            authorType: .ai,
            platformID: platformID,
            profileID: profileID,
            body: body,
            publicReferenceID: publicReferenceID
        )
    }

    init(
        id: String,
        kind: NetworkingAgentActionKind,
        platformID: String = "knowyou-jobs",
        profileID: String,
        profileLabel: String,
        body: String,
        publicReferenceID: String?,
        privateReason: String,
        createdAt: Date,
        status: NetworkingAgentActionStatus
    ) {
        self.id = id
        self.kind = kind
        self.platformID = platformID
        self.profileID = profileID
        self.profileLabel = profileLabel
        self.body = body
        self.publicReferenceID = publicReferenceID
        self.privateReason = privateReason
        self.createdAt = createdAt
        self.status = status
    }
}

struct NetworkingAgentPublicWritePayload: Codable, Equatable {
    let kind: NetworkingAgentActionKind
    let authorType: NetworkingAuthorType
    let platformID: String
    let profileID: String
    let body: String
    let publicReferenceID: String?
}

struct NetworkingAgentFrequencyGuard: Equatable {
    let maxActionsPerProfilePerHour: Int

    init(maxActionsPerProfilePerHour: Int = 6) {
        self.maxActionsPerProfilePerHour = maxActionsPerProfilePerHour
    }

    func shouldAllow(_ candidate: NetworkingAgentAction, existingActions: [NetworkingAgentAction]) -> Bool {
        let oneHourBeforeCandidate = candidate.createdAt.addingTimeInterval(-60 * 60)
        let recentMatchingProfileActions = existingActions.filter { action in
            action.profileID == candidate.profileID
                && action.status != .skipped
                && action.createdAt >= oneHourBeforeCandidate
                && action.createdAt <= candidate.createdAt
        }

        let duplicateBodyExists = recentMatchingProfileActions.contains { action in
            action.kind == candidate.kind
                && action.body.trimmingCharacters(in: .whitespacesAndNewlines)
                    .caseInsensitiveCompare(candidate.body.trimmingCharacters(in: .whitespacesAndNewlines)) == .orderedSame
        }

        return duplicateBodyExists == false
            && recentMatchingProfileActions.count < maxActionsPerProfilePerHour
    }
}

struct NetworkingPublicOpportunity: Codable, Equatable, Identifiable {
    let id: String
    let direction: NetworkingCockpitDirection
    let title: String
    let publicSummary: String
    let publicReferenceID: String?
    let platformID: String
    let profileID: String
    let profileLabel: String
    let suggestedActionKind: NetworkingAgentActionKind
    let suggestedBody: String
    let privateReason: String

    init(
        id: String,
        direction: NetworkingCockpitDirection,
        title: String,
        publicSummary: String,
        publicReferenceID: String?,
        platformID: String = "knowyou-jobs",
        profileID: String,
        profileLabel: String,
        suggestedActionKind: NetworkingAgentActionKind,
        suggestedBody: String,
        privateReason: String
    ) {
        self.id = id
        self.direction = direction
        self.title = title
        self.publicSummary = publicSummary
        self.publicReferenceID = publicReferenceID
        self.platformID = platformID
        self.profileID = profileID
        self.profileLabel = profileLabel
        self.suggestedActionKind = suggestedActionKind
        self.suggestedBody = suggestedBody
        self.privateReason = privateReason
    }
}

struct NetworkingAgentRuntime: Equatable {
    let frequencyGuard: NetworkingAgentFrequencyGuard

    init(frequencyGuard: NetworkingAgentFrequencyGuard = NetworkingAgentFrequencyGuard()) {
        self.frequencyGuard = frequencyGuard
    }

    func profileDrafts(from signals: [NetworkingMyWikiProfileSignal]) -> [NetworkingProfileDraft] {
        signals.map { signal in
            NetworkingProfileDraft(
                id: signal.id,
                personName: signal.personName,
                profileLabel: signal.profileLabel,
                summary: signal.summary,
                body: signal.body,
                source: .myWiki,
                approvalStatus: .draft
            )
        }
    }

    func profileDraft(
        from scenario: NetworkingProfileScenario,
        prompt: String,
        signal: NetworkingMyWikiProfileSignal
    ) -> NetworkingProfileDraft {
        NetworkingProfileDraft(
            id: "profile-\(scenario.id)-\(signal.id)",
            personName: signal.personName,
            profileLabel: signal.profileLabel,
            summary: signal.summary,
            body: """
            Prompt:
            \(prompt)

            My Wiki summary:
            \(signal.summary)

            My Wiki evidence:
            \(signal.body)
            """,
            source: .myWiki,
            approvalStatus: .draft
        )
    }

    func publicSyncPayloads(for drafts: [NetworkingProfileDraft]) -> [NetworkingProfileSyncPayload] {
        drafts.compactMap(\.publicSyncPayload)
    }

    func agentActions(
        for opportunities: [NetworkingPublicOpportunity],
        existingActions: [NetworkingAgentAction],
        createdAt: Date
    ) -> [NetworkingAgentAction] {
        var acceptedActions = existingActions

        return opportunities.compactMap { opportunity in
            let action = NetworkingAgentAction(
                id: "agent-\(opportunity.id)",
                kind: opportunity.suggestedActionKind,
                platformID: opportunity.platformID,
                profileID: opportunity.profileID,
                profileLabel: opportunity.profileLabel,
                body: opportunity.suggestedBody,
                publicReferenceID: opportunity.publicReferenceID,
                privateReason: opportunity.privateReason,
                createdAt: createdAt,
                status: .queued
            )

            guard frequencyGuard.shouldAllow(action, existingActions: acceptedActions) else {
                return nil
            }

            acceptedActions.append(action)
            return action
        }
    }

    func cockpitPresentation(
        highlights: [NetworkingPublicOpportunity],
        agentActions: [NetworkingAgentAction]
    ) -> NetworkingCockpitPresentation {
        let highlightItems = highlights.map { opportunity in
            NetworkingCockpitItem(
                id: opportunity.id,
                direction: opportunity.direction,
                title: opportunity.title,
                publicSummary: opportunity.publicSummary,
                privateReason: opportunity.privateReason,
                publicReferenceID: opportunity.publicReferenceID,
                platformID: opportunity.platformID
            )
        }

        return NetworkingCockpitPresentation(
            items: highlightItems + NetworkingCockpitPresentation.cockpitItems(for: agentActions)
        )
    }
}
