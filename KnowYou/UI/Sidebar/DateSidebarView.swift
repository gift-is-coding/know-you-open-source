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
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        guard let date = formatter.date(from: dateString) else { return dateString }
        
        formatter.dateFormat = "EEEE, MMM d"
        return formatter.string(from: date)
    }
}
