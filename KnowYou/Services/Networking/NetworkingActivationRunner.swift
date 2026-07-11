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

struct NetworkingMachineCredentials: Equatable, Sendable {
    let email: String
    let password: String
}

/// Executes a real platform activation: machine-user sign-in, person/profile sync,
/// agent token registration (hash only reaches the platform), and community
/// membership activation. The plaintext token stays in local activation state.
struct NetworkingActivationRunner: Sendable {
    let client: NetworkingPlatformClient
    var tokenGenerator: @Sendable () -> String = {
        "knw_agent_\(UUID().uuidString.replacingOccurrences(of: "-", with: "").lowercased())"
    }
    var credentialGenerator: @Sendable (_ handle: String) -> NetworkingMachineCredentials = { handle in
        let safeHandle = handle
            .lowercased()
            .unicodeScalars
            .map { CharacterSet.alphanumerics.contains($0) ? Character($0) : "-" }
            .reduce(into: "") { $0.append($1) }
            .trimmingCharacters(in: CharacterSet(charactersIn: "-"))
        let prefix = safeHandle.isEmpty ? "person" : safeHandle
        let suffix = UUID().uuidString.replacingOccurrences(of: "-", with: "").lowercased()
        let credentialValue = [
            "knw",
            UUID().uuidString.replacingOccurrences(of: "-", with: "").lowercased(),
        ].joined(separator: "_")
        return NetworkingMachineCredentials(
            email: "knw-\(prefix)-\(suffix)@users.knowyou.app",
            password: credentialValue
        )
    }

    func activate(
        personName: String,
        handle: String,
        approvedProfiles: [NetworkingProfileRegistration],
        previousState: NetworkingActivationState? = nil
    ) throws -> NetworkingActivationState {
        if previousState?.isPlatformConnected == true, previousState?.machineCredentials == nil {
            throw NetworkingActivationRunnerError.missingStoredIdentityCredentials
        }
        let credentials = previousState?.machineCredentials ?? credentialGenerator(handle)
        let session: NetworkingPlatformSession
        if previousState?.machineCredentials != nil {
            do {
                session = try client.signIn(email: credentials.email, password: credentials.password)
            } catch let signInError {
                throw NetworkingActivationRunnerError.activationFailed(
                    step: "signing in the machine platform identity",
                    underlying: signInError.localizedDescription
                )
            }
        } else {
            do {
                session = try client.signUp(email: credentials.email, password: credentials.password)
            } catch {
                throw NetworkingActivationRunnerError.activationFailed(
                    step: "creating the machine platform identity",
                    underlying: error.localizedDescription
                )
            }
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
            authEmail: credentials.email,
            authPassword: credentials.password,
            mode: .platform,
            userID: session.userID,
            refreshToken: session.refreshToken,
            profileIDMapping: profileIDMapping
        )
    }
}

private extension NetworkingActivationState {
    var machineCredentials: NetworkingMachineCredentials? {
        guard let authEmail,
              authEmail.isEmpty == false,
              let authPassword,
              authPassword.isEmpty == false else {
            return nil
        }
        return NetworkingMachineCredentials(email: authEmail, password: authPassword)
    }
}
