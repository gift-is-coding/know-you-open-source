import Foundation
import AppKit

protocol UpdateServing: Sendable {
    func fetchOffer() async throws -> UpdateOffer?
}

struct NoopUpdateService: UpdateServing {
    func fetchOffer() async throws -> UpdateOffer? {
        nil
    }
}

protocol DirectAppUpdating: Sendable {
    func startUpdate(for offer: UpdateOffer) async throws
}

enum DirectAppUpdateError: LocalizedError {
    case notConfigured
    case missingDownloadURL

    var errorDescription: String? {
        switch self {
        case .notConfigured:
            return "In-app updates are not configured for this build yet."
        case .missingDownloadURL:
            return "The direct-download URL is missing for this update."
        }
    }
}

struct NoopDirectAppUpdater: DirectAppUpdating {
    func startUpdate(for offer: UpdateOffer) async throws {
        throw DirectAppUpdateError.notConfigured
    }
}

@MainActor
struct ExternalLinkDirectAppUpdater: DirectAppUpdating {
    let opener: @MainActor @Sendable (URL) -> Void

    func startUpdate(for offer: UpdateOffer) async throws {
        guard let downloadURL = offer.downloadURL else {
            throw DirectAppUpdateError.missingDownloadURL
        }
        opener(downloadURL)
    }
}

@MainActor
func defaultExternalURLOpener(_ url: URL) {
    NSWorkspace.shared.open(url)
}

private struct RemoteUpdatePayload: Decodable {
    var version: String
    var summary: String?
    var publishedAt: Date?
    var appStoreURL: URL?
    var downloadURL: URL?
}

struct UpdateService: UpdateServing {
    var session: URLSession
    var resolver: UpdateChannelResolver
    var metadataURL: URL
    var currentVersion: String

    func fetchOffer() async throws -> UpdateOffer? {
        let (data, _) = try await session.data(from: metadataURL)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let payload = try decoder.decode(RemoteUpdatePayload.self, from: data)

        guard AppVersion(payload.version) > AppVersion(currentVersion) else {
            return nil
        }

        let actionKind: UpdateActionKind
        switch resolver.resolve() {
        case .direct:
            actionKind = .installInApp
        case .appStore:
            actionKind = .openAppStore
        case .unknown:
            actionKind = .unavailable
        }

        return UpdateOffer(
            availableVersion: payload.version,
            releaseSummary: payload.summary,
            publishedAt: payload.publishedAt,
            actionKind: actionKind,
            storeURL: payload.appStoreURL,
            downloadURL: payload.downloadURL
        )
    }
}
