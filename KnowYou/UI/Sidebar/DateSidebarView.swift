import SwiftUI

struct DateSidebarView: View {
    let dates: [String]
    let selectedDate: String?
    let isActive: Bool
    let isKnowledgeOntologySelected: Bool
    let onSelect: (String) -> Void
    let onOpenKnowledgeOntology: () -> Void
    let onOpenSyncMemory: () -> Void
    @State private var expandedSectionIDs: Set<String> = []
    @Environment(\.openSettings) private var openSettings
    @Environment(\.openURL) private var openURL

    var body: some View {
        VStack(spacing: 0) {
            Button(action: onOpenKnowledgeOntology) {
                HStack(spacing: 8) {
                    Image(systemName: "point.3.connected.trianglepath.dotted")
                    Text("My Wiki")
                    Spacer(minLength: 0)
                }
                .font(.system(size: 13, weight: .semibold))
                .frame(maxWidth: .infinity, minHeight: 34, alignment: .leading)
                .padding(.horizontal, 12)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(isKnowledgeOntologySelected ? Color.accentColor.opacity(0.16) : Color.clear)
            )
            .foregroundStyle(isKnowledgeOntologySelected ? AnyShapeStyle(.primary) : AnyShapeStyle(.secondary))
            .padding(.horizontal, 8)
            .padding(.top, 10)
            .padding(.bottom, 6)

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
                    Button("Sync Memory", action: onOpenSyncMemory)
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
            get: { isActive ? selectedDate : nil },
            set: { newValue in
                if let newValue {
                    onSelect(newValue)
                }
            }
        )
    }

    private var presentation: DateSidebarPresentation {
        DateSidebarPresentation(dates: dates, selectedDate: selectedDate)
    }

    private func dateRow(_ item: DateSidebarItem) -> some View {
        let isSelected = selectedDate == item.id
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

}

struct DateSidebarPresentation {
    let sections: [DateSidebarSection]

    init(dates: [String], selectedDate: String?, today: Date = Date(), calendar: Calendar = .current) {
        let parser = Self.dateParser
        let currentMonth = Self.monthStart(for: today, calendar: calendar)
        let selectedMonth = selectedDate.flatMap(parser.date(from:)).map {
            Self.monthStart(for: $0, calendar: calendar)
        }
        var monthBuckets: [Date: [DateSidebarItem]] = [:]
        var specialItems: [DateSidebarItem] = []

        for dayKey in dates {
            guard let date = parser.date(from: dayKey) else {
                specialItems.append(DateSidebarItem(id: dayKey, title: Self.formattedDay(dayKey)))
                continue
            }

            let month = Self.monthStart(for: date, calendar: calendar)
            monthBuckets[month, default: []].append(
                DateSidebarItem(id: dayKey, title: Self.formattedDay(dayKey))
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
