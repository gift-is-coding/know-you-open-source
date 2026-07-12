import Foundation

struct NetworkingInboxSnapshot {
    let items: [NetworkingCockpitItem]
    let autonomyModes: [String: String]
}

struct NetworkingInboxService {
    let client: NetworkingPlatformClient

    func loadInbox(projectRoot: URL, token: String, platformIDs: [String]) -> [NetworkingCockpitItem] {
        loadInboxSnapshot(projectRoot: projectRoot, token: token, platformIDs: platformIDs).items
    }

    func loadInboxSnapshot(projectRoot: URL, token: String, platformIDs: [String]) -> NetworkingInboxSnapshot {
        let localItems = NetworkingInboxStateStore().load(projectRoot: projectRoot).items
        var platformItems: [NetworkingCockpitItem] = []
        var autonomyModes: [String: String] = [:]

        for platformID in platformIDs {
            do {
                let home = try client.agentHome(token: token, platformID: platformID)
                platformItems.append(
                    contentsOf: NetworkingCockpitPresentation.cockpitItems(fromAgentHome: home, platformID: platformID)
                )
                autonomyModes[platformID] = NetworkingCockpitPresentation.autonomyMode(fromAgentHome: home)
            } catch {
                continue
            }
        }

        let platformItemsByID = platformItems.reduce(into: [String: NetworkingCockpitItem]()) { result, item in
            result[item.id] = item
        }
        let localIDs = Set(localItems.map(\.id))
        let collected = localItems.map { platformItemsByID[$0.id] ?? $0 }
            + platformItems.filter { localIDs.contains($0.id) == false }

        let uniqueItems = collected.reduce(into: [NetworkingCockpitItem]()) { result, item in
            guard result.contains(where: { $0.id == item.id }) == false else { return }
            result.append(item)
        }
        return NetworkingInboxSnapshot(items: uniqueItems, autonomyModes: autonomyModes)
    }
}
