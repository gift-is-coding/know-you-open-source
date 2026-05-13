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
            return "总结"
        case .person:
            return "人物"
        case .project:
            return "项目"
        case .theme:
            return "主题"
        case .preference:
            return "偏好"
        case .openLoop:
            return "待办"
        }
    }
}
