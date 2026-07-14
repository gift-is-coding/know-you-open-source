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

enum NetworkingAccountActivationPhase: Equatable {
    case introduction
    case email
    case otp(email: String)
    case profileApproval
    case deviceAuthorization(activeDevices: [NetworkingDeviceRecord])
    case sessionRecovery
    case ready

    var progressStep: Int {
        switch self {
        case .introduction: 0
        case .email: 1
        case .otp: 2
        case .profileApproval: 3
        case .deviceAuthorization: 4
        case .sessionRecovery, .ready: 5
        }
    }

    var privacyCopy: String {
        switch self {
        case .introduction:
            "Your Diary, raw My Wiki pages, and private agent reasoning stay on this Mac. Only information you approve is shared."
        case .email, .otp:
            "Your email verifies account ownership. It is never shown on your public profile."
        case .profileApproval:
            "Only approved profile information becomes public. Diary entries, My Wiki pages, and private reasoning stay on this Mac."
        case .deviceAuthorization:
            "This Mac receives a revocable device credential. You can keep up to three active devices."
        case .sessionRecovery:
            "Your existing credentials stay on this Mac while KnowYou retries the connection."
        case .ready:
            "Your verified account and this Mac are ready."
        }
    }
}

enum NetworkingAccountActivationIntroduction {
    struct Destination: Equatable {
        let title: String
        let summary: String
        let systemImage: String
    }

    struct Presentation: Equatable {
        let destinations: [Destination]
        let registrationReason: String
    }

    static let presentation = Presentation(
        destinations: [
            Destination(
                title: "Friends",
                summary: "Meet people, join conversations, and bring useful social context back to you.",
                systemImage: "person.2.fill"
            ),
            Destination(
                title: "Career",
                summary: "Discover collaborators, roles, and opportunities that fit what you are building.",
                systemImage: "briefcase.fill"
            ),
        ],
        registrationReason: "Your email verifies that the account belongs to you, keeps Friends and Career connected, and lets you recover or revoke devices. It is never public."
    )
}

enum NetworkingAccountActivationPresentation {
    static func normalizedOTP(_ value: String) -> String {
        String(value.filter(\.isNumber).prefix(6))
    }

    static func isValidOTP(_ value: String) -> Bool {
        value.count == 6 && value.allSatisfy(\.isNumber)
    }

    static func deviceID(existing: String?, generated: @autoclosure () -> String) -> String {
        if let existing, existing.isEmpty == false { return existing }
        return generated()
    }

    static func isCurrentDevice(_ deviceID: String, currentDeviceID: String?) -> Bool {
        guard let currentDeviceID, currentDeviceID.isEmpty == false else { return false }
        return deviceID == currentDeviceID
    }

    static func deviceCapacityMessage(
        activeCount: Int,
        isReliable: Bool,
        isReauthorizingExistingDevice: Bool = false
    ) -> String {
        guard isReliable else {
            return "Device usage is temporarily unavailable. Retry before authorizing this Mac."
        }
        if isReauthorizingExistingDevice, activeCount >= 3 {
            return "This Mac is already authorized and can reconnect. All 3 device slots are in use."
        }
        return "\(activeCount) of 3 device slots currently used."
    }

    static func canAuthorizeDevice(
        activeCount: Int,
        isReliable: Bool,
        deviceName: String,
        isReauthorizingExistingDevice: Bool = false
    ) -> Bool {
        isReliable
            && (activeCount < 3 || isReauthorizingExistingDevice)
            && deviceName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
    }

    static func safeErrorMessage(_ error: Error) -> String {
        switch error {
        case NetworkingPlatformClientError.invalidOrExpiredOTP,
             NetworkingPlatformClientError.emailOTPThrottled,
             NetworkingPlatformClientError.deviceLimitReached:
            return error.localizedDescription
        case NetworkingPlatformClientError.invalidResponse:
            return "The Networking service returned an unreadable response. Please try again."
        case is NetworkingPlatformClientError:
            return "The Networking service could not complete that request. Please try again."
        case is NetworkingActivationRunnerError:
            return "Networking setup could not finish. Your verified account is safe; please try again."
        default:
            return "Something went wrong while connecting Networking. Please try again."
        }
    }
}

