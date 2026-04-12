import SwiftUI

struct DiaryPromptEditorSheet: View {
    let defaultPromptPreview: String
    let initialPrompt: String
    let hasActiveOverride: Bool
    let onApply: (String) -> Void
    let onRestoreDefault: () -> Void
    let onClose: () -> Void

    @State private var draftPrompt: String

    init(
        defaultPromptPreview: String,
        initialPrompt: String,
        hasActiveOverride: Bool,
        onApply: @escaping (String) -> Void,
        onRestoreDefault: @escaping () -> Void,
        onClose: @escaping () -> Void
    ) {
        self.defaultPromptPreview = defaultPromptPreview
        self.initialPrompt = initialPrompt
        self.hasActiveOverride = hasActiveOverride
        self.onApply = onApply
        self.onRestoreDefault = onRestoreDefault
        self.onClose = onClose
        _draftPrompt = State(initialValue: initialPrompt)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Diary Prompt")
                    .font(.title3.weight(.semibold))
                Text("Changes here affect future diary generation only. They do not automatically rewrite previously generated diary content.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("System Default Prompt Preview")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)

                ScrollView {
                    Text(defaultPromptPreview)
                        .font(.system(.caption, design: .monospaced))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .textSelection(.enabled)
                }
                .frame(minHeight: 190, maxHeight: 230)
                .padding(12)
                .background(Color(nsColor: .textBackgroundColor))
                .clipShape(RoundedRectangle(cornerRadius: 10))
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("Global Prompt Override")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)

                TextEditor(text: $draftPrompt)
                    .font(.system(.body, design: .monospaced))
                    .frame(minHeight: 180)
                    .padding(8)
                    .background(Color(nsColor: .textBackgroundColor))
                    .clipShape(RoundedRectangle(cornerRadius: 10))
            }

            HStack {
                Button("Close", action: onClose)
                Spacer()
                Button("Restore Default") {
                    draftPrompt = ""
                    onRestoreDefault()
                }
                .disabled(!hasActiveOverride && draftPrompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

                Button("Apply") {
                    onApply(draftPrompt)
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(20)
        .frame(minWidth: 760, minHeight: 620)
    }
}
