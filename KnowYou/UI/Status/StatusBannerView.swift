import SwiftUI

struct StatusBannerView: View {
    let message: String?
    let details: [String]

    var body: some View {
        if message != nil || !details.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                if let message {
                    Text(message)
                        .font(.callout.weight(.medium))
                }
                ForEach(details, id: \.self) { detail in
                    Text(detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(Color(nsColor: .controlAccentColor).opacity(0.08))
        }
    }
}
