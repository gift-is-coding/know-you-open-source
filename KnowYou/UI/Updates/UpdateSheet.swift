import SwiftUI

struct UpdateSheet: View {
    let currentVersion: String
    let offer: UpdateOffer
    let onPrimaryAction: () -> Void
    let onClose: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Update Available")
                .font(.title2.weight(.semibold))

            Text("KnowYou \(offer.pillTitle) is ready.")
                .font(.headline)

            Text(offer.actionDescription)
                .font(.subheadline)
                .foregroundStyle(.secondary)

            HStack(spacing: 12) {
                versionCard(title: "Current", value: currentVersion)
                versionCard(title: "Available", value: offer.availableVersion)
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("What’s New")
                    .font(.headline)

                Text(offer.summaryText)
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if let publishedTimestampText = offer.publishedTimestampText {
                Text("Published \(publishedTimestampText)")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 0)

            HStack {
                Spacer()

                Button("Later", action: onClose)

                Button(offer.primaryActionTitle, action: onPrimaryAction)
                    .keyboardShortcut(.defaultAction)
                    .disabled(offer.actionKind == .unavailable)
            }
        }
        .padding(24)
        .frame(width: 460, alignment: .leading)
    }

    private func versionCard(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)

            Text(value)
                .font(.system(.body, design: .monospaced))
                .fontWeight(.semibold)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor))
        )
    }
}
