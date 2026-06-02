import Foundation

struct TodoStore {
    private let databaseWriter: DatabaseWriter
    private let documentStore: TodoMarkdownDocumentStore?

    init(databaseWriter: DatabaseWriter, documentURL: URL? = nil) {
        self.databaseWriter = databaseWriter
        documentStore = documentURL.map(TodoMarkdownDocumentStore.init(documentURL:))
    }

    func createTodo(
        title: String,
        sourceDayKey: String,
        sourceEventIDs: [UUID],
        createdAt: Date,
        promotionKind: UnifiedTodoItem.PromotionKind
    ) throws -> UnifiedTodoItem {
        if let documentStore {
            var items = try fetchMarkdownBackedItems(using: documentStore)
            let cleanTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !cleanTitle.isEmpty else {
                throw TodoStoreError.emptyTitle
            }
            let normalizedTitle = UnifiedTodoItem.normalizeTitle(cleanTitle)
            if let index = items.firstIndex(where: { $0.normalizedTitle == normalizedTitle }) {
                items[index].sourceEventIDs = Self.uniqueUUIDs(items[index].sourceEventIDs + sourceEventIDs)
                try documentStore.writeItems(items)
                return items[index]
            }

            let item = UnifiedTodoItem(
                id: UUID().uuidString,
                title: cleanTitle,
                normalizedTitle: normalizedTitle,
                status: .open,
                sourceDayKey: sourceDayKey,
                sourceEventIDs: Self.uniqueUUIDs(sourceEventIDs),
                createdAt: createdAt,
                completedAt: nil,
                completionEvidenceEventIDs: [],
                promotionKind: promotionKind,
                completionKind: nil
            )
            items.append(item)
            try documentStore.writeItems(items)
            return item
        }

        return try databaseWriter.createTodo(
            title: title,
            sourceDayKey: sourceDayKey,
            sourceEventIDs: sourceEventIDs,
            createdAt: createdAt,
            promotionKind: promotionKind
        )
    }

    func fetchTodoItems() throws -> [UnifiedTodoItem] {
        if let documentStore {
            return try fetchMarkdownBackedItems(using: documentStore)
        }

        return try databaseWriter.fetchTodoItems()
    }

    func ensureDocumentExists() throws {
        guard let documentStore, documentStore.exists == false else { return }
        let databaseItems = try databaseWriter.fetchTodoItems()
        try documentStore.writeItems(databaseItems)
    }

    func completeTodo(
        id: String,
        completedAt: Date,
        completionKind: UnifiedTodoItem.CompletionKind,
        evidenceEventIDs: [UUID]
    ) throws {
        if let documentStore {
            var items = try fetchMarkdownBackedItems(using: documentStore)
            guard let index = items.firstIndex(where: { $0.id == id }) else {
                return
            }
            items[index].status = .completed
            items[index].completedAt = completedAt
            items[index].completionKind = completionKind
            items[index].completionEvidenceEventIDs = Self.uniqueUUIDs(evidenceEventIDs)
            try documentStore.writeItems(items)
            return
        }

        try databaseWriter.completeTodo(
            id: id,
            completedAt: completedAt,
            completionKind: completionKind,
            evidenceEventIDs: evidenceEventIDs
        )
    }

    func updateTodoTitle(id: String, title: String) throws {
        let cleanTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanTitle.isEmpty else {
            throw TodoMutationError.emptyTitle
        }
        let normalizedTitle = UnifiedTodoItem.normalizeTitle(cleanTitle)
        guard !normalizedTitle.isEmpty else {
            throw TodoMutationError.emptyTitle
        }

        if let documentStore {
            var items = try fetchMarkdownBackedItems(using: documentStore)
            guard let index = items.firstIndex(where: { $0.id == id }) else {
                return
            }
            if items.contains(where: { $0.id != id && $0.normalizedTitle == normalizedTitle }) {
                throw TodoMutationError.duplicateTitle
            }
            items[index].title = cleanTitle
            items[index].normalizedTitle = normalizedTitle
            try documentStore.writeItems(items)
            return
        }

        try databaseWriter.updateTodoTitle(id: id, title: title)
    }

