import Foundation

enum TodayAutomationRefreshAction: Equatable {
    case fullRecovery
    case incremental
}

struct DailyAutomationPlanner {
    let backfillPlanner: BackfillPlanner

    func pendingDays(latestCompletedDay: String?, existingNoteDays: Set<String>, today: String) -> [String] {
        []
    }

    func todayRefreshAction(todayStory: DailyStory?, hasVerifiedSummarizer: Bool) -> TodayAutomationRefreshAction? {
        guard hasVerifiedSummarizer else {
            return nil
        }
        if todayStory?.provenance?.generationMode == .model {
            return .incremental
        }
        return .fullRecovery
    }
}
