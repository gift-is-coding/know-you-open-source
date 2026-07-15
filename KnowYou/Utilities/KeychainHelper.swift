import Foundation
import LocalAuthentication
import Security

protocol KeychainStoring: Sendable {
    func save(_ value: String, forKey key: String, service: String)
    func load(forKey key: String, service: String) -> String?
    func delete(forKey key: String, service: String)
}

enum KeychainHelper {
    static var service: String {
        AppRuntimeProfile.current.keychainService
    }

    static let shared: KeychainStoring = SystemKeychainStore()

    static func loadQuery(forKey key: String, service: String) -> [CFString: Any] {
        [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: key,
            kSecReturnData: true,
            kSecMatchLimit: kSecMatchLimitOne,
            kSecUseAuthenticationContext: nonInteractiveAuthenticationContext(),
        ]
    }

    static func deleteQuery(forKey key: String, service: String) -> [CFString: Any] {
        [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: key,
            kSecUseAuthenticationContext: nonInteractiveAuthenticationContext(),
        ]
    }

    private static func nonInteractiveAuthenticationContext() -> LAContext {
        let context = LAContext()
        context.interactionNotAllowed = true
        return context
    }

    private struct SystemKeychainStore: KeychainStoring {
        func save(_ value: String, forKey key: String, service: String) {
            let data = Data(value.utf8)
            let query: [CFString: Any] = [
                kSecClass: kSecClassGenericPassword,
                kSecAttrService: service,
                kSecAttrAccount: key,
            ]
            SecItemDelete(KeychainHelper.deleteQuery(forKey: key, service: service) as CFDictionary)
            let attributes = query.merging([kSecValueData: data]) { _, new in new }
            SecItemAdd(attributes as CFDictionary, nil)
        }

        func load(forKey key: String, service: String) -> String? {
            let query = KeychainHelper.loadQuery(forKey: key, service: service)
            var result: AnyObject?
            let status = SecItemCopyMatching(query as CFDictionary, &result)
            guard status == errSecSuccess, let data = result as? Data else { return nil }
            return String(decoding: data, as: UTF8.self)
        }

        func delete(forKey key: String, service: String) {
            SecItemDelete(KeychainHelper.deleteQuery(forKey: key, service: service) as CFDictionary)
        }
    }
}
