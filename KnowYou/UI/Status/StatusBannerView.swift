import SwiftUI

struct StatusBannerView: View {
    let message: String?

    var body: some View {
        if let message {
            Text(message)
                .font(.callout)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(Color(nsColor: .controlAccentColor).opacity(0.08))
        }
    }
}
