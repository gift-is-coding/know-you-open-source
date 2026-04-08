import Foundation

struct DailyNote: Equatable {
    let dayKey: String
    let markdown: String
    let fileURL: URL
}

struct DailyStory: Equatable, Codable {
    let dayKey: String
    let generatedAt: Date
    let sections: [DailyStorySection]
}

struct DailyStorySection: Equatable, Codable, Identifiable {
    let id: String
    let title: String
    let paragraphs: [DailyStoryParagraph]
}

struct DailyStoryParagraph: Equatable, Codable, Identifiable {
    let id: String
    let text: String
    let sourceEventIDs: [UUID]
}
