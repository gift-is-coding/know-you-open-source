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
    let recoveryNudge: DiaryEngineRecoveryNudgePresentation?
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

            if let recoveryNudge {
                DiaryEngineRecoveryNudgeBanner(presentation: recoveryNudge)
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

private struct DiaryEngineRecoveryNudgeBanner: View {
    let presentation: DiaryEngineRecoveryNudgePresentation

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: iconName)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(iconColor)
                .frame(width: 18, height: 18)

            VStack(alignment: .leading, spacing: 3) {
                Text(presentation.title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(titleColor)
                Text(presentation.detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(backgroundColor, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(borderColor, lineWidth: 1)
        )
    }

    private var iconName: String {
        switch presentation.kind {
        case .setupRequired:
            return "exclamationmark.circle.fill"
        case .repairRequired:
            return "exclamationmark.triangle.fill"
        }
    }

    private var iconColor: Color {
        switch presentation.kind {
        case .setupRequired:
            return .yellow
        case .repairRequired:
            return .red
        }
    }

    private var titleColor: Color {
        switch presentation.kind {
        case .setupRequired:
            return .primary
        case .repairRequired:
            return .red
        }
    }

    private var backgroundColor: Color {
        switch presentation.kind {
        case .setupRequired:
            return .yellow.opacity(0.12)
        case .repairRequired:
            return .red.opacity(0.09)
        }
    }

    private var borderColor: Color {
        switch presentation.kind {
        case .setupRequired:
            return .yellow.opacity(0.55)
        case .repairRequired:
            return .red.opacity(0.35)
        }
    }
}
