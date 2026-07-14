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
    case missingStoredIdentityCredentials

    var errorDescription: String? {
        switch self {
        case let .activationFailed(step, underlying):
            return "Networking activation failed while \(step): \(underlying)"
        case .missingStoredIdentityCredentials:
            return "This Networking identity is already connected, but its secure credentials are unavailable. Restore the Keychain credentials before reconnecting."
        }
    }
}

/// Executes activation after Supabase has verified the human email: person/profile sync,
/// agent token registration (hash only reaches the platform), and community
/// membership activation. The plaintext token stays in local activation state.
struct NetworkingActivationRunner: Sendable {
    let client: NetworkingPlatformClient
    var tokenGenerator: @Sendable () -> String = {
        "knw_agent_\(UUID().uuidString.replacingOccurrences(of: "-", with: "").lowercased())"
    }
    var deviceTokenGenerator: @Sendable () -> String = {
        "knw_device_\(UUID().uuidString.replacingOccurrences(of: "-", with: "").lowercased())\(UUID().uuidString.replacingOccurrences(of: "-", with: "").lowercased())"
    }

    func activate(
        session: NetworkingPlatformSession,
        email: String,
        deviceID: String,
        deviceDisplayName: String,
        personName: String,
        handle: String,
        approvedProfiles: [NetworkingProfileRegistration]
    ) throws -> NetworkingActivationState {
        let tokenPlaintext = tokenGenerator()
        let deviceToken = deviceTokenGenerator()
        let personID: String
        do {
            personID = try client.beginActivation(
                session: session,
                displayName: personName,
                handle: handle,
                deviceID: deviceID,
                deviceDisplayName: deviceDisplayName,
                deviceTokenHash: NetworkingPlatformClient.tokenHash(deviceToken),
                agentTokenHash: NetworkingPlatformClient.tokenHash(tokenPlaintext),
                agentTokenLabel: "Local KnowYou Networking agent"
            )
        } catch {
            throw NetworkingActivationRunnerError.activationFailed(
                step: "authorizing this Mac",
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
            authEmail: email,
            mode: .platform,
            userID: session.userID,
            refreshToken: session.refreshToken,
            deviceID: deviceID,
            deviceDisplayName: deviceDisplayName,
            deviceToken: deviceToken,
            profileIDMapping: profileIDMapping
        )
    }
}
