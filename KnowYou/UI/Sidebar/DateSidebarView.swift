import SwiftUI

struct DateSidebarView: View {
    let dates: [String]
    let selectedDate: String?
    let selectedItemID: String?
    let knowledgeImportConfig: KnowledgeImportConfig
    let isActive: Bool
    let onSelectDiaryDate: (String) -> Void
    let onSelectOtherSource: (_ focusAddConnector: Bool) -> Void
    let onSelectKnowledgeConnector: (String) -> Void
    let onOpenSyncMemory: () -> Void
    @State private var expandedSectionIDs: Set<String> = []
    @State private var isSourceGroupExpanded = true
    @State private var isDiaryGroupExpanded = true
    @Environment(\.openSettings) private var openSettings
    @Environment(\.openURL) private var openURL

    var body: some View {
        VStack(spacing: 0) {
            List(selection: activeBinding) {
                DisclosureGroup(isExpanded: $isSourceGroupExpanded) {
                    DisclosureGroup(isExpanded: $isDiaryGroupExpanded) {
                        ForEach(presentation.diarySections) { section in
                            diarySectionRows(section)
                        }
                    } label: {
                        diaryGroupLabel(presentation.diaryRootItem)
                    }

                    ForEach(presentation.sourceItems) { item in
                        rootRow(item)
                    }
                } label: {
                    sourceGroupLabel(presentation.sourceRootItem)
                }
            }
            .listStyle(.sidebar)

            Divider()

            HStack(spacing: 4) {
                Menu {
                    Button("Connectors", action: onOpenSyncMemory)
                    Button("Settings") {
                        openSettings()
                    }
                } label: {
                    Image(systemName: "gearshape")
                        .font(.title3)
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .padding(.leading, 12)
                .padding(.vertical, 12)

                Menu {
                    Button {
                        openURL(AppSupportMetadata.twitterURL)
                    } label: {
                        Label(AppSupportMetadata.twitterButtonTitle, systemImage: "bubble.left.and.text.bubble.right")
                    }

                    Button {
                        openURL(AppSupportMetadata.emailURL)
                    } label: {
                        Label(AppSupportMetadata.emailButtonTitle, systemImage: "envelope")
                    }

                    if let discordURL = AppSupportMetadata.discordURL {
                        Button {
                            openURL(discordURL)
                        } label: {
                            Label(AppSupportMetadata.discordButtonTitle, systemImage: "person.3")
                        }
                    }
                } label: {
                    Image(systemName: "bubble.left.and.text.bubble.right")
                        .font(.title3)
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .padding(.vertical, 12)

                Spacer()
            }
        }
        .navigationTitle("Journals")
        .background(Color(nsColor: .controlBackgroundColor))
        .onAppear {
            seedExpandedSections()
        }
        .onChange(of: dates) {
            seedExpandedSections()
        }
        .onChange(of: selectedDate) {
            seedExpandedSections()
        }
    }

    private var activeBinding: Binding<String?> {
        Binding(
            get: { isActive ? selectedItemID : nil },
            set: { newValue in
                if let newValue {
                    handleSelectionAction(Self.selectionAction(for: newValue))
                }
            }
        )
    }

    private var presentation: DateSidebarPresentation {
        DateSidebarPresentation(
            dates: dates,
            selectedItemID: selectedItemID,
            knowledgeImportConfig: knowledgeImportConfig
        )
    }

    private func sourceGroupLabel(_ item: SidebarRootItem) -> some View {
        HStack(spacing: 8) {
            Button {
                selectRootItem(item)
            } label: {
                HStack(spacing: 8) {
                    Label(item.title, systemImage: item.systemImage)
                        .foregroundStyle(.primary)
                    Spacer()
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Button {
                onSelectOtherSource(true)
            } label: {
                Image(systemName: "plus")
            }
            .buttonStyle(.borderless)
            .help("Add Source")
            .accessibilityLabel("Add Source")
            .accessibilityIdentifier("add-source-add-button")
        }
        .padding(.vertical, 4)
        .fontWeight(item.isSelected ? .semibold : .regular)
        .tag(item.id)
    }

    private func diaryGroupLabel(_ item: SidebarRootItem) -> some View {
        Button {
            selectRootItem(item)
        } label: {
            HStack(spacing: 8) {
                Label(item.title, systemImage: item.systemImage)
                    .foregroundStyle(.primary)
                Spacer()
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.vertical, 4)
        .fontWeight(item.isSelected ? .semibold : .regular)
        .tag(item.id)
    }

    private func rootRow(_ item: SidebarRootItem) -> some View {
        HStack(spacing: 8) {
            Button {
                selectRootItem(item)
            } label: {
                HStack(spacing: 8) {
                    Label(item.title, systemImage: item.systemImage)
                        .foregroundStyle(item.isEnabled ? AnyShapeStyle(.primary) : AnyShapeStyle(.secondary))
                    Spacer()
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if item.showsAddButton {
                Button {
                    onSelectOtherSource(true)
                } label: {
                    Image(systemName: "plus")
                }
                .buttonStyle(.borderless)
                .help("Add Source")
                .accessibilityLabel("Add Source")
                .accessibilityIdentifier("add-source-add-button")
            }
        }
        .padding(.vertical, 4)
        .fontWeight(item.isSelected ? .semibold : .regular)
        .tag(item.id)
    }

    @ViewBuilder
    private func diarySectionRows(_ section: DateSidebarSection) -> some View {
        if let title = section.title {
            DisclosureGroup(isExpanded: expansionBinding(for: section)) {
                ForEach(section.items) { item in
                    dateRow(item)
                }
            } label: {
                Text(title)
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundStyle(.secondary)
            }
        } else {
            ForEach(section.items) { item in
                dateRow(item)
            }
        }
    }

    private func dateRow(_ item: DateSidebarItem) -> some View {
        let dayKey = item.id.replacingOccurrences(of: "diary:", with: "")
        let isSelected = selectedItemID == item.id
        return Label(item.title, systemImage: "doc.plaintext")
            .padding(.vertical, 4)
            .fontWeight(isSelected ? .semibold : .regular)
            .foregroundStyle(isActive || isSelected ? AnyShapeStyle(.primary) : AnyShapeStyle(.secondary))
            .tag(item.id)
            .onTapGesture {
                onSelectDiaryDate(dayKey)
            }
    }

    private func handleSelectionAction(_ action: SidebarSelectionAction?) {
        switch action {
        case .diaryDate(let dayKey):
            onSelectDiaryDate(dayKey)
        case .otherSource(let focusAddConnector):
            onSelectOtherSource(focusAddConnector)
        case .knowledgeConnector(let instanceID):
            onSelectKnowledgeConnector(instanceID)
        case nil:
            break
        }
    }

    static func selectionAction(for itemID: String) -> SidebarSelectionAction? {
        if let dayKey = dayKeyForSelection(itemID) {
            return .diaryDate(dayKey)
        } else if itemID == "add-source" || itemID == "other-source" {
            return .otherSource(focusAddConnector: false)
        } else if itemID.hasPrefix("connector:") {
            return .knowledgeConnector(String(itemID.dropFirst("connector:".count)))
        }
        return nil
    }

    private func selectRootItem(_ item: SidebarRootItem) {
        if item.id == "diary-root" {
            if let selectedDate {
                onSelectDiaryDate(selectedDate)
            }
        } else {
            handleSelectionAction(Self.selectionAction(for: item.id))
        }
    }

    private func expansionBinding(for section: DateSidebarSection) -> Binding<Bool> {
        Binding(
            get: { expandedSectionIDs.contains(section.id) },
            set: { isExpanded in
                if isExpanded {
                    expandedSectionIDs.insert(section.id)
                } else {
                    expandedSectionIDs.remove(section.id)
                }
            }
        )
    }

    private func seedExpandedSections() {
        expandedSectionIDs = Set(
            presentation.sections
                .filter(\.isExpandedByDefault)
                .map(\.id)
        )
    }

    private static func diaryItemID(for dayKey: String) -> String {
        "diary:\(dayKey)"
    }

    static func dayKeyForSelection(_ itemID: String) -> String? {
        let prefix = "diary:"
        guard itemID.hasPrefix(prefix) else { return nil }
        return String(itemID.dropFirst(prefix.count))
    }

}

enum SidebarSelectionAction: Equatable {
    case diaryDate(String)
    case otherSource(focusAddConnector: Bool)
    case knowledgeConnector(String)
}

struct SidebarRootItem: Identifiable, Equatable {
    let id: String
    let title: String
    let systemImage: String
    let isSelected: Bool
    let isEnabled: Bool
    let showsAddButton: Bool
}

struct DateSidebarPresentation {
    let sourceRootItem: SidebarRootItem
    let diaryRootItem: SidebarRootItem
    let sourceItems: [SidebarRootItem]
    let diarySections: [DateSidebarSection]
    let rootItems: [SidebarRootItem]
    let sections: [DateSidebarSection]

    init(
        dates: [String],
        selectedItemID: String?,
        knowledgeImportConfig: KnowledgeImportConfig = .default,
        today: Date = Date(),
        calendar: Calendar = .current
    ) {
        let parser = Self.dateParser
        let currentMonth = Self.monthStart(for: today, calendar: calendar)
        let selectedDayKey = selectedItemID.map(Self.dayKey)
        let selectedMonth = selectedDayKey.flatMap(parser.date(from:)).map {
            Self.monthStart(for: $0, calendar: calendar)
        }
        var monthBuckets: [Date: [DateSidebarItem]] = [:]
        var specialItems: [DateSidebarItem] = []

        sourceRootItem = SidebarRootItem(
            id: "add-source",
            title: "Add Source",
            systemImage: "plus.square.on.square",
            isSelected: selectedItemID == "add-source" || selectedItemID == "other-source",
            isEnabled: true,
            showsAddButton: true
        )
        diaryRootItem = SidebarRootItem(
            id: "diary-root",
            title: "My Diary",
            systemImage: "book.closed",
            isSelected: selectedItemID == "diary-root",
            isEnabled: true,
            showsAddButton: false
        )
        sourceItems = knowledgeImportConfig.connectorInstances.map { instance in
            SidebarRootItem(
                id: "connector:\(instance.id)",
                title: instance.displayName,
                systemImage: Self.systemImage(for: instance.connectorID),
                isSelected: selectedItemID == "connector:\(instance.id)",
                isEnabled: instance.isEnabled,
                showsAddButton: false
            )
        }

        for dayKey in dates {
            guard let date = parser.date(from: dayKey) else {
                specialItems.append(
                    DateSidebarItem(
                        id: Self.diaryItemID(for: dayKey),
                        title: Self.formattedDay(dayKey, today: today, calendar: calendar)
                    )
                )
                continue
            }

            let month = Self.monthStart(for: date, calendar: calendar)
            monthBuckets[month, default: []].append(
                DateSidebarItem(
                    id: Self.diaryItemID(for: dayKey),
                    title: Self.formattedDay(dayKey, today: today, calendar: calendar)
                )
            )
        }

        let monthSections = monthBuckets.keys.sorted(by: >).map { month in
            DateSidebarSection(
                id: Self.monthID(for: month),
                title: Self.monthDisplay.string(from: month),
                isExpandedByDefault: month == currentMonth || month == selectedMonth,
                items: monthBuckets[month, default: []]
            )
        }

        if specialItems.isEmpty {
            diarySections = monthSections
        } else {
            diarySections = monthSections + [
                DateSidebarSection(
                    id: "special",
                    title: nil,
                    isExpandedByDefault: true,
                    items: specialItems
                )
            ]
        }
        rootItems = [sourceRootItem, diaryRootItem] + sourceItems
        sections = diarySections
    }

    private static let dateParser: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()

    private static let monthDisplay: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "MMMM yyyy"
        return formatter
    }()

    private static let dayDisplay: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "MM-dd EEE"
        return formatter
    }()

    private static func monthStart(for date: Date, calendar: Calendar) -> Date {
        let components = calendar.dateComponents([.year, .month], from: date)
        return calendar.date(from: components) ?? date
    }

    private static func monthID(for date: Date) -> String {
        dateParser.string(from: date)
    }

    private static func diaryItemID(for dayKey: String) -> String {
        "diary:\(dayKey)"
    }

    private static func dayKey(from itemID: String) -> String {
        itemID.replacing(/^diary:/, with: "")
    }

    private static func systemImage(for connectorID: KnowledgeConnectorID) -> String {
        switch connectorID {
        case .localFolderImport:
            return "folder"
        case .obsidianImport:
            return "square.stack.3d.up"
        case .feishuImport:
            return "doc.richtext"
        case .notionImport:
            return "doc.on.doc"
        case .googleDriveImport:
            return "externaldrive"
        case .obsidianExport, .openClawExport:
            return "arrow.up.doc"
        }
    }

    private static func formattedDay(_ dateString: String, today: Date, calendar: Calendar) -> String {
        if dateString == OnboardingDemoStory.demoDayKey {
            return "Demo Day"
        }
        guard let date = Self.dateParser.date(from: dateString) else { return dateString }
        if calendar.isDate(date, inSameDayAs: today) {
            return "Today"
        }
        if let yesterday = calendar.date(byAdding: .day, value: -1, to: today),
           calendar.isDate(date, inSameDayAs: yesterday) {
            return "Yesterday"
        }
        return Self.dayDisplay.string(from: date)
    }
}

struct DateSidebarSection: Identifiable, Equatable {
    let id: String
    let title: String?
    let isExpandedByDefault: Bool
    let items: [DateSidebarItem]
}

struct DateSidebarItem: Identifiable, Equatable {
    let id: String
    let title: String
}
