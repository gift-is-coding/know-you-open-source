import Foundation

enum NetworkingAuthMode: String, Codable, Equatable {
    case supabaseMachineUser
}

struct NetworkingPeopleSyncPayload: Codable, Equatable {
    let displayName: String
    let handle: String
}

struct NetworkingActivationPlan: Codable, Equatable {
    let authMode: NetworkingAuthMode
    let peoplePayload: NetworkingPeopleSyncPayload
    let profilePayloads: [NetworkingProfileSyncPayload]
    let agentTokenPlaintext: String
    let agentTokenLabel: String
    let authEmail: String?
    let authPassword: String?
}

enum NetworkingActivationMode: String, Codable, Equatable {
    case platform
    case localSandbox
}

struct NetworkingActivationState: Codable, Equatable {
    let isEnabled: Bool
    let personID: String
    let agentTokenPlaintext: String
    let supabaseURL: URL
    let publishableKey: String
    var mode: NetworkingActivationMode = .localSandbox
    var userID: String?
    var refreshToken: String?
    var authEmail: String?
    var authPassword: String?
    var profileIDMapping: [String: String] = [:]

    init(
        isEnabled: Bool,
        personID: String,
        agentTokenPlaintext: String,
        supabaseURL: URL,
        publishableKey: String,
        authEmail: String? = nil,
        authPassword: String? = nil,
        mode: NetworkingActivationMode = .localSandbox,
        userID: String? = nil,
        refreshToken: String? = nil,
        profileIDMapping: [String: String] = [:]
    ) {
        self.isEnabled = isEnabled
        self.personID = personID
        self.agentTokenPlaintext = agentTokenPlaintext
        self.supabaseURL = supabaseURL
        self.publishableKey = publishableKey
        self.mode = mode
        self.userID = userID
        self.refreshToken = refreshToken
        self.authEmail = authEmail
        self.authPassword = authPassword
        self.profileIDMapping = profileIDMapping
    }

    var isPlatformConnected: Bool {
        mode == .platform
    }

    /// Maps an App-local profile identifier (for example "profile-career") to
    /// the platform profile UUID created during activation.
    func platformProfileID(forLocalProfileID localProfileID: String) -> String? {
        profileIDMapping[localProfileID]
    }

    private enum CodingKeys: String, CodingKey {
        case isEnabled
        case personID
        case agentTokenPlaintext
        case supabaseURL
        case publishableKey
        case mode
        case userID
        case refreshToken
        case authEmail
        case authPassword
        case profileIDMapping
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        isEnabled = try container.decode(Bool.self, forKey: .isEnabled)
        personID = try container.decode(String.self, forKey: .personID)
        agentTokenPlaintext = try container.decode(String.self, forKey: .agentTokenPlaintext)
        supabaseURL = try container.decode(URL.self, forKey: .supabaseURL)
        publishableKey = try container.decode(String.self, forKey: .publishableKey)
        mode = try container.decodeIfPresent(NetworkingActivationMode.self, forKey: .mode) ?? .localSandbox
        userID = try container.decodeIfPresent(String.self, forKey: .userID)
        refreshToken = try container.decodeIfPresent(String.self, forKey: .refreshToken)
        authEmail = try container.decodeIfPresent(String.self, forKey: .authEmail)
        authPassword = try container.decodeIfPresent(String.self, forKey: .authPassword)
        profileIDMapping = try container.decodeIfPresent([String: String].self, forKey: .profileIDMapping) ?? [:]
    }
}

struct NetworkingActivationService {
    var tokenGenerator: () -> String = {
        "knw_agent_\(UUID().uuidString.replacingOccurrences(of: "-", with: "").lowercased())"
    }

    func activationPlan(
        personName: String,
        handle: String,
        approvedProfiles: [NetworkingProfileSyncPayload]
    ) -> NetworkingActivationPlan {
        NetworkingActivationPlan(
            authMode: .supabaseMachineUser,
            peoplePayload: NetworkingPeopleSyncPayload(displayName: personName, handle: handle),
            profilePayloads: approvedProfiles,
            agentTokenPlaintext: tokenGenerator(),
            agentTokenLabel: "Local KnowYou Networking agent",
            authEmail: nil,
            authPassword: nil
        )
    }
}

struct NetworkingActivationStateStore {
    let fileManager: FileManager

    init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
    }

    func load(projectRoot: URL) -> NetworkingActivationState? {
        let url = stateURL(projectRoot: projectRoot)
        guard fileManager.fileExists(atPath: url.path),
              let data = try? Data(contentsOf: url) else {
            return nil
        }
        return try? JSONDecoder().decode(NetworkingActivationState.self, from: data)
    }

    func save(_ state: NetworkingActivationState, projectRoot: URL) throws {
        let url = stateURL(projectRoot: projectRoot)
        try fileManager.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(state)
        try data.write(to: url, options: .atomic)
    }

    func stateURL(projectRoot: URL) -> URL {
        projectRoot.appending(path: ".knowyou/networking/activation.json")
    }
}

struct NetworkingInboxState: Codable, Equatable, Sendable {
    let items: [NetworkingCockpitItem]

    init(items: [NetworkingCockpitItem] = []) {
        self.items = items
    }

    func recording(_ item: NetworkingCockpitItem) -> NetworkingInboxState {
        NetworkingInboxState(items: [item] + items.filter { $0.id != item.id })
    }
}

struct NetworkingInboxStateStore {
    let fileManager: FileManager

