import AppKit
import Foundation

struct ClipboardCaptureSnapshot: Sendable {
    let capturedAt: Date
    let sourceApp: String
    let persistedText: String?
    let auditText: String?
}

@MainActor
final class ClipboardWatcher {
    private let pasteboard: NSPasteboard
    private let privacyFilter: PrivacyFilter
    private let databaseWriter: DatabaseWriter
    private let onCapture: ((ClipboardCaptureSnapshot) -> Void)?
    private var timer: Timer?
    private var lastChangeCount: Int

    init(
        pasteboard: NSPasteboard = .general,
        privacyFilter: PrivacyFilter,
        databaseWriter: DatabaseWriter,
        onCapture: ((ClipboardCaptureSnapshot) -> Void)? = nil
    ) {
        self.pasteboard = pasteboard
        self.privacyFilter = privacyFilter
        self.databaseWriter = databaseWriter
        self.onCapture = onCapture
        self.lastChangeCount = pasteboard.changeCount
    }

    func start() {
        guard timer == nil else {
            return
        }

        // Bootstrap the current clipboard contents so launch-time automation can
        // include the latest real clipboard item in today's note.
        if lastChangeCount == pasteboard.changeCount {
            lastChangeCount -= 1
            poll()
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
        let sourceApp = NSWorkspace.shared.frontmostApplication?.localizedName ?? "Unknown"
        let event = EventRecord(
            id: UUID(),
            sourceType: .clipboard,
            sourceApp: sourceApp,
            capturedAt: capturedAt,
            dayKey: ISO8601DayKey.format(capturedAt),
            text: filtered.persistedText,
            auditText: filtered.auditText,
            privacyAction: filtered.action,
            contentHash: Self.contentHash(for: payload, dayKey: ISO8601DayKey.format(capturedAt))
        )

        do {
            try databaseWriter.insert(event)
            onCapture?(
                ClipboardCaptureSnapshot(
                    capturedAt: capturedAt,
                    sourceApp: sourceApp,
                    persistedText: filtered.persistedText,
                    auditText: filtered.auditText
                )
            )
        } catch {
            print("ClipboardWatcher: failed to insert event: \(error)")
        }
    }

    nonisolated static func contentHash(for payload: String, dayKey: String) -> String {
        SHA256Hasher.hash("\(dayKey):\(payload)")
    }
}