struct NetworkingActivationState: Codable, Equatable, Sendable {
    let isEnabled: Bool
    let personID: String
    let agentTokenPlaintext: String
    let supabaseURL: URL
    let publishableKey: String
    var mode: NetworkingActivationMode = .localSandbox
    var userID: String?
    var refreshToken: String?
    var authEmail: String?
    /// Decoded only for legacy migration. New activation never writes or uses it.
    var authPassword: String?
    var deviceID: String?
    var deviceDisplayName: String?
    var deviceToken: String?
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
        deviceID: String? = nil,
        deviceDisplayName: String? = nil,
        deviceToken: String? = nil,
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
        self.deviceID = deviceID
        self.deviceDisplayName = deviceDisplayName
        self.deviceToken = deviceToken
        self.profileIDMapping = profileIDMapping
    }

    var isPlatformConnected: Bool {
        mode == .platform
    }

    var isReadyForPlatformHandoff: Bool {
        isEnabled &&
            isPlatformConnected &&
            authEmail?.isEmpty == false &&
            refreshToken?.isEmpty == false &&
            deviceID?.isEmpty == false &&
            deviceToken?.isEmpty == false &&
            agentTokenPlaintext.isEmpty == false
    }

    var containsLegacyPlaintextSecrets: Bool {
        agentTokenPlaintext.isEmpty == false ||
            refreshToken?.isEmpty == false ||
            deviceToken?.isEmpty == false ||
            authPassword?.isEmpty == false
    }

    func removingSecretsForReauthentication() -> NetworkingActivationState {
        NetworkingActivationState(
            isEnabled: isEnabled, personID: personID, agentTokenPlaintext: "",
            supabaseURL: supabaseURL, publishableKey: publishableKey,
            authEmail: authEmail, authPassword: nil, mode: mode, userID: userID,
            refreshToken: nil, deviceID: deviceID, deviceDisplayName: deviceDisplayName,
            deviceToken: nil, profileIDMapping: profileIDMapping
        )
    }

    func refreshed(with session: NetworkingPlatformSession) -> NetworkingActivationState {
        NetworkingActivationState(
            isEnabled: isEnabled,
            personID: personID,
            agentTokenPlaintext: agentTokenPlaintext,
            supabaseURL: supabaseURL,
            publishableKey: publishableKey,
            authEmail: authEmail,
            mode: mode,
            userID: session.userID,
            refreshToken: session.refreshToken,
            deviceID: deviceID,
            deviceDisplayName: deviceDisplayName,
            deviceToken: deviceToken,
            profileIDMapping: profileIDMapping
        )
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
        case deviceID
        case deviceDisplayName
        case deviceToken
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
        deviceID = try container.decodeIfPresent(String.self, forKey: .deviceID)
        deviceDisplayName = try container.decodeIfPresent(String.self, forKey: .deviceDisplayName)
        deviceToken = try container.decodeIfPresent(String.self, forKey: .deviceToken)
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

enum NetworkingActivationStateStoreError: LocalizedError, Equatable {
    case secureStorageTimedOut
    case legacyCredentialsRequireReauthentication

    var errorDescription: String? {
        switch self {
        case .secureStorageTimedOut:
            "Secure Networking credentials took too long to unlock."
        case .legacyCredentialsRequireReauthentication:
            "Legacy Networking credentials must be replaced by email verification."
        }
    }
}

private final class NetworkingActivationLoadGate: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<Result<NetworkingActivationState?, Error>, Never>?

    init(_ continuation: CheckedContinuation<Result<NetworkingActivationState?, Error>, Never>) {
        self.continuation = continuation
    }

    func finish(_ result: Result<NetworkingActivationState?, Error>) {
        lock.lock()
        let pending = continuation
        continuation = nil
        lock.unlock()
        pending?.resume(returning: result)
    }
}

struct NetworkingActivationStateStore: @unchecked Sendable {
    let fileManager: FileManager
    let keychain: KeychainStoring
    let keychainService: String

    init(
        fileManager: FileManager = .default,
        keychain: KeychainStoring = KeychainHelper.shared,
        keychainService: String = KeychainHelper.service
    ) {
        self.fileManager = fileManager
        self.keychain = keychain
        self.keychainService = keychainService
    }

    func load(projectRoot: URL) throws -> NetworkingActivationState? {
        guard let persisted = try persistedState(projectRoot: projectRoot) else { return nil }
        guard persisted.containsLegacyPlaintextSecrets == false else {
            throw NetworkingActivationStateStoreError.legacyCredentialsRequireReauthentication
        }
        let keys = secretKeys(projectRoot: projectRoot)
        return hydrated(persisted, keys: keys)
    }

    func load(projectRoot: URL, timeout: TimeInterval) async throws -> NetworkingActivationState? {
        let result = await withCheckedContinuation { continuation in
            let gate = NetworkingActivationLoadGate(continuation)
            DispatchQueue.global(qos: .userInitiated).async {
                gate.finish(Result { try load(projectRoot: projectRoot) })
            }
            DispatchQueue.global(qos: .userInitiated).asyncAfter(deadline: .now() + timeout) {
                gate.finish(.failure(NetworkingActivationStateStoreError.secureStorageTimedOut))
            }
        }
        return try result.get()
    }

    func persistedState(projectRoot: URL) throws -> NetworkingActivationState? {
        let url = stateURL(projectRoot: projectRoot)
        guard fileManager.fileExists(atPath: url.path) else { return nil }
        let data = try Data(contentsOf: url)
        return try JSONDecoder().decode(NetworkingActivationState.self, from: data)
    }

    func discardLegacySecretsForReauthentication(projectRoot: URL) throws -> NetworkingActivationState? {
        guard let persisted = try persistedState(projectRoot: projectRoot) else { return nil }
        guard persisted.containsLegacyPlaintextSecrets else { return persisted }
        return try clearSecretsForReauthentication(projectRoot: projectRoot)
    }

