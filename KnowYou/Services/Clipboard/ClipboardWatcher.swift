import AppKit
import Foundation

@MainActor
final class ClipboardWatcher {
    private let pasteboard: NSPasteboard
    private let privacyFilter: PrivacyFilter
    private let databaseWriter: DatabaseWriter
    private var timer: Timer?
    private var lastChangeCount: Int

    init(
        pasteboard: NSPasteboard = .general,
        privacyFilter: PrivacyFilter,
        databaseWriter: DatabaseWriter
    ) {
        self.pasteboard = pasteboard
        self.privacyFilter = privacyFilter
        self.databaseWriter = databaseWriter
        self.lastChangeCount = pasteboard.changeCount
    }

    func start() {
        guard timer == nil else {
            return
        }

        let timer = Timer.scheduledTimer(withTimeInterval: 1.5, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.poll()
            }
        }
        timer.tolerance = 0.3
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    private func poll() {
        let changeCount = pasteboard.changeCount
        guard changeCount != lastChangeCount else {
            return
        }

        lastChangeCount = changeCount

        guard let text = pasteboard.string(forType: .string), !text.isEmpty else {
            return
        }

        let filtered = privacyFilter.classify(text)
        let payload = filtered.persistedText ?? filtered.auditText ?? ""
        let capturedAt = Date()
        let event = EventRecord(
            id: UUID(),
            sourceType: .clipboard,
            sourceApp: NSWorkspace.shared.frontmostApplication?.localizedName ?? "Unknown",
            capturedAt: capturedAt,
            dayKey: ISO8601DayKey.format(capturedAt),
            text: filtered.persistedText,
            auditText: filtered.auditText,
            privacyAction: filtered.action,
            contentHash: SHA256Hasher.hash(payload)
        )

        try? databaseWriter.insert(event)
    }
}
