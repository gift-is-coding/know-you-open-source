import SwiftUI

struct DiaryEngineSelectorButton: View {
    let title: String
    let state: EngineIndicatorState
    let emphasized: Bool
    let action: () -> Void

    init(
        title: String,
        state: EngineIndicatorState,
        emphasized: Bool = false,
        action: @escaping () -> Void
    ) {
        self.title = title
        self.state = state
        self.emphasized = emphasized
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                EngineIndicatorLight(state: state)
                Text(title)
                    .font(.subheadline.weight(.medium))
                    .lineLimit(1)
                Image(systemName: "chevron.down")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(backgroundStyle, in: Capsule())
            .overlay(
                Capsule()
                    .strokeBorder(borderColor, lineWidth: emphasized ? 1.5 : 0)
            )
            .shadow(color: emphasized ? Color.accentColor.opacity(0.18) : .clear, radius: 10, x: 0, y: 4)
        }
        .buttonStyle(.plain)
    }

    private var backgroundStyle: some ShapeStyle {
        if emphasized {
            return AnyShapeStyle(Color.accentColor.opacity(0.12))
        }
        return AnyShapeStyle(.regularMaterial)
    }

    private var borderColor: Color {
        emphasized ? .accentColor.opacity(0.85) : .clear
    }
}

enum DiaryEngineRecoveryNudgeKind: Equatable {
    case setupRequired
    case repairRequired
}

struct DiaryEngineRecoveryNudgePresentation: Equatable {
    let kind: DiaryEngineRecoveryNudgeKind
    let toolbarTitle: String
    let toolbarState: EngineIndicatorState
    let title: String
    let detail: String

    static func make(
        defaultEngine: DiaryEngine,
        engineStatuses: [DiaryEngine: EngineRuntimeStatus]
    ) -> DiaryEngineRecoveryNudgePresentation? {
        if defaultEngine == .none {
            return DiaryEngineRecoveryNudgePresentation(
                kind: .setupRequired,
                toolbarTitle: "Add Diary Engine",
                toolbarState: .yellow,
                title: "Choose a Diary Engine",
                detail: "Connect any engine to generate and refresh diary entries."
            )
        }

        let status = engineStatuses[defaultEngine] ?? EngineRuntimeStatus()
        guard status.state == .green else {
            return DiaryEngineRecoveryNudgePresentation(
                kind: .repairRequired,
                toolbarTitle: "Fix Diary Engine",
                toolbarState: .yellow,
                title: "Diary Engine needs attention",
                detail: "\(defaultEngine.displayName) is not ready. Retest it or configure another engine."
            )
        }

        return nil
    }
}

struct EngineIndicatorLight: View {
    let state: EngineIndicatorState

    var body: some View {
        Circle()
            .fill(color)
            .frame(width: 8, height: 8)
    }

    private var color: Color {
        switch state {
        case .gray:
            return .gray
        case .yellow:
            return .yellow
        case .green:
            return .green
        }
    }
}
