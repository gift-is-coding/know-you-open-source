import Foundation

protocol KnowledgeImportConnector {
    var connectorInstanceID: String { get }
    var connectorID: KnowledgeConnectorID { get }

    func fetchSnapshots() async throws -> [KnowledgeImportSnapshot]
}