    func reopenTodo(id: String) throws {
        if let documentStore {
            var items = try fetchMarkdownBackedItems(using: documentStore)
            guard let index = items.firstIndex(where: { $0.id == id }) else {
                return
            }
            items[index].status = .open
            items[index].completedAt = nil
            items[index].completionKind = nil
            items[index].completionEvidenceEventIDs = []
            try documentStore.writeItems(items)
            return
        }

        try databaseWriter.reopenTodo(id: id)
    }

    func deleteTodo(id: String) throws {
        if let documentStore {
            var items = try fetchMarkdownBackedItems(using: documentStore)
            items.removeAll { $0.id == id }
            try documentStore.writeItems(items)
            return
        }

        try databaseWriter.deleteTodo(id: id)
    }

    func mergeTodoEvidence(id: String, sourceEventIDs: [UUID]) throws {
        if let documentStore {
            var items = try fetchMarkdownBackedItems(using: documentStore)
            guard let index = items.firstIndex(where: { $0.id == id }) else {
                return
            }
            items[index].sourceEventIDs = Self.uniqueUUIDs(items[index].sourceEventIDs + sourceEventIDs)
            try documentStore.writeItems(items)
            return
        }

        try databaseWriter.mergeTodoEvidence(id: id, sourceEventIDs: sourceEventIDs)
    }

    private func fetchMarkdownBackedItems(using documentStore: TodoMarkdownDocumentStore) throws -> [UnifiedTodoItem] {
        if !documentStore.exists {
            let databaseItems = try databaseWriter.fetchTodoItems()
            try documentStore.writeItems(databaseItems)
            return Self.sortedItems(databaseItems)
        }

        return Self.sortedItems(try documentStore.fetchItems())
    }

    fileprivate static func sortedItems(_ items: [UnifiedTodoItem]) -> [UnifiedTodoItem] {
        items.sorted { left, right in
            if left.status != right.status {
                return left.status == .open
            }
            if left.createdAt != right.createdAt {
                return left.createdAt < right.createdAt
            }
            return (left.completedAt ?? .distantFuture) < (right.completedAt ?? .distantFuture)
        }
    }

    private static func uniqueUUIDs(_ ids: [UUID]) -> [UUID] {
        var seen = Set<UUID>()
        var unique: [UUID] = []
        for id in ids where seen.insert(id).inserted {
            unique.append(id)
        }
        return unique
    }
}

private enum TodoStoreError: LocalizedError {
    case emptyTitle

    var errorDescription: String? {
        switch self {
        case .emptyTitle:
            return "Todo title cannot be empty."
        }
    }
}

private struct TodoMarkdownDocumentStore {
    let documentURL: URL

    var exists: Bool {
        FileManager.default.fileExists(atPath: documentURL.path)
    }

    func fetchItems() throws -> [UnifiedTodoItem] {
        guard exists else {
            return []
        }

        let markdown = try String(contentsOf: documentURL, encoding: .utf8)
        return markdown
            .components(separatedBy: .newlines)
            .compactMap(Self.item(fromLine:))
    }

