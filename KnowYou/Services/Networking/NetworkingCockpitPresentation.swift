import Foundation

struct NetworkingCockpitPresentation {
    let items: [NetworkingCockpitItem]

    init(items: [NetworkingCockpitItem] = []) {
        self.items = items
    }

    var sections: [NetworkingCockpitSection] {
        Self.sectionOrder.compactMap { direction in
            let matchingItems = items.filter { $0.direction == direction }
            guard matchingItems.isEmpty == false else { return nil }
            return NetworkingCockpitSection(
                direction: direction,
                title: Self.title(for: direction),
                items: matchingItems
            )
        }
    }

    var localBridgePayload: String {
        encode(
            LocalBridgePayload(
                sections: sections,
                privateFieldsIncluded: ["privateReason"]
            )
        )
    }

    var publicPlatformPayload: String {
        encode(
            PublicPlatformPayload(
                items: items.map { item in
                    PublicCockpitItem(
                        id: item.id,
                        direction: item.direction,
                        title: item.title,
                        publicSummary: item.publicSummary,
                        publicReferenceID: item.publicReferenceID
                    )
                }
            )
        )
    }

    static func attribution(for item: NetworkingPublicContent) -> String {
        let base = "\(item.personName) · \(item.profileLabel)"
        return item.authorType == .ai ? "\(base) · AI" : base
    }

    static func sortedPublicContent(_ items: [NetworkingPublicContent]) -> [NetworkingPublicContent] {
        items.sorted { left, right in
            if left.authorType != right.authorType {
                return priority(for: left.authorType) < priority(for: right.authorType)
            }
            return left.createdAt > right.createdAt
        }
    }

    static func cockpitItems(for agentActions: [NetworkingAgentAction]) -> [NetworkingCockpitItem] {
        agentActions.map { action in
            NetworkingCockpitItem(
                id: action.id,
                direction: action.status == .sent ? .activity : .outbound,
                title: title(for: action),
                publicSummary: publicSummary(for: action),
                privateReason: action.privateReason,
                publicReferenceID: action.publicReferenceID
            )
        }
    }

    private static let sectionOrder: [NetworkingCockpitDirection] = [
        .highlight,
        .inbound,
        .outbound,
        .activity
    ]

    private static func title(for direction: NetworkingCockpitDirection) -> String {
        switch direction {
        case .highlight:
            return "Highlights"
        case .inbound:
            return "People looking for you"
        case .outbound:
            return "Your agent looking outward"
        case .activity:
            return "Agent activity"
        }
    }

    private static func title(for action: NetworkingAgentAction) -> String {
        switch (action.kind, action.status) {
        case (.post, .queued):
            return "Agent prepared a post as \(action.profileLabel)"
        case (.comment, .queued):
            return "Agent prepared a comment as \(action.profileLabel)"
        case (.post, .sent):
            return "Agent posted as \(action.profileLabel)"
        case (.comment, .sent):
            return "Agent commented as \(action.profileLabel)"
        case (_, .skipped):
            return "Agent skipped repetitive activity"
        }
    }

    private static func publicSummary(for action: NetworkingAgentAction) -> String {
        "\(action.profileLabel) · AI: \(action.body)"
    }

    private static func priority(for authorType: NetworkingAuthorType) -> Int {
        switch authorType {
        case .human:
            return 0
        case .ai:
            return 1
        }
    }

    private func encode<T: Encodable>(_ value: T) -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(value),
              let text = String(data: data, encoding: .utf8) else {
            return "{}"
        }
        return text
    }
}

private struct LocalBridgePayload: Codable, Equatable {
    let sections: [NetworkingCockpitSection]
    let privateFieldsIncluded: [String]
}

private struct PublicPlatformPayload: Codable, Equatable {
    let items: [PublicCockpitItem]
}

private struct PublicCockpitItem: Codable, Equatable {
    let id: String
    let direction: NetworkingCockpitDirection
    let title: String
    let publicSummary: String
    let publicReferenceID: String?
}
