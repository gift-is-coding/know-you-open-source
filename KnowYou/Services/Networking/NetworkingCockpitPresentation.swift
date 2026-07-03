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
                        publicReferenceID: item.publicReferenceID,
                        platformID: item.platformID
                    )
                }
            )
        )
    }

    func items(forPlatformID platformID: String) -> [NetworkingCockpitItem] {
        items.filter { item in
            item.platformID == platformID
        }
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

    /// Maps a platform Agent Home payload (the JSON returned by the
    /// `networking_agent_home` RPC or `/api/agent/home`) into cockpit items.
    /// Only public fields cross this boundary; private My Wiki reasoning never
    /// appears in the payload.
    static func cockpitItems(fromAgentHome home: [String: Any], platformID: String) -> [NetworkingCockpitItem] {
        func tasks(_ key: String) -> [[String: Any]] {
            home[key] as? [[String: Any]] ?? []
        }

        func item(
            _ task: [String: Any],
            direction: NetworkingCockpitDirection,
            fallbackTitle: String
        ) -> NetworkingCockpitItem? {
            guard let taskID = task["id"] as? String else { return nil }
            let evidence = (task["publicEvidence"] as? [String]) ?? []
            let reasonCodes = (task["reasonCodes"] as? [String]) ?? []
            return NetworkingCockpitItem(
                id: "\(platformID)-\(taskID)",
                direction: direction,
                title: (task["summary"] as? String).flatMap { $0.isEmpty ? nil : $0 } ?? fallbackTitle,
                publicSummary: evidence.isEmpty ? fallbackTitle : evidence.joined(separator: " · "),
                privateReason: "Public reason codes: \(reasonCodes.joined(separator: ", "))",
                publicReferenceID: task["publicReferenceID"] as? String,
                platformID: platformID
            )
        }

        let needsReply = tasks("needsReply").compactMap { item($0, direction: .inbound, fallbackTitle: "Needs reply") }
        let potentialMatches = tasks("potentialMatches").compactMap { item($0, direction: .highlight, fallbackTitle: "Potential match") }
        let savedForYou = tasks("savedForYou").compactMap { item($0, direction: .outbound, fallbackTitle: "Saved for you") }
        return needsReply + potentialMatches + savedForYou
    }

    static func cockpitItems(for agentActions: [NetworkingAgentAction]) -> [NetworkingCockpitItem] {
        agentActions.map { action in
            NetworkingCockpitItem(
                id: action.id,
                direction: action.status == .sent ? .activity : .outbound,
                title: title(for: action),
                publicSummary: publicSummary(for: action),
                privateReason: action.privateReason,
                publicReferenceID: action.publicReferenceID,
                platformID: action.platformID
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
            return "Potential matches"
        case .inbound:
            return "Needs reply"
        case .outbound:
            return "Saved for you"
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
    let platformID: String
}
