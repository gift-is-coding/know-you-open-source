import Foundation

struct GoogleDriveKnowledgeConnector: KnowledgeImportConnector {
    let connectorInstanceID: String
    let connectorID: KnowledgeConnectorID = .googleDriveImport

    private let bearerToken: String
    private let client: KnowledgeHTTPClient

    init(
        connectorInstanceID: String,
        bearerToken: String,
        client: KnowledgeHTTPClient = KnowledgeHTTPClient()
    ) {
        self.connectorInstanceID = connectorInstanceID
        self.bearerToken = bearerToken
        self.client = client
    }

    func fetchSnapshots() async throws -> [KnowledgeImportSnapshot] {
        let files = try await listFiles()
        var snapshots: [KnowledgeImportSnapshot] = []
        for file in files {
            guard let downloadPlan = downloadPlan(for: file) else {
                continue
            }

            let request = KnowledgeHTTPClient.bearerRequest(url: downloadPlan.url, token: bearerToken)
            let data = try await client.data(for: request)
            guard let contentMarkdown = String(data: data, encoding: .utf8) else {
                throw KnowledgeImportConnectorError.invalidResponse("Google Drive file \(file.id) was not UTF-8.")
            }

            snapshots.append(
                KnowledgeImportSnapshot(
                    connectorInstanceID: connectorInstanceID,
                    connectorID: connectorID,
                    remoteID: file.id,
                    title: file.name,
                    sourcePath: nil,
                    remoteURL: file.webViewLink,
                    mimeType: downloadPlan.mimeType,
                    contentMarkdown: contentMarkdown,
                    remoteUpdatedAt: Self.parseDate(file.modifiedTime),
                    originKind: "google-drive-file"
                )
            )
        }
        return snapshots
    }

    private func listFiles() async throws -> [GoogleDriveFile] {
        var files: [GoogleDriveFile] = []
        var pageToken: String?
        repeat {
            guard let url = listURL(pageToken: pageToken) else {
                throw KnowledgeImportConnectorError.invalidResponse("Cannot build Google Drive files URL.")
            }

            let request = KnowledgeHTTPClient.bearerRequest(url: url, token: bearerToken)
            let data = try await client.data(for: request)
            let response = try JSONDecoder().decode(GoogleDriveFilesResponse.self, from: data)
            files.append(contentsOf: response.files)
            pageToken = response.nextPageToken
        } while pageToken != nil

        return files
    }

    private func listURL(pageToken: String?) -> URL? {
        var components = URLComponents()
        components.scheme = "https"
        components.host = "www.googleapis.com"
        components.path = "/drive/v3/files"
        var queryItems = [
            URLQueryItem(name: "q", value: "trashed=false"),
            URLQueryItem(name: "fields", value: "files(id,name,mimeType,modifiedTime,webViewLink),nextPageToken"),
            URLQueryItem(name: "pageSize", value: "100")
        ]
        if let pageToken {
            queryItems.append(URLQueryItem(name: "pageToken", value: pageToken))
        }
        components.queryItems = queryItems
        return components.url
    }

    private func downloadPlan(for file: GoogleDriveFile) -> GoogleDriveDownloadPlan? {
        switch file.mimeType {
        case "application/vnd.google-apps.document":
            return exportPlan(for: file.id)
        case "text/markdown", "text/plain":
            return mediaPlan(for: file)
        default:
            return nil
        }
    }

    private func exportPlan(for fileID: String) -> GoogleDriveDownloadPlan? {
        var components = URLComponents()
        components.scheme = "https"
        components.host = "www.googleapis.com"
        components.path = "/drive/v3/files/\(fileID)/export"
        components.queryItems = [URLQueryItem(name: "mimeType", value: "text/markdown")]
        guard let url = components.url else {
            return nil
        }
        return GoogleDriveDownloadPlan(url: url, mimeType: "text/markdown")
    }

    private func mediaPlan(for file: GoogleDriveFile) -> GoogleDriveDownloadPlan? {
        var components = URLComponents()
        components.scheme = "https"
        components.host = "www.googleapis.com"
        components.path = "/drive/v3/files/\(file.id)"
        components.queryItems = [URLQueryItem(name: "alt", value: "media")]
        guard let url = components.url else {
            return nil
        }
        return GoogleDriveDownloadPlan(url: url, mimeType: file.mimeType)
    }

    private static func parseDate(_ string: String?) -> Date? {
        guard let string else {
            return nil
        }

        let fractionalFormatter = ISO8601DateFormatter()
        fractionalFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = fractionalFormatter.date(from: string) {
            return date
        }

        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: string)
    }
}

private struct GoogleDriveFilesResponse: Decodable {
    var files: [GoogleDriveFile]
    var nextPageToken: String?
}

private struct GoogleDriveFile: Decodable {
    var id: String
    var name: String
    var mimeType: String
    var modifiedTime: String?
    var webViewLink: String?
}

private struct GoogleDriveDownloadPlan {
    var url: URL
    var mimeType: String
}
