import Foundation

struct NetworkingInboxService {
    let client: NetworkingPlatformClient

    func loadInbox(projectRoot: URL, token: String, platformIDs: [String]) -> [NetworkingCockpitItem] {
        let localItems = NetworkingInboxStateStore().load(projectRoot: projectRoot).items
        var collected = localItems

        for platformID in platformIDs {
            do {
                let home = try client.agentHome(token: token, platformID: platformID)
                collected.append(
                    contentsOf: NetworkingCockpitPresentation.cockpitItems(fromAgentHome: home, platformID: platformID)
                )
            } catch {
                continue
            }
        }

        return collected.reduce(into: [NetworkingCockpitItem]()) { result, item in
            guard result.contains(where: { $0.id == item.id }) == false else { return }
            result.append(item)
        }
    }
}
