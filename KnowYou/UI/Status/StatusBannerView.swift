import SwiftUI

struct StatusBannerView: View {
    let message: String?

    var body: some View {
        if let message {
            Text(message)
                .font(.callout)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(12)
                .background(.quaternary.opacity(0.4))
        }
    }
}
