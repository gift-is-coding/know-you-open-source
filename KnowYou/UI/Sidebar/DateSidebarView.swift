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

    private func formattedDate(_ dateString: String) -> String {
        let parser = DateFormatter()
        parser.locale = Locale(identifier: "en_US_POSIX")
        parser.dateFormat = "yyyy-MM-dd"
        guard let date = parser.date(from: dateString) else { return dateString }

        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "MM-dd EEE"
        return formatter.string(from: date)
    }
}
