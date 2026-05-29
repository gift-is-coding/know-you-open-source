import Foundation
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

    private struct SystemKeychainStore: KeychainStoring {
        func save(_ value: String, forKey key: String, service: String) {
            let data = Data(value.utf8)
            let query: [CFString: Any] = [
                kSecClass: kSecClassGenericPassword,
                kSecAttrService: service,
                kSecAttrAccount: key,
            ]
            SecItemDelete(query as CFDictionary)
            let attributes = query.merging([kSecValueData: data]) { _, new in new }
            SecItemAdd(attributes as CFDictionary, nil)
        }

        func load(forKey key: String, service: String) -> String? {
            let query: [CFString: Any] = [
                kSecClass: kSecClassGenericPassword,
                kSecAttrService: service,
                kSecAttrAccount: key,
                kSecReturnData: true,
                kSecMatchLimit: kSecMatchLimitOne,
            ]
            var result: AnyObject?
            let status = SecItemCopyMatching(query as CFDictionary, &result)
            guard status == errSecSuccess, let data = result as? Data else { return nil }
            return String(decoding: data, as: UTF8.self)
        }

        func delete(forKey key: String, service: String) {
            let query: [CFString: Any] = [
                kSecClass: kSecClassGenericPassword,
                kSecAttrService: service,
                kSecAttrAccount: key,
            ]
            SecItemDelete(query as CFDictionary)
        }
    }
}
