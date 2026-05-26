import Foundation

struct NotionKnowledgeConnector: KnowledgeImportConnector {
    let connectorInstanceID: String
    let connectorID: KnowledgeConnectorID = .notionImport

    private let bearerToken: String
    private let client: KnowledgeHTTPClient
    private let notionVersion: String

    init(
        connectorInstanceID: String,
        bearerToken: String,
        client: KnowledgeHTTPClient = KnowledgeHTTPClient(),
        notionVersion: String = "2026-03-11"
    ) {
        self.connectorInstanceID = connectorInstanceID
        self.bearerToken = bearerToken
        self.client = client
        self.notionVersion = notionVersion
    }

    func fetchSnapshots() async throws -> [KnowledgeImportSnapshot] {
        let pages = try await searchPages()
        var snapshots: [KnowledgeImportSnapshot] = []
        for page in pages {
            let blocks = try await fetchChildren(parentID: page.id)
            snapshots.append(
                KnowledgeImportSnapshot(
                    connectorInstanceID: connectorInstanceID,
                    connectorID: connectorID,
                    remoteID: page.id,
                    title: page.title,
                    sourcePath: nil,
                    remoteURL: page.url,
                    mimeType: "text/markdown",
                    contentMarkdown: try await renderBlocks(blocks, depth: 0),
                    remoteUpdatedAt: Self.parseDate(page.lastEditedTime),
                    originKind: "notion-page"
                )
            )
        }
        return snapshots
    }

    private func searchPages() async throws -> [NotionPage] {
        var pages: [NotionPage] = []
        var cursor: String?
        repeat {
            var request = try notionRequest(url: Self.searchURL(), method: "POST")
            var body: [String: Any] = [
                "filter": [
                    "property": "object",
                    "value": "page"
                ],
                "page_size": 100
            ]
            if let cursor {
                body["start_cursor"] = cursor
            }
            request.httpBody = try JSONSerialization.data(withJSONObject: body)

            let data = try await client.data(for: request)
            let response = try JSONDecoder().decode(NotionListResponse<NotionPage>.self, from: data)
            pages.append(contentsOf: response.results)
            cursor = response.hasMore ? response.nextCursor : nil
        } while cursor != nil

        return pages
    }

    private func fetchChildren(parentID: String) async throws -> [NotionBlock] {
        var blocks: [NotionBlock] = []
        var cursor: String?
        repeat {
            var components = URLComponents()
            components.scheme = "https"
            components.host = "api.notion.com"
            components.path = "/v1/blocks/\(parentID)/children"
            var queryItems = [URLQueryItem(name: "page_size", value: "100")]
            if let cursor {
                queryItems.append(URLQueryItem(name: "start_cursor", value: cursor))
            }
            components.queryItems = queryItems
            guard let url = components.url else {
                throw KnowledgeImportConnectorError.invalidResponse("Cannot build Notion block children URL.")
            }

            let request = try notionRequest(url: url)
            let data = try await client.data(for: request)
            let response = try JSONDecoder().decode(NotionListResponse<NotionBlock>.self, from: data)
            blocks.append(contentsOf: response.results)
            cursor = response.hasMore ? response.nextCursor : nil
        } while cursor != nil

        return blocks
    }

    private func renderBlocks(_ blocks: [NotionBlock], depth: Int) async throws -> String {
        var renderedBlocks: [String] = []
        for block in blocks {
            if let renderedBlock = try await renderBlock(block, depth: depth), !renderedBlock.isEmpty {
                renderedBlocks.append(renderedBlock)
            }
        }
        return renderedBlocks.joined(separator: "\n\n")
    }