    @discardableResult
    func clearSecretsForReauthentication(projectRoot: URL) throws -> NetworkingActivationState? {
        let persisted = try persistedState(projectRoot: projectRoot)
        let sanitized = persisted?.removingSecretsForReauthentication()
        let keys = secretKeys(projectRoot: projectRoot)
        keychain.delete(forKey: keys.agentToken, service: keychainService)
        keychain.delete(forKey: keys.refreshToken, service: keychainService)
        keychain.delete(forKey: keys.authPassword, service: keychainService)
        keychain.delete(forKey: keys.deviceToken, service: keychainService)
        if let sanitized {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            try encoder.encode(sanitized).write(to: stateURL(projectRoot: projectRoot), options: .atomic)
        }
        return sanitized
    }

    func save(_ state: NetworkingActivationState, projectRoot: URL) throws {
        let url = stateURL(projectRoot: projectRoot)
        try fileManager.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let keys = secretKeys(projectRoot: projectRoot)
        try persistSecret(state.agentTokenPlaintext, key: keys.agentToken)
        try persistSecret(state.refreshToken, key: keys.refreshToken)
        try persistSecret(state.deviceToken, key: keys.deviceToken)
        keychain.delete(forKey: keys.authPassword, service: keychainService)
        let persisted = NetworkingActivationState(
            isEnabled: state.isEnabled, personID: state.personID, agentTokenPlaintext: "",
            supabaseURL: state.supabaseURL, publishableKey: state.publishableKey,
            authEmail: state.authEmail, authPassword: nil, mode: state.mode,
            userID: state.userID, refreshToken: nil,
            deviceID: state.deviceID, deviceDisplayName: state.deviceDisplayName,
            deviceToken: nil, profileIDMapping: state.profileIDMapping
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(persisted)
        try data.write(to: url, options: .atomic)
    }

    func stateURL(projectRoot: URL) -> URL {
        projectRoot.appending(path: ".knowyou/networking/activation.json")
    }

    private func secretKeys(projectRoot: URL) -> (agentToken: String, refreshToken: String, authPassword: String, deviceToken: String) {
        let prefix = "networking.\(NetworkingPlatformClient.tokenHash(projectRoot.standardizedFileURL.path))"
        return ("\(prefix).agent-token", "\(prefix).refresh-token", "\(prefix).auth-password", "\(prefix).device-token")
    }

    private func hydrated(_ state: NetworkingActivationState, keys: (agentToken: String, refreshToken: String, authPassword: String, deviceToken: String)) -> NetworkingActivationState {
        NetworkingActivationState(
            isEnabled: state.isEnabled, personID: state.personID,
            agentTokenPlaintext: keychain.load(forKey: keys.agentToken, service: keychainService) ?? state.agentTokenPlaintext,
            supabaseURL: state.supabaseURL, publishableKey: state.publishableKey,
            authEmail: state.authEmail,
            authPassword: nil,
            mode: state.mode, userID: state.userID,
            refreshToken: keychain.load(forKey: keys.refreshToken, service: keychainService) ?? state.refreshToken,
            deviceID: state.deviceID, deviceDisplayName: state.deviceDisplayName,
            deviceToken: keychain.load(forKey: keys.deviceToken, service: keychainService) ?? state.deviceToken,
            profileIDMapping: state.profileIDMapping
        )
    }

    private func persistSecret(_ value: String?, key: String) throws {
        guard let value, value.isEmpty == false else {
            keychain.delete(forKey: key, service: keychainService)
            return
        }
        keychain.save(value, forKey: key, service: keychainService)
        guard keychain.load(forKey: key, service: keychainService) == value else {
            throw CocoaError(.fileWriteUnknown, userInfo: [
                NSLocalizedDescriptionKey: "Networking could not securely save credentials in Keychain."
            ])
        }
    }
}

struct NetworkingPendingDeviceAuthorization: Codable, Equatable, Sendable {
    let deviceID: String
    let deviceDisplayName: String
}

struct NetworkingPendingDeviceAuthorizationStore {
    let fileManager: FileManager

    init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
    }

    func load(projectRoot: URL) throws -> NetworkingPendingDeviceAuthorization? {
        let url = stateURL(projectRoot: projectRoot)
        guard fileManager.fileExists(atPath: url.path) else { return nil }
        return try JSONDecoder().decode(
            NetworkingPendingDeviceAuthorization.self,
            from: Data(contentsOf: url)
        )
    }

    func save(_ state: NetworkingPendingDeviceAuthorization, projectRoot: URL) throws {
        let url = stateURL(projectRoot: projectRoot)
        try fileManager.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try JSONEncoder().encode(state).write(to: url, options: .atomic)
    }

    func clear(projectRoot: URL) throws {
        let url = stateURL(projectRoot: projectRoot)
        guard fileManager.fileExists(atPath: url.path) else { return }
        try fileManager.removeItem(at: url)
    }

    func stateURL(projectRoot: URL) -> URL {
        projectRoot.appending(path: ".knowyou/networking/pending-device.json")
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
