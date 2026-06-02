import SwiftUI

struct UpdateSheet: View {
    let currentVersion: String
    let offer: UpdateOffer
    let onPrimaryAction: () -> Void
    let onClose: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack(alignment: .center, spacing: 12) {
                Image(systemName: "arrow.down.circle.fill")
                    .font(.system(size: 34, weight: .semibold))
                    .foregroundStyle(Color.orange)

                VStack(alignment: .leading, spacing: 4) {
                    Text("Update Available")
                        .font(.title2.weight(.bold))

                    Text("KnowYou \(offer.availableVersion) is ready.")
                        .font(.headline)
                        .foregroundStyle(.secondary)
                }
            }

            HStack(spacing: 12) {
                versionCard(title: "Current", value: currentVersion)
                versionCard(title: "Available", value: offer.availableVersion)
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("What's New")
                    .font(.headline)

                Text(offer.summaryText)
                    .font(.body)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color(nsColor: .textBackgroundColor))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(Color.orange.opacity(0.35), lineWidth: 1)
            )

            Text(offer.actionDescription)
                .font(.subheadline)
                .foregroundStyle(.secondary)

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
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
                    .disabled(offer.actionKind == .unavailable)
            }
        }
        .padding(24)
        .frame(width: 500, alignment: .leading)
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
            RoundedRectangle(cornerRadius: 8)
                .fill(Color(nsColor: .controlBackgroundColor))
        )
    }
}

struct PostUpdateWhatsNewSheet: View {
    let title: String
    let summary: String
    let onClose: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .center, spacing: 12) {
                Image(systemName: "checkmark.seal.fill")
                    .font(.system(size: 34, weight: .semibold))
                    .foregroundStyle(Color.green)

                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.title2.weight(.bold))

                    Text("KnowYou has been updated.")
                        .font(.headline)
                        .foregroundStyle(.secondary)
                }
            }

            Text(summary)
                .font(.body)
                .fixedSize(horizontal: false, vertical: true)
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color(nsColor: .textBackgroundColor))
                )

            HStack {
                Spacer()
                Button("Done", action: onClose)
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(24)
        .frame(width: 500, alignment: .leading)
    }
}
