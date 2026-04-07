import Foundation

enum EventSourceType: String, Codable {
    case clipboard
    case notification
}

enum PrivacyAction: String, Codable {
    case keep
    case redact
    case drop
}

struct EventRecord: Equatable, Codable {
    let id: UUID
    let sourceType: EventSourceType
    let sourceApp: String
    let capturedAt: Date
    let dayKey: String
    let text: String?
    let auditText: String?
    let privacyAction: PrivacyAction
    let contentHash: String
}
