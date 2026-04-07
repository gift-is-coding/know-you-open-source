import Foundation

struct RunRecord: Equatable {
    let id: UUID
    let runType: String
    let dayKey: String?
    let startedAt: Date
    let finishedAt: Date?
    let status: String
}
