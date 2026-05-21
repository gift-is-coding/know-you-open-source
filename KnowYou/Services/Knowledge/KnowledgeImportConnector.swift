import Foundation

enum KnowledgeImportConnectorError: LocalizedError, Equatable {
    case unavailable(String)
    case unauthorized(String)
    case invalidResponse(String)

    var errorDescription: String? {
        switch self {
        case let .unavailable(message):
            return "Connector unavailable: \(message)"
        case let .unauthorized(message):
            return "Connector unauthorized: \(message)"
        case let .invalidResponse(message):
            return "Connector returned an invalid response: \(message)"
        }
    }
}

protocol KnowledgeImportConnector {
    var connectorInstanceID: String { get }
    var connectorID: KnowledgeConnectorID { get }

    func fetchSnapshots() async throws -> [KnowledgeImportSnapshot]
}
