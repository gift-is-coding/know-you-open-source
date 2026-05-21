import Foundation

struct ObsidianKnowledgeConnector: KnowledgeImportConnector {
    let connectorInstanceID: String
    let connectorID: KnowledgeConnectorID = .obsidianImport

    private let scanner: FileKnowledgeSnapshotScanner

    init(connectorInstanceID: String, vaultURL: URL) {
        self.connectorInstanceID = connectorInstanceID
        self.scanner = FileKnowledgeSnapshotScanner(
            connectorInstanceID: connectorInstanceID,
            connectorID: .obsidianImport,
            rootURL: vaultURL,
            originKind: "obsidian-vault",
            shouldSkipRemoteID: Self.isKnowYouDailyMemoryExportPath,
            shouldSkipContent: Self.containsKnowYouExportMarker
        )
    }

    func fetchSnapshots() async throws -> [KnowledgeImportSnapshot] {
        try scanner.fetchSnapshots()
    }

    private static func isKnowYouDailyMemoryExportPath(_ remoteID: String) -> Bool {
        remoteID.lowercased().hasPrefix("knowyou/daily memories/")
    }

    private static func containsKnowYouExportMarker(remoteID: String, contentMarkdown: String) -> Bool {
        if frontmatterContainsKnowYouExportMarker(contentMarkdown) {
            return true
        }

        return jsonContainsKnowYouExportMarker(contentMarkdown)
    }

    private static func frontmatterContainsKnowYouExportMarker(_ contentMarkdown: String) -> Bool {
        guard contentMarkdown.hasPrefix("---"), let openingLineEnd = contentMarkdown.firstIndex(of: "\n") else {
            return false
        }

        let openingLine = contentMarkdown[..<openingLineEnd].trimmingCharacters(in: .whitespacesAndNewlines)
        guard openingLine == "---" else {
            return false
        }

        let contentStart = contentMarkdown.index(after: openingLineEnd)
        var lineStart = contentStart
        var hasMarker = false
        var previousLineAllowsNestedYAML = false
        while lineStart < contentMarkdown.endIndex {
            let lineEnd = contentMarkdown[lineStart...].firstIndex(of: "\n") ?? contentMarkdown.endIndex
            let rawLine = String(contentMarkdown[lineStart..<lineEnd])
            let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)

            if line == "---" {
                return hasMarker
            }

            let frontmatterMarker = #"^\s*knowyou_export\s*:\s*daily_memory\s*$"#
            if rawLine.range(of: frontmatterMarker, options: [.regularExpression, .caseInsensitive]) != nil {
                hasMarker = true
                previousLineAllowsNestedYAML = false
            } else if line.isEmpty || line.hasPrefix("#") {
                previousLineAllowsNestedYAML = false
            } else if previousLineAllowsNestedYAML && isNestedYAMLLine(rawLine) {
                previousLineAllowsNestedYAML = true
            } else if let keyValue = yamlKeyValue(in: rawLine) {
                previousLineAllowsNestedYAML = keyValue.value.isEmpty || isYAMLBlockScalarIndicator(keyValue.value)
            } else {
                return false
            }

            guard lineEnd < contentMarkdown.endIndex else {
                break
            }
            lineStart = contentMarkdown.index(after: lineEnd)
        }

        return false
    }

    private static func jsonContainsKnowYouExportMarker(_ contentMarkdown: String) -> Bool {
        let trimmedContent = contentMarkdown.trimmingCharacters(in: .whitespacesAndNewlines)
        guard
            let data = trimmedContent.data(using: .utf8),
            let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else {
            return false
        }

        return object.contains { key, value in
            key.caseInsensitiveCompare("originKind") == .orderedSame
                && (value as? String)?.caseInsensitiveCompare("daily_memory_export") == .orderedSame
        }
    }

    private static func yamlKeyValue(in line: String) -> (key: String, value: String)? {
        let trimmedLine = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let colonIndex = trimmedLine.firstIndex(of: ":") else {
            return nil
        }

        let key = String(trimmedLine[..<colonIndex]).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty, key.allSatisfy(isYAMLKeyCharacter) else {
            return nil
        }

        let valueStart = trimmedLine.index(after: colonIndex)
        let value = String(trimmedLine[valueStart...]).trimmingCharacters(in: .whitespacesAndNewlines)
        return (key, value)
    }

    private static func isYAMLKeyCharacter(_ character: Character) -> Bool {
        character.isLetter || character.isNumber || character == "_" || character == "-"
    }

    private static func isNestedYAMLLine(_ line: String) -> Bool {
        let trimmedLine = line.trimmingCharacters(in: .whitespacesAndNewlines)
        return line.first == " " || line.first == "\t" || trimmedLine.hasPrefix("- ")
    }

    private static func isYAMLBlockScalarIndicator(_ value: String) -> Bool {
        ["|", "|-", "|+", ">", ">-", ">+"].contains(value)
    }
}
