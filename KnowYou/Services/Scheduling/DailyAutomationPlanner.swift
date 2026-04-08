import Foundation

struct DailyAutomationPlanner {
    let backfillPlanner: BackfillPlanner

    func pendingDays(latestCompletedDay: String?, existingNoteDays: Set<String>, today: String) -> [String] {
        let latestExistingNoteDay = existingNoteDays.filter { $0 <= today }.max()
        let baseline = [latestCompletedDay, latestExistingNoteDay].compactMap { $0 }.max()

        guard let baseline else {
            return [today]
        }

        var pendingDays = backfillPlanner.missingDates(lastCompletedDay: baseline, today: today)
        if !pendingDays.contains(today) {
            pendingDays.append(today)
        }

        return pendingDays
    }
}
