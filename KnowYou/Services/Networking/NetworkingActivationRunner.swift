import Foundation

struct NetworkingProfileRegistration: Codable, Equatable {
    let localProfileID: String
    let slug: String
    let label: String
    let scenarioID: String
    let scenarioDescription: String
    let summary: String
    let body: String
    let platformIDs: [String]
}

enum NetworkingActivationRunnerError: LocalizedError {
    case activationFailed(step: String, underlying: String)

    var errorDescription: String? {
        switch self {
        case let .activationFailed(step, underlying):
            return "Networking activation failed while \(step): \(underlying)"
        }
    }
}

/// Executes a real platform activation: anonymous sign-in, person/profile sync,
/// agent token registration (hash only reaches the platform), and community
/// membership activation. The plaintext token stays in local activation state.
struct NetworkingActivationRunner: Sendable {
    let client: NetworkingPlatformClient
    var tokenGenerator: @Sendable () -> String = {
        "knw_agent_\(UUID().uuidString.replacingOccurrences(of: "-", with: "").lowercased())"
    }

    func activate(
        personName: String,
        handle: String,
        approvedProfiles: [NetworkingProfileRegistration]
    ) throws -> NetworkingActivationState {
        let session: NetworkingPlatformSession
        do {
            session = try client.signInAnonymously()
        } catch {
            throw NetworkingActivationRunnerError.activationFailed(
                step: "creating the anonymous platform identity",
                underlying: error.localizedDescription
            )
        }

        let personID: String
        do {
            personID = try client.upsertPerson(session: session, displayName: personName, handle: handle)
        } catch {
            throw NetworkingActivationRunnerError.activationFailed(
                step: "syncing the public person record",
                underlying: error.localizedDescription
            )
        }

        var profileIDMapping: [String: String] = [:]
        for registration in approvedProfiles {
            do {
                let platformProfileID = try client.upsertProfile(
                    session: session,
                    personID: personID,
                    registration: registration
                )
                profileIDMapping[registration.localProfileID] = platformProfileID
            } catch {
                throw NetworkingActivationRunnerError.activationFailed(
                    step: "publishing profile \(registration.label)",
                    underlying: error.localizedDescription
                )
            }
        }

        let tokenPlaintext = tokenGenerator()
        do {
            try client.registerAgentToken(
                session: session,
                personID: personID,
                tokenPlaintext: tokenPlaintext,
                label: "Local KnowYou Networking agent"
            )
        } catch {
            throw NetworkingActivationRunnerError.activationFailed(
                step: "registering the local agent token",
                underlying: error.localizedDescription
            )
        }

        for registration in approvedProfiles {
            guard let platformProfileID = profileIDMapping[registration.localProfileID] else { continue }
            for communityID in registration.platformIDs {
                do {
                    try client.activateMembership(
                        session: session,
                        personID: personID,
                        profileID: platformProfileID,
                        communityID: communityID
                    )
                } catch {
                    throw NetworkingActivationRunnerError.activationFailed(
                        step: "activating \(communityID) membership for \(registration.label)",
                        underlying: error.localizedDescription
                    )
                }
            }
        }

        return NetworkingActivationState(
            isEnabled: true,
            personID: personID,
            agentTokenPlaintext: tokenPlaintext,
            supabaseURL: client.config.supabaseURL,
            publishableKey: client.config.publishableKey,
            mode: .platform,
            userID: session.userID,
            refreshToken: session.refreshToken,
            profileIDMapping: profileIDMapping
        )
    }
}