    private func renderBlock(_ block: NotionBlock, depth: Int) async throws -> String? {
        let ownMarkdown: String?
        switch block.type {
        case "heading_1":
            ownMarkdown = "# \(block.heading1?.plainText ?? "")"
        case "heading_2":
            ownMarkdown = "## \(block.heading2?.plainText ?? "")"
        case "heading_3":
            ownMarkdown = "### \(block.heading3?.plainText ?? "")"
        case "paragraph":
            ownMarkdown = block.paragraph?.plainText
        case "bulleted_list_item":
            ownMarkdown = "\(Self.indent(depth))- \(block.bulletedListItem?.plainText ?? "")"
        case "numbered_list_item":
            ownMarkdown = "\(Self.indent(depth))1. \(block.numberedListItem?.plainText ?? "")"
        case "to_do":
            let checked = block.toDo?.checked == true ? "x" : " "
            ownMarkdown = "\(Self.indent(depth))- [\(checked)] \(block.toDo?.plainText ?? "")"
        case "code":
            let language = block.code?.language ?? ""
            let text = block.code?.plainText ?? ""
            ownMarkdown = "```\(language)\n\(text)\n```"
        default:
            ownMarkdown = nil
        }

        let childMarkdown: String
        if block.hasChildren {
            childMarkdown = try await renderBlocks(try await fetchChildren(parentID: block.id), depth: depth + 1)
        } else {
            childMarkdown = ""
        }

        switch (ownMarkdown?.trimmingCharacters(in: .whitespacesAndNewlines), childMarkdown.isEmpty) {
        case let (.some(text), false) where !text.isEmpty:
            return "\(ownMarkdown ?? "")\n\n\(childMarkdown)"
        case let (.some(text), true) where !text.isEmpty:
            return ownMarkdown
        case (_, false):
            return childMarkdown
        default:
            return nil
        }
    }

    private func notionRequest(url: URL, method: String = "GET") throws -> URLRequest {
        var request = KnowledgeHTTPClient.bearerRequest(url: url, token: bearerToken, method: method)
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(notionVersion, forHTTPHeaderField: "Notion-Version")
        return request
    }

    private static func searchURL() -> URL {
        URL(string: "https://api.notion.com/v1/search")!
    }

    private static func indent(_ depth: Int) -> String {
        String(repeating: "  ", count: depth)
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

private struct NotionListResponse<Element: Decodable>: Decodable {
    var results: [Element]
    var nextCursor: String?
    var hasMore: Bool

    private enum CodingKeys: String, CodingKey {
        case results
        case nextCursor = "next_cursor"
        case hasMore = "has_more"
    }
}

private struct NotionPage: Decodable {
    var id: String
    var lastEditedTime: String?
    var url: String?
    var properties: [String: NotionPageProperty]

    var title: String {
        properties.values
            .compactMap(\.title)
            .flatMap { $0 }
            .map(\.plainText)
            .first { !$0.isEmpty } ?? id
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case lastEditedTime = "last_edited_time"
        case url
        case properties
    }
}

private struct NotionPageProperty: Decodable {
    var title: [NotionRichText]?
}

private struct NotionBlock: Decodable {
    var id: String
    var type: String
    var hasChildren: Bool
    var paragraph: NotionRichTextContainer?
    var heading1: NotionRichTextContainer?
    var heading2: NotionRichTextContainer?
    var heading3: NotionRichTextContainer?
    var bulletedListItem: NotionRichTextContainer?
    var numberedListItem: NotionRichTextContainer?
    var toDo: NotionRichTextContainer?
    var code: NotionRichTextContainer?

    private enum CodingKeys: String, CodingKey {
        case id
        case type
        case hasChildren = "has_children"
        case paragraph
        case heading1 = "heading_1"
        case heading2 = "heading_2"
        case heading3 = "heading_3"
        case bulletedListItem = "bulleted_list_item"
        case numberedListItem = "numbered_list_item"
        case toDo = "to_do"
        case code
    }
}

private struct NotionRichTextContainer: Decodable {
    var richText: [NotionRichText]?
    var checked: Bool?
    var language: String?

    var plainText: String {
        richText?.map(\.plainText).joined() ?? ""
    }

    private enum CodingKeys: String, CodingKey {
        case richText = "rich_text"
        case checked
        case language
    }
}

private struct NotionRichText: Decodable {
    var plainText: String

    private enum CodingKeys: String, CodingKey {
        case plainText = "plain_text"
    }
}
