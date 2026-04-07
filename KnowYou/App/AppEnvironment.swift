import Foundation

@MainActor
final class AppEnvironment {
    let databaseURL: URL
    let databaseWriter: DatabaseWriter
    let privacyFilter: PrivacyFilter
    let clipboardWatcher: ClipboardWatcher
    let notificationCollector: NotificationCollector

    init(databasePath: String) throws {
        let databaseURL = URL(fileURLWithPath: databasePath)
        let databaseWriter = try DatabaseWriter(path: databasePath)
        let privacyFilter = PrivacyFilter()

        self.databaseURL = databaseURL
        self.databaseWriter = databaseWriter
        self.privacyFilter = privacyFilter
        self.clipboardWatcher = ClipboardWatcher(
            privacyFilter: privacyFilter,
            databaseWriter: databaseWriter
        )
        self.notificationCollector = NotificationCollector(
            privacyFilter: privacyFilter,
            databaseWriter: databaseWriter
        )
    }
}
