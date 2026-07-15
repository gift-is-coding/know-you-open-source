import LocalAuthentication
import Security
import XCTest
@testable import KnowYou

final class CodexAuthStoreTests: XCTestCase {
    private var temporaryDirectoryURL: URL!
    private var keychain: InMemoryCodexKeychain!

    override func setUpWithError() throws {
        try super.setUpWithError()
        temporaryDirectoryURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: temporaryDirectoryURL, withIntermediateDirectories: true)
        keychain = InMemoryCodexKeychain()
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: temporaryDirectoryURL)
        try super.tearDownWithError()
    }

    func testKeychainReadUsesNonInteractiveAuthenticationContext() throws {
        let query = KeychainHelper.loadQuery(forKey: "networking", service: "dev.knowyou.test")

        let context = try XCTUnwrap(query[kSecUseAuthenticationContext] as? LAContext)
        XCTAssertTrue(context.interactionNotAllowed)
        XCTAssertNil(query[kSecUseAuthenticationUI])
    }

    func testKeychainDeleteUsesNonInteractiveAuthenticationContext() throws {
        let query = KeychainHelper.deleteQuery(forKey: "networking", service: "dev.knowyou.test")

        let context = try XCTUnwrap(query[kSecUseAuthenticationContext] as? LAContext)
        XCTAssertTrue(context.interactionNotAllowed)
        XCTAssertNil(query[kSecUseAuthenticationUI])
    }

    func testComputesKeychainAccountFromCodexHome() {
        let account = CodexAuthStore.keychainAccount(forCodexHomePath: "/Users/test/.codex")

        XCTAssertEqual(account, "cli|d446e73b91d0fe9e")
    }

    func testReadsKeychainBeforeAuthFile() throws {
        let codexHome = try makeCodexHome()
        let authFileURL = codexHome.appendingPathComponent("auth.json")
        try authRecordJSON(accessToken: token(accountID: "file-account"), refreshToken: "file-refresh")
            .write(to: authFileURL, atomically: true, encoding: .utf8)
        let account = CodexAuthStore.keychainAccount(forCodexHomePath: codexHome.path)
        keychain.save(
            authRecordJSON(accessToken: token(accountID: "keychain-account"), refreshToken: "keychain-refresh"),
            forKey: account,
            service: CodexAuthStore.keychainService
        )
        let store = CodexAuthStore(
            keychain: keychain,
            environment: ["CODEX_HOME": codexHome.path],
            now: { Date(timeIntervalSince1970: 1_700_000_000) }
        )

        let credential = try store.readCredential()

        XCTAssertEqual(credential.accountID, "keychain-account")
        XCTAssertEqual(credential.refreshToken, "keychain-refresh")
        XCTAssertEqual(credential.source, .keychain(account: account, codexHomePath: codexHome.path))
    }

    func testFallsBackToAuthFileWhenKeychainIsMissing() throws {
        let codexHome = try makeCodexHome()
        try authRecordJSON(accessToken: token(accountID: "file-account"), refreshToken: "file-refresh")
            .write(to: codexHome.appendingPathComponent("auth.json"), atomically: true, encoding: .utf8)
        let store = CodexAuthStore(
            keychain: keychain,
            environment: ["CODEX_HOME": codexHome.path],
            now: { Date(timeIntervalSince1970: 1_700_000_000) }
        )

        let credential = try store.readCredential()

        XCTAssertEqual(credential.accountID, "file-account")
        XCTAssertEqual(credential.refreshToken, "file-refresh")
        XCTAssertEqual(credential.source, .authFile(path: codexHome.appendingPathComponent("auth.json").path))
    }

    func testRejectsIncompleteAuthRecord() throws {
        let codexHome = try makeCodexHome()
        try #"{"auth_mode":"chatgpt","tokens":{"access_token":"only-access"}}"#
            .write(to: codexHome.appendingPathComponent("auth.json"), atomically: true, encoding: .utf8)
        let store = CodexAuthStore(keychain: keychain, environment: ["CODEX_HOME": codexHome.path])

        XCTAssertThrowsError(try store.readCredential()) { error in
            XCTAssertEqual(error as? CodexAuthStoreError, .credentialNotFound)
        }
    }

    func testBuildsUpdatedAuthRecordAndPreservesUnrelatedFields() throws {
        let existing = Data("""
        {
          "auth_mode": "chatgpt",
          "tokens": {
            "access_token": "old-access",
            "refresh_token": "old-refresh",
            "extra": "preserve-me"
          },
          "custom": "still-here"
        }
        """.utf8)
        let refreshed = CodexOAuthCredential(
            accessToken: "new-access",
            refreshToken: "new-refresh",
            expiresAt: Date(timeIntervalSince1970: 2_000_000_000),
            accountID: "new-account",
            source: .authFile(path: "/tmp/auth.json")
        )

        let updated = try CodexAuthStore.updatedAuthRecordJSON(
            existingJSONData: existing,
            credential: refreshed,
            refreshedAt: Date(timeIntervalSince1970: 1_800_000_000)
        )
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: updated) as? [String: Any])
        let tokens = try XCTUnwrap(object["tokens"] as? [String: Any])

        XCTAssertEqual(object["custom"] as? String, "still-here")
        XCTAssertEqual(tokens["extra"] as? String, "preserve-me")
        XCTAssertEqual(tokens["access_token"] as? String, "new-access")
        XCTAssertEqual(tokens["refresh_token"] as? String, "new-refresh")
        XCTAssertEqual(tokens["account_id"] as? String, "new-account")
        XCTAssertEqual(object["last_refresh"] as? String, "2027-01-15T08:00:00Z")
    }

    private func makeCodexHome() throws -> URL {
        let codexHome = temporaryDirectoryURL.appendingPathComponent(".codex", isDirectory: true)
        try FileManager.default.createDirectory(at: codexHome, withIntermediateDirectories: true)
        return codexHome
    }

    private func authRecordJSON(accessToken: String, refreshToken: String) -> String {
        """
        {
          "auth_mode": "chatgpt",
          "tokens": {
            "access_token": "\(accessToken)",
            "refresh_token": "\(refreshToken)"
          },
          "last_refresh": "2024-01-01T00:00:00Z"
        }
        """
    }

    private func token(accountID: String) -> String {
        makeJWT(payload: [
            "exp": 2_000_000_000,
            "https://api.openai.com/auth": [
                "chatgpt_account_id": accountID
            ]
        ])
    }
}

private final class InMemoryCodexKeychain: KeychainStoring, @unchecked Sendable {
    private var values: [String: String] = [:]

    func save(_ value: String, forKey key: String, service: String) {
        values["\(service):\(key)"] = value
    }

    func load(forKey key: String, service: String) -> String? {
        values["\(service):\(key)"]
    }

    func delete(forKey key: String, service: String) {
        values.removeValue(forKey: "\(service):\(key)")
    }
}
