import SwiftUI

struct DateSidebarView: View {
    let dates: [String]
    let selectedDate: String?
    let onSelect: (String) -> Void

    var body: some View {
        List(dates, id: \.self) { date in
            Button {
                onSelect(date)
            } label: {
                HStack {
                    Text(date)
                        .fontWeight(selectedDate == date ? .semibold : .regular)
                    Spacer(minLength: 0)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .navigationTitle("Daily Notes")
    }
}
