import SwiftUI

struct DateSidebarView: View {
    let dates: [String]
    let selectedDate: String?
    let onSelect: (String) -> Void

    var body: some View {
        List(selection: selectedDateBinding) {
            ForEach(dates, id: \.self) { date in
                Label(formattedDate(date), systemImage: "doc.plaintext")
                    .padding(.vertical, 4)
                    .fontWeight(selectedDate == date ? .semibold : .regular)
                    .tag(date)
            }
        }
        .listStyle(.sidebar)
        .navigationTitle("Journals")
        .background(Color(nsColor: .controlBackgroundColor))
    }

    private var selectedDateBinding: Binding<String?> {
        Binding(
            get: { selectedDate },
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
