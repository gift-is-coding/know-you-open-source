import SwiftUI

struct DateSidebarView: View {
    let dates: [String]
    let selectedDate: String?
    let isActive: Bool
    let onSelect: (String) -> Void
    let onOpenSyncMemory: () -> Void
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        VStack(spacing: 0) {
            List(selection: activeBinding) {
                ForEach(dates, id: \.self) { date in
                    let isSelected = selectedDate == date
                    Label(formattedDate(date), systemImage: "doc.plaintext")
                        .padding(.vertical, 4)
                        .fontWeight(isSelected ? .semibold : .regular)
                        .foregroundStyle(isActive || isSelected ? AnyShapeStyle(.primary) : AnyShapeStyle(.secondary))
                        .tag(date)
                }
            }
            .listStyle(.sidebar)

            Divider()

            HStack {
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
                .padding(12)

                Spacer()
            }
        }
        .navigationTitle("Journals")
        .background(Color(nsColor: .controlBackgroundColor))
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

    private static let dateParser: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    private static let dateDisplay: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "MM-dd EEE"
        return f
    }()

    private func formattedDate(_ dateString: String) -> String {
        guard let date = Self.dateParser.date(from: dateString) else { return dateString }
        return Self.dateDisplay.string(from: date)
    }
}