    func writeItems(_ items: [UnifiedTodoItem]) throws {
        try FileManager.default.createDirectory(
            at: documentURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try Self.render(items: TodoStore.sortedItems(items))
            .write(to: documentURL, atomically: true, encoding: .utf8)
    }

    private static func render(items: [UnifiedTodoItem]) throws -> String {
        let openItems = items.filter { $0.status == .open }
        let completedItems = items.filter { $0.status == .completed }
        var lines = [
            "# Todo",
            "",
            "## Open",
            "",
        ]

        lines.append(contentsOf: try openItems.map(renderLine))
        lines.append("")
        lines.append("## Completed")
        lines.append("")
        lines.append(contentsOf: try completedItems.map(renderLine))
        lines.append("")
        return lines.joined(separator: "\n")
    }

    private static func renderLine(_ item: UnifiedTodoItem) throws -> String {
        let checkbox = item.status == .completed ? "x" : " "
        let title = item.title
            .replacingOccurrences(of: "\n", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let metadata = TodoMarkdownMetadata(item: item)
        let data = try JSONEncoder().encode(metadata)
        let json = String(data: data, encoding: .utf8) ?? "{}"
        return "- [\(checkbox)] \(title) <!-- knowyou:todo \(json) -->"
    }

    private static func item(fromLine line: String) -> UnifiedTodoItem? {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        let isOpen = trimmed.hasPrefix("- [ ]") || trimmed.hasPrefix("* [ ]")
        let isCompleted = trimmed.hasPrefix("- [x]") || trimmed.hasPrefix("- [X]")
            || trimmed.hasPrefix("* [x]") || trimmed.hasPrefix("* [X]")
        guard isOpen || isCompleted else {
            return nil
        }

        var body = String(trimmed.dropFirst(5)).trimmingCharacters(in: .whitespacesAndNewlines)
        let metadata = extractMetadata(from: &body)
        let normalizedTitle = UnifiedTodoItem.normalizeTitle(body)
        guard !body.isEmpty, !normalizedTitle.isEmpty else {
            return nil
        }

        return UnifiedTodoItem(
            id: metadata?.id ?? fallbackID(for: normalizedTitle),
            title: body,
            normalizedTitle: normalizedTitle,
            status: isCompleted ? .completed : .open,
            sourceDayKey: metadata?.sourceDayKey ?? "",
            sourceEventIDs: metadata?.sourceEventIDs.compactMap(UUID.init(uuidString:)) ?? [],
            createdAt: Date(timeIntervalSince1970: metadata?.createdAt ?? 0),
            completedAt: metadata?.completedAt.map(Date.init(timeIntervalSince1970:)),
            completionEvidenceEventIDs: metadata?.completionEvidenceEventIDs.compactMap(UUID.init(uuidString:)) ?? [],
            promotionKind: metadata.flatMap { UnifiedTodoItem.PromotionKind(rawValue: $0.promotionKind) } ?? .manual,
            completionKind: metadata?.completionKind.flatMap(UnifiedTodoItem.CompletionKind.init(rawValue:))
        )
    }

    private static func extractMetadata(from body: inout String) -> TodoMarkdownMetadata? {
        guard let start = body.range(of: "<!-- knowyou:todo "),
              let end = body.range(of: " -->", range: start.upperBound..<body.endIndex)
        else {
            return nil
        }

        let json = String(body[start.upperBound..<end.lowerBound])
        body = String(body[..<start.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
        guard let data = json.data(using: .utf8) else {
            return nil
        }
        return try? JSONDecoder().decode(TodoMarkdownMetadata.self, from: data)
    }

    private static func fallbackID(for normalizedTitle: String) -> String {
        let encoded = Data(normalizedTitle.utf8)
            .base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
        return "md-\(encoded)"
    }
}

private struct TodoMarkdownMetadata: Codable {
    let id: String
    let sourceDayKey: String
    let sourceEventIDs: [String]
    let createdAt: TimeInterval
    let completedAt: TimeInterval?
    let completionEvidenceEventIDs: [String]
    let promotionKind: String
    let completionKind: String?

    init(item: UnifiedTodoItem) {
        id = item.id
        sourceDayKey = item.sourceDayKey
        sourceEventIDs = item.sourceEventIDs.map(\.uuidString)
        createdAt = item.createdAt.timeIntervalSince1970
        completedAt = item.completedAt?.timeIntervalSince1970
        completionEvidenceEventIDs = item.completionEvidenceEventIDs.map(\.uuidString)
        promotionKind = item.promotionKind.rawValue
        completionKind = item.completionKind?.rawValue
    }
}
