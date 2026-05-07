import Foundation

enum CodexCredentialSource: Equatable, Sendable {
    case keychain(account: String, codexHomePath: String)
    case authFile(path: String)
}

struct CodexOAuthCredential: Equatable, Sendable {
    let accessToken: String
    let refreshToken: String
    let expiresAt: Date
    let accountID: String
    let source: CodexCredentialSource
}

enum CodexAuthStoreError: Error, LocalizedError, Equatable {
    case credentialNotFound
    case writeFailed

    var errorDescription: String? {
        switch self {
        case .credentialNotFound:
            return "Codex login state was not found. Sign in with Codex CLI, then retest Codex Auth."
        case .writeFailed:
            return "Codex credentials could not be updated."
        }
    }
}

struct CodexAuthStore: @unchecked Sendable {
    static let keychainService = "Codex Auth"

    private let keychain: KeychainStoring
    private let fileManager: FileManager
    private let environment: [String: String]
    private let now: @Sendable () -> Date

    init(
        keychain: KeychainStoring = KeychainHelper.shared,
        fileManager: FileManager = .default,
        environment: [String: String] = ProcessInfo.processInfo.environment,
        now: @escaping @Sendable () -> Date = Date.init
    ) {
        self.keychain = keychain
        self.fileManager = fileManager
        self.environment = environment
        self.now = now
    }

    static func keychainAccount(forCodexHomePath codexHomePath: String) -> String {
        "cli|\(SHA256Hasher.hash(codexHomePath).prefix(16))"
    }

    func readCredential() throws -> CodexOAuthCredential {
        let codexHomeURL = resolvedCodexHomeURL()
        let codexHomePath = codexHomeURL.path
        let account = Self.keychainAccount(forCodexHomePath: codexHomePath)

        if let secret = keychain.load(forKey: account, service: Self.keychainService),
           let credential = credential(
                from: Data(secret.utf8),
                source: .keychain(account: account, codexHomePath: codexHomePath),
                fallbackExpiry: fallbackExpiry(fromAuthRecordData: Data(secret.utf8), authFileURL: nil)
           ) {
            return credential
        }

        let authFileURL = codexHomeURL.appendingPathComponent("auth.json")
        guard
            let data = try? Data(contentsOf: authFileURL),
            let credential = credential(
                from: data,
                source: .authFile(path: authFileURL.path),
                fallbackExpiry: fallbackExpiry(fromAuthRecordData: data, authFileURL: authFileURL)
            )
        else {
            throw CodexAuthStoreError.credentialNotFound
        }

        return credential
    }

    func writeCredential(_ credential: CodexOAuthCredential, refreshedAt: Date = Date()) throws {
        switch credential.source {
        case .keychain(let account, _):
            guard let existing = keychain.load(forKey: account, service: Self.keychainService) else {
                throw CodexAuthStoreError.writeFailed
            }
            let updated = try Self.updatedAuthRecordJSON(
                existingJSONData: Data(existing.utf8),
                credential: credential,
                refreshedAt: refreshedAt
            )
            keychain.save(String(decoding: updated, as: UTF8.self), forKey: account, service: Self.keychainService)
        case .authFile(let path):
            let url = URL(fileURLWithPath: path)
            let existing = try Data(contentsOf: url)
            let updated = try Self.updatedAuthRecordJSON(
                existingJSONData: existing,
                credential: credential,
                refreshedAt: refreshedAt
            )
            try updated.write(to: url, options: .atomic)
        }
    }

    static func updatedAuthRecordJSON(
        existingJSONData: Data,
        credential: CodexOAuthCredential,
        refreshedAt: Date
    ) throws -> Data {
        var record = (try JSONSerialization.jsonObject(with: existingJSONData)) as? [String: Any] ?? [:]
        var tokens = record["tokens"] as? [String: Any] ?? [:]
        tokens["access_token"] = credential.accessToken
        tokens["refresh_token"] = credential.refreshToken
        tokens["account_id"] = credential.accountID
        record["tokens"] = tokens
        record["auth_mode"] = record["auth_mode"] ?? "chatgpt"
        record["last_refresh"] = Self.codexISO8601String(from: refreshedAt)
        return try JSONSerialization.data(withJSONObject: record, options: [.sortedKeys])
    }

    private func resolvedCodexHomeURL() -> URL {
        let configured = environment["CODEX_HOME"]?.trimmingCharacters(in: .whitespacesAndNewlines)
        let rawPath = configured?.isEmpty == false ? configured! : "~/.codex"
        let expanded = (rawPath as NSString).expandingTildeInPath
        let url = URL(fileURLWithPath: expanded)
        if fileManager.fileExists(atPath: url.path) {
            return url.resolvingSymlinksInPath()
        }
        return url.standardizedFileURL
    }

    private func credential(
        from data: Data,
        source: CodexCredentialSource,
        fallbackExpiry: Date
    ) -> CodexOAuthCredential? {
        guard
            let record = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
            authModeIsCompatible(record["auth_mode"]),
            let tokens = record["tokens"] as? [String: Any],
            let accessToken = nonEmptyString(tokens["access_token"]),
            let refreshToken = nonEmptyString(tokens["refresh_token"])
        else {
            return nil
        }

        let accountID = nonEmptyString(tokens["account_id"]) ?? CodexJWT.accountID(from: accessToken)
        guard let accountID else {
            return nil
        }

        return CodexOAuthCredential(
            accessToken: accessToken,
            refreshToken: refreshToken,
            expiresAt: CodexJWT.expiryDate(from: accessToken) ?? fallbackExpiry,
            accountID: accountID,
            source: source
        )
    }

    private func fallbackExpiry(fromAuthRecordData data: Data, authFileURL: URL?) -> Date {
        if
            let record = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
            let lastRefresh = parseLastRefresh(record["last_refresh"])
        {
            return lastRefresh.addingTimeInterval(3600)
        }

        if
            let authFileURL,
            let attributes = try? fileManager.attributesOfItem(atPath: authFileURL.path),
            let modificationDate = attributes[.modificationDate] as? Date
        {
            return modificationDate.addingTimeInterval(3600)
        }

        return now().addingTimeInterval(3600)
    }

    private func parseLastRefresh(_ value: Any?) -> Date? {
        if let string = value as? String {
            return Self.codexISO8601Date(from: string)
        }
        if let number = value as? TimeInterval {
            return Date(timeIntervalSince1970: number)
        }
        return nil
    }

    private func authModeIsCompatible(_ value: Any?) -> Bool {
        guard let value else {
            return true
        }
        return (value as? String) == "chatgpt"
    }

    private func nonEmptyString(_ value: Any?) -> String? {
        guard let string = value as? String else {
            return nil
        }
        let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private static func codexISO8601String(from date: Date) -> String {
        codexISO8601Formatter().string(from: date)
    }

    private static func codexISO8601Date(from string: String) -> Date? {
        codexISO8601Formatter().date(from: string)
    }

    private static func codexISO8601Formatter() -> ISO8601DateFormatter {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        return formatter
    }
}
