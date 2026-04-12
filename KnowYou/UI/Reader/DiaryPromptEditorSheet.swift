import SwiftUI

struct DiaryPromptEditorSheet: View {
    let initialPrompt: String
    let hasActiveOverride: Bool
    let onApply: (String) -> Void
    let onRestoreDefault: () -> Void
    let onClose: () -> Void

    @State private var draftPrompt: String

    init(
        initialPrompt: String,
        hasActiveOverride: Bool,
        onApply: @escaping (String) -> Void,
        onRestoreDefault: @escaping () -> Void,
        onClose: @escaping () -> Void
    ) {
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
                Text("Leave this blank to keep using the built-in system prompt.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
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
        .frame(minWidth: 700, minHeight: 420)
    }
}
