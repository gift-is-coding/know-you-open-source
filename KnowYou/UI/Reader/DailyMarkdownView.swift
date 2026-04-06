import SwiftUI

struct DailyMarkdownView: View {
    let markdownURL: URL?

    var body: some View {
        Group {
            if let markdownURL {
                Text(markdownURL.lastPathComponent)
            } else {
                Text("No day selected")
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
