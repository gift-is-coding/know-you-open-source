import Foundation

struct KnowledgeImportConfig: Codable, Equatable, Sendable {
    var isImportEnabled = false
    var dailyImportHour = 7
    var dailyImportMinute = 30
    var connectorInstances: [KnowledgeConnectorInstanceConfig] = []

    static let `default` = KnowledgeImportConfig()
    private static let storageKey = "knowledgeImportConfig"

    func save(to defaults: UserDefaults = .standard) {
        if let data = try? JSONEncoder().encode(importOnly()) {
            defaults.set(data, forKey: Self.storageKey)
        }
    }

    static func load(from defaults: UserDefaults = .standard) -> KnowledgeImportConfig {
        guard
            let data = defaults.data(forKey: storageKey),
            let decoded = try? JSONDecoder().decode(KnowledgeImportConfig.self, from: data)
        else {
            return .default
        }
        return decoded.importOnly()
    }

    private func importOnly() -> KnowledgeImportConfig {
        var config = self
        config.connectorInstances = connectorInstances.filter { $0.connectorID.isImport }
        return config
    }
}

struct KnowledgeImportCredentialStore: Sendable {
    let keychain: KeychainStoring
    let service: String

    init(keychain: KeychainStoring = KeychainHelper.shared, service: String = KeychainHelper.service) {
        self.keychain = keychain
        self.service = service
    }

    func saveBearerToken(_ token: String, connectorInstanceID: String) {
        let trimmedToken = token.trimmingCharacters(in: .whitespacesAndNewlines)
        let key = "knowledge-import.\(connectorInstanceID).bearer-token"
        if trimmedToken.isEmpty {
            keychain.delete(forKey: key, service: service)
        } else {
            keychain.save(trimmedToken, forKey: key, service: service)
        }
    }

    func bearerToken(connectorInstanceID: String) -> String? {
        let key = "knowledge-import.\(connectorInstanceID).bearer-token"
        guard let token = keychain.load(forKey: key, service: service) else { return nil }
        let trimmedToken = token.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmedToken.isEmpty {
            keychain.delete(forKey: key, service: service)
            return nil
        }
        return trimmedToken
    }

    func deleteBearerToken(connectorInstanceID: String) {
        keychain.delete(forKey: "knowledge-import.\(connectorInstanceID).bearer-token", service: service)
    }
}
