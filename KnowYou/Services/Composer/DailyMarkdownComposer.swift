import Foundation

struct DailyMarkdownComposer {
    func compose(dayKey: String, events: [EventRecord], summary: String?) -> String {
        let timelineLines = bulletList(
            for: events.map { event in
                let body = event.text ?? event.auditText ?? ""
                return "\(event.sourceApp): \(body)"
            }
        )
        let clipboardLines = bulletList(
            for: events
                .filter { $0.sourceType == .clipboard }
                .map { $0.text ?? $0.auditText ?? "" }
        )
        let notificationLines = bulletList(
            for: events
                .filter { $0.sourceType == .notification }
                .map { $0.text ?? $0.auditText ?? "" }
        )

        return """
        # \(dayKey)

        ## Summary

        \(summary ?? "_Pending summary_")

        ## Timeline

        \(timelineLines)

        ## Clipboard

        \(clipboardLines)

        ## Notifications

        \(notificationLines)
        """
    }

    private func bulletList(for items: [String]) -> String {
        let lines = items
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .map { "- \($0)" }

        return lines.isEmpty ? "_No entries_" : lines.joined(separator: "\n")
    }
}
