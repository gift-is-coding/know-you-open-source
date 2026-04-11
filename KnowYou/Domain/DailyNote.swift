import Foundation

struct DailyNote: Equatable {
    let dayKey: String
    let markdown: String
    let fileURL: URL
}

enum StoryGenerationMode: String, Equatable, Codable {
    case model
    case fallback
    case legacy
}

struct StoryProvenance: Equatable, Codable {
    let generationMode: StoryGenerationMode
    let engineKind: String
    let engineLabel: String
    let model: String?
    let pipelineVersion: String
    let curatedEventCount: Int?
}

struct DailyStory: Equatable, Codable {
    let dayKey: String
    let generatedAt: Date
    let sections: [DailyStorySection]
    let provenance: StoryProvenance?

    init(
        dayKey: String,
        generatedAt: Date,
        sections: [DailyStorySection],
        provenance: StoryProvenance? = nil
    ) {
        self.dayKey = dayKey
        self.generatedAt = generatedAt
        self.sections = sections
        self.provenance = provenance
    }

    private enum CodingKeys: String, CodingKey {
        case dayKey
        case generatedAt
        case sections
        case provenance
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        dayKey = try container.decode(String.self, forKey: .dayKey)
        generatedAt = try container.decode(Date.self, forKey: .generatedAt)
        sections = try container.decode([DailyStorySection].self, forKey: .sections)
        provenance = try container.decodeIfPresent(StoryProvenance.self, forKey: .provenance)
            ?? StoryProvenance(
                generationMode: .legacy,
                engineKind: "legacy",
                engineLabel: "Legacy Story",
                model: nil,
                pipelineVersion: "legacy",
                curatedEventCount: nil
            )
    }

    func withProvenance(_ provenance: StoryProvenance) -> DailyStory {
        DailyStory(
            dayKey: dayKey,
            generatedAt: generatedAt,
            sections: sections,
            provenance: provenance
        )
    }
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
