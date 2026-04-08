import SwiftUI

struct DailyMarkdownView: View {
    let markdownURL: URL?
    let contentVersion: Int

    var body: some View {
        Group {
            if let markdownURL, let markdown = try? String(contentsOf: markdownURL) {
                ScrollView {
                    MarkdownContentView(markdown: markdown)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .topLeading)
                        .padding(.horizontal, 40)
                        .padding(.vertical, 32)
                }
                .background(Color(nsColor: .textBackgroundColor))
            } else {
                ContentUnavailableView("No Day Selected", systemImage: "doc.text")
            }
        }
        .id(contentVersion)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct MarkdownContentView: View {
    let markdown: String

    var body: some View {
        if let attributed = try? AttributedString(
            markdown: markdown,
            options: AttributedString.MarkdownParsingOptions(
                interpretedSyntax: .full,
                failurePolicy: .returnPartiallyParsedIfPossible
            )
        ) {
            Text(attributed)
                .frame(maxWidth: .infinity, alignment: .topLeading)
        } else {
            Text(markdown)
                .font(.system(.body, design: .monospaced))
                .lineSpacing(6)
                .frame(maxWidth: .infinity, alignment: .topLeading)
        }
    }
}
