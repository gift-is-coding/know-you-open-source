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

    func stateURL(projectRoot: URL) -> URL {
        projectRoot.appending(path: ".knowyou/networking/activation.json")
    }
}
