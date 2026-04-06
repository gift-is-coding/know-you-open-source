import Foundation

@MainActor
final class AppEnvironment {
    let vaultURL: URL

    init(vaultURL: URL) {
        self.vaultURL = vaultURL
    }
}
