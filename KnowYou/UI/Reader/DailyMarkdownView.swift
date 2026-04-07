import SwiftUI

struct DailyMarkdownView: View {
    let markdownURL: URL?

    var body: some View {
        Group {
            if let markdownURL, let markdown = try? String(contentsOf: markdownURL) {
                ScrollView {
                    Text(markdown)
                        .font(.system(.body, design: .monospaced))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .topLeading)
                        .padding(28)
                }
                .background(Color(nsColor: .textBackgroundColor))
            } else {
                ContentUnavailableView("No Day Selected", systemImage: "doc.text")
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
