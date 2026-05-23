import SwiftUI

struct DateSidebarView: View {
    let dates: [String]
    let selectedDate: String?
    let isActive: Bool
    var knowledgeImportConfig: KnowledgeImportConfig = .default
    let onSelect: (String) -> Void
    let onOpenSyncMemory: () -> Void
    @State private var expandedSectionIDs: Set<String> = []
    @Environment(\.openSettings) private var openSettings
    @Environment(\.openURL) private var openURL

    var body: some View {
        VStack(spacing: 0) {
            List(selection: activeBinding) {
                ForEach(presentation.sections) { section in
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
            get: { isActive ? selectedDate.map(Self.diaryItemID) : nil },
            set: { newValue in
                if let newValue, let dayKey = Self.dayKeyForSelection(newValue) {
                    onSelect(dayKey)
                }
            }
        )
    }

    private var presentation: DateSidebarPresentation {
        DateSidebarPresentation(
            dates: dates,
            selectedItemID: selectedDate.map(Self.diaryItemID),
            knowledgeImportConfig: knowledgeImportConfig
        )
    }

    private func dateRow(_ item: DateSidebarItem) -> some View {
        let isSelected = selectedDate.map(Self.diaryItemID) == item.id
        return Label(item.title, systemImage: "doc.plaintext")
            .padding(.vertical, 4)
            .fontWeight(isSelected ? .semibold : .regular)
            .foregroundStyle(isActive || isSelected ? AnyShapeStyle(.primary) : AnyShapeStyle(.secondary))
            .tag(item.id)
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

struct SidebarRootItem: Identifiable, Equatable {
    let id: String
    let title: String
    let systemImage: String
    let isSelected: Bool
    let isEnabled: Bool
    let showsAddButton: Bool
}

struct DateSidebarPresentation {
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

        rootItems = [
            SidebarRootItem(
                id: "diary-root",
                title: "My Diary",
                systemImage: "book.closed",
                isSelected: selectedItemID == "diary-root",
                isEnabled: true,
                showsAddButton: false
            ),
            SidebarRootItem(
                id: "other-source",
                title: "Other Source",
                systemImage: "tray.full",
                isSelected: selectedItemID == "other-source",
                isEnabled: true,
                showsAddButton: true
            ),
        ] + knowledgeImportConfig.connectorInstances.map { instance in
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
                specialItems.append(DateSidebarItem(id: Self.diaryItemID(for: dayKey), title: Self.formattedDay(dayKey)))
                continue
            }

            let month = Self.monthStart(for: date, calendar: calendar)
            monthBuckets[month, default: []].append(
                DateSidebarItem(id: Self.diaryItemID(for: dayKey), title: Self.formattedDay(dayKey))
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
            sections = monthSections
        } else {
            sections = monthSections + [
                DateSidebarSection(
                    id: "special",
                    title: nil,
                    isExpandedByDefault: true,
                    items: specialItems
                )
            ]
        }
    }

    private static let dateParser: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()

    private static let monthDisplay: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "MMMM yyyy"
        return formatter
    }()

    private static let dayDisplay: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
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

    private static func formattedDay(_ dateString: String) -> String {
        if dateString == OnboardingDemoStory.demoDayKey {
            return "Demo Day"
        }
        guard let date = Self.dateParser.date(from: dateString) else { return dateString }
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
