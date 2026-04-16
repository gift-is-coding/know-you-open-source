import Foundation

struct SyncMemoryPathDetector {
    private struct ObsidianConfigVault: Decodable {
        let path: String
        let ts: Double?
    }

    private struct ObsidianConfig: Decodable {
        let vaults: [String: ObsidianConfigVault]
    }

    let fileManager: FileManager

    init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
    }

    func defaultObsidianConfigDirectory(homePath: String) -> URL {
        URL(fileURLWithPath: homePath, isDirectory: true)
            .appendingPathComponent("Library", isDirectory: true)
            .appendingPathComponent("Application Support", isDirectory: true)
            .appendingPathComponent("obsidian", isDirectory: true)
    }

    func detectConfiguredObsidianVaults(configDirectory: URL) -> [URL] {
        let configURL = configDirectory.appendingPathComponent("obsidian.json")
        guard
            let data = try? Data(contentsOf: configURL),
            let decoded = try? JSONDecoder().decode(ObsidianConfig.self, from: data)
        else {
            return []
        }

        return decoded.vaults.values
            .sorted { ($0.ts ?? 0) > ($1.ts ?? 0) }
            .map { URL(fileURLWithPath: $0.path, isDirectory: true) }
            .filter { isObsidianVault(directory: $0) }
    }

    func detectObsidianVaults(searchRoots: [URL]) -> [URL] {
        searchRoots.flatMap { searchRoot in
            var matches: [URL] = []

            if isObsidianVault(directory: searchRoot) {
                matches.append(searchRoot)
            }

            guard let contents = try? fileManager.contentsOfDirectory(
                at: searchRoot,
                includingPropertiesForKeys: nil,
                options: [.skipsHiddenFiles]
            ) else {
                return matches
            }

            matches.append(contentsOf: contents.filter { candidate in
                isDirectory(candidate) && isObsidianVault(directory: candidate)
            })
            return matches
        }
    }

    func defaultOpenClawWorkspace(homePath: String) -> URL {
        URL(fileURLWithPath: homePath, isDirectory: true)
            .appendingPathComponent(".openclaw", isDirectory: true)
            .appendingPathComponent("workspace", isDirectory: true)
    }

    func openClawMemoryDirectory(for workspace: URL) -> URL {
        workspace.appendingPathComponent("know-you-memory", isDirectory: true)
    }

    private func isObsidianVault(directory: URL) -> Bool {
        isDirectory(directory) && fileManager.fileExists(
            atPath: directory.appendingPathComponent(".obsidian", isDirectory: true).path
        )
    }

    private func isDirectory(_ url: URL) -> Bool {
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: url.path, isDirectory: &isDirectory) else {
            return false
        }
        return isDirectory.boolValue
    }
}
