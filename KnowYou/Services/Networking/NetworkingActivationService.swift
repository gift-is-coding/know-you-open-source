import Foundation

enum NetworkingAuthMode: String, Codable, Equatable {
    case supabaseAnonymous
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
}

struct NetworkingActivationState: Codable, Equatable {
    let isEnabled: Bool
    let personID: String
    let agentTokenPlaintext: String
    let supabaseURL: URL
    let publishableKey: String
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
            authMode: .supabaseAnonymous,
            peoplePayload: NetworkingPeopleSyncPayload(displayName: personName, handle: handle),
            profilePayloads: approvedProfiles,
            agentTokenPlaintext: tokenGenerator(),
            agentTokenLabel: "Local KnowYou Networking agent"
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
