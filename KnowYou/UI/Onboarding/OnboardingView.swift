import SwiftUI
import AppKit

struct OnboardingView: View {
    @Environment(AppState.self) private var appState
    let onComplete: () -> Void

    @State private var step: OnboardingStep = .intro
    @State private var vaultPath: String = (try? AppState.defaultVaultURL().path) ?? ""

    var body: some View {
        VStack(spacing: 0) {
            progressDots
                .padding(.top, 28)
                .padding(.horizontal, 32)

            Group {
                switch step {
                case .intro:
                    introScene
                case .capture:
                    captureScene
                case .safety:
                    safetyScene
                case .preview:
                    previewScene
                case .permissions:
                    permissionsScene
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .padding(.horizontal, 32)
            .padding(.top, 20)

            navigationBar
                .padding(.horizontal, 32)
                .padding(.bottom, 28)
        }
        .frame(width: 640, height: 620)
        .background(
            LinearGradient(
                colors: [
                    Color(nsColor: .windowBackgroundColor),
                    Color.accentColor.opacity(0.08)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
    }

    private var currentContent: OnboardingStepContent {
        OnboardingContent.content(for: step)
    }

    private var progressDots: some View {
        HStack(spacing: 10) {
            ForEach(OnboardingStep.storyFlow, id: \.self) { candidate in
                Capsule(style: .continuous)
                    .fill(progressColor(for: candidate))
                    .frame(width: candidate == step ? 26 : 8, height: 8)
                    .animation(.easeInOut(duration: 0.2), value: step)
            }
        }
    }

    private var navigationBar: some View {
        HStack {
            if !step.isFirst {
                Button("Back") { goBack() }
                    .buttonStyle(.plain)
            }

            Spacer()

            Button(currentContent.primaryCTA) {
                if step.isLast {
                    finish()
                } else {
                    advance()
                }
            }
            .buttonStyle(.borderedProminent)
        }
    }

    private var introScene: some View {
        let content = currentContent

        return VStack(alignment: .leading, spacing: 24) {
            storyHeader(
                systemImage: "book.pages.fill",
                title: content.title,
                body: content.body,
                caption: content.caption
            )

            VStack(alignment: .leading, spacing: 16) {
                Label("Local-first, from the first screen", systemImage: "internaldrive.fill")
                    .font(.headline)

                Text("Know You writes a day-by-day diary in Markdown and keeps the source trail close by, so you can trust what the story says and where it came from.")
                    .foregroundStyle(.secondary)

                HStack(spacing: 12) {
                    introTrustCard(
                        title: "Stays on this Mac",
                        detail: "Your notes live in your vault, not a default cloud."
                    )
                    introTrustCard(
                        title: "Readable forever",
                        detail: "Every day is plain Markdown you can inspect anytime."
                    )
                }
            }
            .padding(22)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        }
    }

    private var captureScene: some View {
        let content = currentContent
        let timelineTimes = ["8:10 AM", "1:45 PM", "10:18 PM"]

        return VStack(alignment: .leading, spacing: 24) {
            storyHeader(
                systemImage: "sparkles.rectangle.stack.fill",
                title: content.title,
                body: content.body,
                caption: content.caption
            )

            VStack(alignment: .leading, spacing: 16) {
                ForEach(Array(content.bullets.enumerated()), id: \.offset) { index, bullet in
                    captureMomentRow(
                        time: timelineTimes[index],
                        title: bullet
                    )
                }
            }
            .padding(22)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        }
    }

    private var safetyScene: some View {
        let content = currentContent

        return VStack(alignment: .leading, spacing: 24) {
            storyHeader(
                systemImage: "lock.shield.fill",
                title: content.title,
                body: content.body,
                caption: content.caption
            )

            VStack(alignment: .leading, spacing: 12) {
                ForEach(content.bullets, id: \.self) { bullet in
                    HStack(alignment: .top, spacing: 12) {
                        Image(systemName: "checkmark.shield.fill")
                            .foregroundStyle(Color.accentColor)
                            .frame(width: 20)

                        Text(bullet)
                            .font(.body)
                    }
                }

                Text("Nothing in first-run setup depends on enabling a summarizer. The critical path is your vault, your permissions, and your first story.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .padding(.top, 8)
            }
            .padding(22)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        }
    }

    private var previewScene: some View {
        let content = currentContent

        return VStack(alignment: .leading, spacing: 24) {
            storyHeader(
                systemImage: "text.book.closed.fill",
                title: content.title,
                body: content.body,
                caption: content.caption
            )

            diaryPreviewCard(content: content)
        }
    }

    private var permissionsScene: some View {
        let content = currentContent
        let notificationsAvailable = appState.environment?.notificationReader.isAvailable == true

        return VStack(alignment: .leading, spacing: 24) {
            storyHeader(
                systemImage: "checkmark.circle.badge.shield.checkmark.fill",
                title: content.title,
                body: content.body,
                caption: content.caption
            )

            VStack(alignment: .leading, spacing: 18) {
                vaultChooser

                Divider()

                PermissionRow(
                    icon: "doc.on.clipboard",
                    title: "Clipboard",
                    detail: "No permission required. Know You reads your clipboard automatically.",
                    ok: true
                )
                PermissionRow(
                    icon: "bell.badge",
                    title: "Notifications (Full Disk Access)",
                    detail: notificationsAvailable
                        ? "Full Disk Access detected. Notifications can be imported into the story."
                        : "To import notifications, grant Full Disk Access: System Settings → Privacy & Security → Full Disk Access → add Know You.",
                    ok: notificationsAvailable
                )
            }
            .padding(22)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        }
    }

    private var vaultChooser: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Vault location")
                .font(.headline)

            Text("Choose where your daily Markdown files should live.")
                .font(.callout)
                .foregroundStyle(.secondary)

            HStack(spacing: 12) {
                Text(vaultPath)
                    .font(.system(.body, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)

                Spacer(minLength: 12)

                Button("Choose…") { chooseVaultFolder() }
            }
            .padding(14)
            .background(Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
    }

    private func storyHeader(systemImage: String, title: String, body: String, caption: String) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Image(systemName: systemImage)
                .font(.system(size: 34, weight: .semibold))
                .foregroundStyle(Color.accentColor)

            Text(title)
                .font(.system(size: 31, weight: .semibold, design: .rounded))

            Text(body)
                .font(.title3)
                .foregroundStyle(.primary)

            Text(caption)
                .font(.callout)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func introTrustCard(title: String, detail: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.headline)

            Text(detail)
                .font(.callout)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private func captureMomentRow(time: String, title: String) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Text(time)
                .font(.caption.monospacedDigit().weight(.semibold))
                .foregroundStyle(.secondary)
                .frame(width: 62, alignment: .leading)

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.body.weight(.medium))

                Text("Know You keeps the nearby source context so the finished diary still feels grounded in the actual day.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(14)
        .background(Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private func diaryPreviewCard(content: OnboardingStepContent) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            if let preview = content.preview {
                Text(preview.title)
                    .font(.headline)

                ForEach(Array(preview.entries.enumerated()), id: \.offset) { _, entry in
                    VStack(alignment: .leading, spacing: 10) {
                        HStack(alignment: .firstTextBaseline) {
                            Text(entry.time)
                                .font(.caption.monospacedDigit().weight(.semibold))
                                .foregroundStyle(.secondary)

                            Spacer()

                            Text("Sources nearby")
                                .font(.caption.weight(.medium))
                                .foregroundStyle(.secondary)
                        }

                        Text(entry.paragraph)
                            .font(.body)
                            .lineSpacing(3)

                        HStack(spacing: 8) {
                            ForEach(entry.sources, id: \.self) { source in
                                Text(source)
                                    .font(.caption.weight(.medium))
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 6)
                                    .background(Color.accentColor.opacity(0.12), in: Capsule(style: .continuous))
                            }
                        }
                    }
                    .padding(16)
                    .background(Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                }
            }
        }
        .padding(22)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
    }

    private func progressColor(for candidate: OnboardingStep) -> Color {
        if candidate == step {
            return .accentColor
        }

        if isCompleted(candidate) {
            return Color.accentColor.opacity(0.35)
        }

        return Color.secondary.opacity(0.22)
    }

    private func advance() {
        guard let next = step.next else { return }
        step = next
    }

    private func goBack() {
        guard let previous = step.previous else { return }
        step = previous
    }

    private func isCompleted(_ candidate: OnboardingStep) -> Bool {
        guard let candidateIndex = OnboardingStep.storyFlow.firstIndex(of: candidate),
              let stepIndex = OnboardingStep.storyFlow.firstIndex(of: step) else {
            return false
        }

        return candidateIndex < stepIndex
    }

    private func chooseVaultFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.prompt = "Select Vault Folder"
        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            vaultPath = url.path
        }
    }

    private func finish() {
        let vaultURL = URL(fileURLWithPath: vaultPath, isDirectory: true)
        appState.applyVaultURL(vaultURL)
        UserDefaults.standard.set(true, forKey: AppState.UserDefaultsKeys.hasCompletedOnboarding)
        onComplete()
    }
}

private struct PermissionRow: View {
    let icon: String
    let title: String
    let detail: String
    let ok: Bool

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: ok ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                .foregroundStyle(ok ? .green : .orange)
                .frame(width: 20)
            VStack(alignment: .leading, spacing: 4) {
                Label(title, systemImage: icon)
                    .fontWeight(.medium)
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}
