import SwiftUI

struct DiaryEngineSelectorButton: View {
    let title: String
    let state: EngineIndicatorState
    let action: () -> Void

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
            .background(.regularMaterial, in: Capsule())
        }
        .buttonStyle(.plain)
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
