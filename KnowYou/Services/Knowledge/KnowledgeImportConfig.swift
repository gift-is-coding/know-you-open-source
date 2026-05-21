import Foundation

struct KnowledgeImportConfig: Codable, Equatable, Sendable {
    var isImportEnabled = false
    var dailyImportHour = 7
    var dailyImportMinute = 30
    var connectorInstances: [KnowledgeConnectorInstanceConfig] = []

    static let `default` = KnowledgeImportConfig()
    private static let storageKey = "knowledgeImportConfig"

    func save(to defaults: UserDefaults = .standard) {
        if let data = try? JSONEncoder().encode(self) {
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
        return decoded
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
        keychain.save(token, forKey: "knowledge-import.\(connectorInstanceID).bearer-token", service: service)
    }

    func bearerToken(connectorInstanceID: String) -> String? {
        keychain.load(forKey: "knowledge-import.\(connectorInstanceID).bearer-token", service: service)
    }

    func deleteBearerToken(connectorInstanceID: String) {
        keychain.delete(forKey: "knowledge-import.\(connectorInstanceID).bearer-token", service: service)
    }
}
