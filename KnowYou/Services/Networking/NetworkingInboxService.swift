import Foundation

struct NetworkingInboxService {
    let client: NetworkingPlatformClient

    func loadInbox(projectRoot: URL, token: String, platformIDs: [String]) -> [NetworkingCockpitItem] {
        let localItems = NetworkingInboxStateStore().load(projectRoot: projectRoot).items
        var platformItems: [NetworkingCockpitItem] = []

        for platformID in platformIDs {
            do {
                let home = try client.agentHome(token: token, platformID: platformID)
                platformItems.append(
                    contentsOf: NetworkingCockpitPresentation.cockpitItems(fromAgentHome: home, platformID: platformID)
                )
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

        return collected.reduce(into: [NetworkingCockpitItem]()) { result, item in
            guard result.contains(where: { $0.id == item.id }) == false else { return }
            result.append(item)
        }
    }
}
