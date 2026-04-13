import Foundation

struct DailyAutomationPlanner {
    let backfillPlanner: BackfillPlanner

    func pendingDays(latestCompletedDay: String?, existingNoteDays: Set<String>, today: String) -> [String] {
        []
    }

    func shouldAttemptTodayIncremental(todayStory: DailyStory?, hasVerifiedSummarizer: Bool) -> Bool {
        hasVerifiedSummarizer && todayStory?.provenance?.generationMode == .model
    }
}
