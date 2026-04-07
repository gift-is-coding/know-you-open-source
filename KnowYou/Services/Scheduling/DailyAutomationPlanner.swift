import Foundation

struct DailyAutomationPlanner {
    let backfillPlanner: BackfillPlanner

    func pendingDays(latestCompletedDay: String?, existingNoteDays: Set<String>, today: String) -> [String] {
        let latestExistingNoteDay = existingNoteDays.filter { $0 <= today }.max()
        let baseline = [latestCompletedDay, latestExistingNoteDay].compactMap { $0 }.max()

        guard let baseline else {
            return existingNoteDays.contains(today) ? [] : [today]
        }

        let missingDays = backfillPlanner.missingDates(lastCompletedDay: baseline, today: today)
        if !missingDays.isEmpty {
            return missingDays
        }

        return existingNoteDays.contains(today) ? [] : [today]
    }
}
