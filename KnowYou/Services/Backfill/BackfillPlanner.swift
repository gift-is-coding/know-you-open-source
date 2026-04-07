import Foundation

struct BackfillPlanner {
    let calendar: Calendar

    func missingDates(lastCompletedDay: String, today: String) -> [String] {
        guard
            let start = parse(lastCompletedDay),
            let end = parse(today),
            start < end
        else {
            return []
        }

        var current = calendar.date(byAdding: .day, value: 1, to: start)
        var dates: [String] = []

        while let day = current, day <= end {
            dates.append(ISO8601DayKey.format(day))
            current = calendar.date(byAdding: .day, value: 1, to: day)
        }

        return dates
    }

    private func parse(_ dayKey: String) -> Date? {
        let parts = dayKey.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3 else {
            return nil
        }

        return calendar.date(
            from: DateComponents(
                calendar: calendar,
                timeZone: .autoupdatingCurrent,
                year: parts[0],
                month: parts[1],
                day: parts[2]
            )
        )
    }
}
