import SwiftUI

struct DiaryEnginePanelRow: Identifiable, Equatable {
    let engine: DiaryEngine
    let status: EngineRuntimeStatus
    let isDefault: Bool
    let isRetesting: Bool

    var id: DiaryEngine { engine }
    var canBecomeDefault: Bool { status.state == .green }
    var testButtonTitle: String {
        if isRetesting {
            return "Testing…"
        }
        return status.lastVerifiedAt == nil ? "Test" : "Retest"
    }
}

struct DiaryEnginePanel: View {
    let rows: [DiaryEnginePanelRow]
    let isRetestingAll: Bool
    let onSelectDefault: (DiaryEngine) -> Void
    let onRetestEngine: (DiaryEngine) -> Void
    let onRetestAll: () -> Void
    let onConfigureAPI: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("Diary Engine")
                    .font(.headline)
                Spacer()
                Button(isRetestingAll ? "Testing…" : "Retest All", action: onRetestAll)
                    .disabled(isRetestingAll)
            }

            ForEach(rows) { row in
                VStack(alignment: .leading, spacing: 10) {
                    HStack(alignment: .center, spacing: 10) {
                        EngineIndicatorLight(state: row.status.state)

                        VStack(alignment: .leading, spacing: 3) {
                            Text(row.engine.displayName)
                                .font(.subheadline.weight(.semibold))
                            Text(row.status.detail)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }

                        Spacer()

                        if row.isDefault {
                            Text("Default")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary)
                        }
                    }

                    HStack(spacing: 8) {
                        Button(row.canBecomeDefault ? (row.isDefault ? "Selected" : "Use Default") : "Unavailable") {
                            onSelectDefault(row.engine)
                        }
                        .disabled(!row.canBecomeDefault || row.isDefault)

                        if row.engine == .llmAPI {
                            Button("Configure", action: onConfigureAPI)
                        } else {
                            Button(row.testButtonTitle) {
                                onRetestEngine(row.engine)
                            }
                            .disabled(row.isRetesting)
                        }
                    }
                    .buttonStyle(.bordered)
                }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
        }
        .padding(16)
        .frame(width: 360)
    }
}
