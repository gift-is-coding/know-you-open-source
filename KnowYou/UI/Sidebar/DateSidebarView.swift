import SwiftUI

struct DateSidebarView: View {
    let dates: [String]
    let selectedDate: String?
    let onSelect: (String) -> Void

    var body: some View {
        List(selection: selectedDateBinding) {
            ForEach(dates, id: \.self) { date in
                Text(date)
                    .fontWeight(selectedDate == date ? .semibold : .regular)
                    .tag(date)
            }
        }
        .navigationTitle("Daily Notes")
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
}
