import Foundation

struct MyWikiDashboardSnapshot: Equatable {
    var summaries: [MyWikiEntry]
    var people: [MyWikiEntry]
    var projects: [MyWikiEntry]
    var themes: [MyWikiEntry]
    var preferences: [MyWikiEntry]
    var openLoops: [MyWikiEntry]

    static let empty = MyWikiDashboardSnapshot(
        summaries: [],
        people: [],
        projects: [],
        themes: [],
        preferences: [],
        openLoops: []
    )
}

struct MyWikiEntry: Identifiable, Equatable {
    let id: String
    let title: String
    let category: MyWikiCategory
    let summary: String
    let sourceNames: [String]
}

enum MyWikiCategory: String, CaseIterable, Equatable {
    case summary
    case person
    case project
    case theme
    case preference
    case openLoop
}

extension MyWikiCategory {
    var displayTitle: String {
        switch self {
        case .summary:
            return "Summary"
        case .person:
            return "People"
        case .project:
            return "Projects"
        case .theme:
            return "Topics"
        case .preference:
            return "Preferences"
        case .openLoop:
            return "Follow-ups"
        }
    }
}