    init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
    }

    func load(projectRoot: URL) -> NetworkingInboxState {
        let url = stateURL(projectRoot: projectRoot)
        guard fileManager.fileExists(atPath: url.path),
              let data = try? Data(contentsOf: url),
              let state = try? JSONDecoder().decode(NetworkingInboxState.self, from: data) else {
            return NetworkingInboxState()
        }
        return state
    }

    func save(_ state: NetworkingInboxState, projectRoot: URL) throws {
        let url = stateURL(projectRoot: projectRoot)
        try fileManager.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(state)
        try data.write(to: url, options: .atomic)
    }

    func stateURL(projectRoot: URL) -> URL {
        projectRoot.appending(path: ".knowyou/networking/inbox-state.json")
    }
}

struct NetworkingProfileApprovalStateStore {
    let fileManager: FileManager

    init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
    }

    func load(projectRoot: URL) -> NetworkingProfileApprovalState {
        let url = stateURL(projectRoot: projectRoot)
        guard fileManager.fileExists(atPath: url.path),
              let data = try? Data(contentsOf: url),
              let state = try? JSONDecoder().decode(NetworkingProfileApprovalState.self, from: data) else {
            return NetworkingProfileApprovalState()
        }
        return state
    }

    func save(_ state: NetworkingProfileApprovalState, projectRoot: URL) throws {
        let url = stateURL(projectRoot: projectRoot)
        try fileManager.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(state)
        try data.write(to: url, options: .atomic)
    }

    func stateURL(projectRoot: URL) -> URL {
        projectRoot.appending(path: ".knowyou/networking/profile-approval.json")
    }
}

struct NetworkingProfileDraftState: Codable, Equatable {
    let draftsByProfileID: [String: NetworkingProfileDraft]
    let customProfiles: [NetworkingCustomProfileConfiguration]
    let lastDailyUpdateCheckAt: Date?

    init(
        draftsByProfileID: [String: NetworkingProfileDraft] = [:],
        customProfiles: [NetworkingCustomProfileConfiguration] = [],
        lastDailyUpdateCheckAt: Date? = nil
    ) {
        self.draftsByProfileID = draftsByProfileID
        self.customProfiles = customProfiles
        self.lastDailyUpdateCheckAt = lastDailyUpdateCheckAt
    }

    func storing(_ draft: NetworkingProfileDraft, forProfileID profileID: String) -> NetworkingProfileDraftState {
        var nextDrafts = draftsByProfileID
        nextDrafts[profileID] = draft
        return NetworkingProfileDraftState(
            draftsByProfileID: nextDrafts,
            customProfiles: customProfiles,
            lastDailyUpdateCheckAt: lastDailyUpdateCheckAt
        )
    }

    func storingCustomProfile(_ customProfile: NetworkingCustomProfileConfiguration) -> NetworkingProfileDraftState {
        var nextCustomProfiles = customProfiles.filter { $0.id != customProfile.id }
        nextCustomProfiles.append(customProfile)
        return NetworkingProfileDraftState(
            draftsByProfileID: draftsByProfileID,
            customProfiles: nextCustomProfiles,
            lastDailyUpdateCheckAt: lastDailyUpdateCheckAt
        )
    }

    func markingDailyUpdateChecked(at date: Date) -> NetworkingProfileDraftState {
        NetworkingProfileDraftState(
            draftsByProfileID: draftsByProfileID,
            customProfiles: customProfiles,
            lastDailyUpdateCheckAt: date
        )
    }

    func fillingMissingDraftTimestamps(with fallbackDate: Date) -> NetworkingProfileDraftState {
        var nextDrafts: [String: NetworkingProfileDraft] = [:]
        for (profileID, draft) in draftsByProfileID {
            var nextDraft = draft
            if nextDraft.generatedAt == nil {
                nextDraft.generatedAt = fallbackDate
            }
            if nextDraft.updatedAt == nil {
                nextDraft.updatedAt = fallbackDate
            }
            nextDrafts[profileID] = nextDraft
        }
        return NetworkingProfileDraftState(
            draftsByProfileID: nextDrafts,
            customProfiles: customProfiles,
            lastDailyUpdateCheckAt: lastDailyUpdateCheckAt
        )
    }

    private enum CodingKeys: String, CodingKey {
        case draftsByProfileID
        case customProfiles
        case lastDailyUpdateCheckAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        draftsByProfileID = try container.decodeIfPresent([String: NetworkingProfileDraft].self, forKey: .draftsByProfileID) ?? [:]
        customProfiles = try container.decodeIfPresent([NetworkingCustomProfileConfiguration].self, forKey: .customProfiles) ?? []
        lastDailyUpdateCheckAt = try container.decodeIfPresent(Date.self, forKey: .lastDailyUpdateCheckAt)
    }
}

struct NetworkingProfileDraftStateStore {
    let fileManager: FileManager

    init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
    }

    func load(projectRoot: URL) -> NetworkingProfileDraftState {
        let url = stateURL(projectRoot: projectRoot)
        guard fileManager.fileExists(atPath: url.path),
              let data = try? Data(contentsOf: url),
              let state = try? JSONDecoder().decode(NetworkingProfileDraftState.self, from: data) else {
            return NetworkingProfileDraftState()
        }
        let modifiedAt = (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? Date()
        return state.fillingMissingDraftTimestamps(with: modifiedAt)
    }

    func save(_ state: NetworkingProfileDraftState, projectRoot: URL) throws {
        let url = stateURL(projectRoot: projectRoot)
        try fileManager.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(state)
        try data.write(to: url, options: .atomic)
    }

    func stateURL(projectRoot: URL) -> URL {
        projectRoot.appending(path: ".knowyou/networking/profile-drafts.json")
    }
}
