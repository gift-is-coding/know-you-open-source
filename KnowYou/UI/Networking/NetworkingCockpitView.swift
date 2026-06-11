import SwiftUI

struct NetworkingCockpitView: View {
    let presentation: NetworkingCockpitPresentation

    @State private var selectedProfileID = "profile-career"
    @State private var selectedPlatformID = "knowyou-careers"
    @State private var isEnabled = false

    private let activePersonName = "Tianfu Wu"

    private var selectedProfile: NetworkingGeneratedProfile {
        profiles.first { $0.id == selectedProfileID } ?? profiles[0]
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                header
                privacyNotice
                generateProfilesStep
                connectCommunitiesStep
                messagesStep
            }
            .padding(28)
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .accessibilityIdentifier("networking-cockpit-native")
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 18) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Networking")
                    .font(.largeTitle.weight(.semibold))
                Text("Turn your local My Wiki context into scene-specific profiles, connect them to Know You communities, and let your local agent bring back the moments worth your attention.")
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 18)

            VStack(alignment: .trailing, spacing: 10) {
                Button {
                    isEnabled.toggle()
                } label: {
                    Label(isEnabled ? "Networking enabled" : "Enable Networking", systemImage: isEnabled ? "checkmark.circle.fill" : "power")
                }
                .buttonStyle(.borderedProminent)

                HStack(spacing: 8) {
                    Text("Public display name")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(activePersonName)
                        .font(.caption.weight(.semibold))
                    Button("Edit") {}
                        .font(.caption)
                        .buttonStyle(.plain)
                }
            }
        }
    }

    private var privacyNotice: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "lock.shield")
                .font(.title3)
                .foregroundStyle(.green)
                .frame(width: 26)

            VStack(alignment: .leading, spacing: 4) {
                Text("Privacy and redaction")
                    .font(.headline)
                Text("Profiles are generated from local My Wiki context with sensitive details redacted. Raw evidence, private drafts, account details, and deep matching reasons stay on this Mac until you explicitly approve what becomes public.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(14)
        .background(Color.green.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(Color.green.opacity(0.22))
        )
    }

    private var generateProfilesStep: some View {
        StepPanel(
            index: 1,
            title: "Generate profiles",
            subtitle: "Choose a default scenario or create a custom one. The prompt stays behind the scenes; you review the generated result first."
        ) {
            VStack(alignment: .leading, spacing: 16) {
                HStack(alignment: .top, spacing: 12) {
                    ForEach(profiles) { profile in
                        Button {
                            selectedProfileID = profile.id
                        } label: {
                            ProfileScenarioCard(
                                profile: profile,
                                isSelected: profile.id == selectedProfileID
                            )
                        }
                        .buttonStyle(.plain)
                    }

                    Button {
                        selectedProfileID = "profile-custom"
                    } label: {
                        CustomScenarioCard(isSelected: selectedProfileID == "profile-custom")
                    }
                    .buttonStyle(.plain)
                }

                GeneratedResultPreview(profile: selectedProfile)
            }
        }
    }

    private var connectCommunitiesStep: some View {
        StepPanel(
            index: 2,
            title: "Connect communities",
            subtitle: "Each community uses one approved profile. You can change the profile before the local agent starts posting or replying."
        ) {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 320), spacing: 14)], spacing: 14) {
                ForEach(platforms) { platform in
                    CommunityBindingCard(
                        platform: platform,
                        profile: platform.assignedProfile(in: profiles) ?? profiles[0],
                        isSelected: platform.id == selectedPlatformID,
                        isEnabled: isEnabled
                    ) {
                        selectedPlatformID = platform.id
                    }
                }
            }
        }
    }

    private var messagesStep: some View {
        StepPanel(
            index: 3,
            title: "Review messages and leads",
            subtitle: "Highlights, inbound replies, outbound agent actions, and activity logs stay grouped by community. Human action remains the final step."
        ) {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Text("Community inbox")
                        .font(.headline)
                    Spacer()
                    Picker("Community", selection: $selectedPlatformID) {
                        ForEach(platforms) { platform in
                            Text(platform.name).tag(platform.id)
                        }
                    }
                    .labelsHidden()
                    .frame(width: 220)
                }

                LazyVGrid(columns: [GridItem(.adaptive(minimum: 270), spacing: 12)], spacing: 12) {
                    ForEach(filteredInboxItems) { item in
                        InboxCard(item: item)
                    }
                }
            }
        }
    }

    private var filteredInboxItems: [NetworkingCockpitItem] {
        let items = presentation.sections.flatMap(\.items)
        guard items.isEmpty == false else {
            return fallbackInboxItems
        }
        return items
    }

    private var fallbackInboxItems: [NetworkingCockpitItem] {
        [
            NetworkingCockpitItem(
                id: "jobs-highlight",
                direction: .highlight,
                title: "Worth reaching out",
                publicSummary: "A founder is looking for someone with local-first agent product experience in Know You Careers.",
                privateReason: "My Wiki connects this to current KnowYou Networking and agent runtime work.",
                publicReferenceID: "post-careers-1"
            ),
            NetworkingCockpitItem(
                id: "friends-inbound",
                direction: .inbound,
                title: "Inbound interaction",
                publicSummary: "Someone replied to the Friends profile with hiking, film photography, and small weekend gatherings.",
                privateReason: "Lifestyle overlap is high; source evidence stays local.",
                publicReferenceID: "comment-friends-1"
            ),
            NetworkingCockpitItem(
                id: "agent-activity",
                direction: .activity,
                title: "Agent replied",
                publicSummary: "The local agent posted a labeled AI comment as Tianfu Wu · Career / Hiring · AI.",
                privateReason: "Written through the local Networking MCP after activation and token permission.",
                publicReferenceID: "comment-agent-1"
            ),
        ]
    }

    private var profiles: [NetworkingGeneratedProfile] {
        [
            NetworkingGeneratedProfile(
                id: "profile-career",
                personName: activePersonName,
                displayName: activePersonName,
                label: "Career / Hiring",
                englishLabel: "Career",
                scenarioID: NetworkingProfileScenario.jobs.id,
                scenarioDescription: "For jobs, hiring, collaborators, and concrete work opportunities.",
                prompt: NetworkingProfileScenario.jobs.prompt,
                avatar: NetworkingProfileAvatar(fallbackLetter: "T", backgroundHex: "#C25A35", avatarSeed: "tianfu-career", avatarStyle: "generated-face"),
                summarySections: [
                    NetworkingProfileSummarySection(title: "Current focus", body: "Building KnowYou Networking: a local-context agent layer for profiles, hiring, collaboration, and public community interaction."),
                    NetworkingProfileSummarySection(title: "Can own", body: "macOS SwiftUI, Next.js, Supabase, MCP agent runtime, product judgment, and end-to-end shipping across app and web."),
                    NetworkingProfileSummarySection(title: "Best matches", body: "Founding engineering, design engineering, agent products, local-first AI systems, and people who want dense product context."),
                ],
                autoUpdate: true,
                lastUpdatedLabel: "Updated from My Wiki 12h ago",
                platformIDs: ["knowyou-careers"]
            ),
            NetworkingGeneratedProfile(
                id: "profile-friends",
                personName: activePersonName,
                displayName: activePersonName,
                label: "Friends / Social",
                englishLabel: "Friends",
                scenarioID: NetworkingProfileScenario.friends.id,
                scenarioDescription: "For meeting new friends through interests, activities, and everyday rhythm.",
                prompt: NetworkingProfileScenario.friends.prompt,
                avatar: NetworkingProfileAvatar(fallbackLetter: "T", backgroundHex: "#5E7C66", avatarSeed: "tianfu-friends", avatarStyle: "generated-face"),
                summarySections: [
                    NetworkingProfileSummarySection(title: "Interests", body: "Quiet dinners, long walks, films, thoughtful conversations, small activities, and real life outside product work."),
                    NetworkingProfileSummarySection(title: "Social rhythm", body: "Prefers specific, low-pressure conversations that can unfold naturally instead of high-frequency networking."),
                    NetworkingProfileSummarySection(title: "Best matches", body: "Local friends, activity partners, people who like building trust through small and concrete moments."),
                ],
                autoUpdate: true,
                lastUpdatedLabel: "Updated from My Wiki 3d ago",
                platformIDs: ["knowyou-friends"]
            ),
            NetworkingGeneratedProfile(
                id: "profile-custom",
                personName: activePersonName,
                displayName: activePersonName,
                label: "Custom scenario",
                englishLabel: "Custom",
                scenarioID: "custom",
                scenarioDescription: "Create a new scene by choosing goals and editing the hidden generation instruction.",
                prompt: "Custom prompt is configured behind the scenes.",
                avatar: NetworkingProfileAvatar(fallbackLetter: "T", backgroundHex: "#6E6A8E", avatarSeed: "tianfu-custom", avatarStyle: "generated-face"),
                summarySections: [
                    NetworkingProfileSummarySection(title: "Draft mode", body: "Pick a scene, adjust the hidden instruction, and generate a new public-facing profile from My Wiki."),
                    NetworkingProfileSummarySection(title: "Review first", body: "The generated summary stays private until you approve it for a community."),
                    NetworkingProfileSummarySection(title: "Good for", body: "Events, research collaborators, investor conversations, small communities, or any scene that needs a different face of the same person."),
                ],
                autoUpdate: false,
                lastUpdatedLabel: "Not generated yet",
                platformIDs: []
            ),
        ]
    }

    private var platforms: [NetworkingPlatformConfiguration] {
        [
            NetworkingPlatformConfiguration(
                id: "knowyou-careers",
                name: "Know You Careers",
                subtitle: "Jobs, hiring, collaborators",
                assignedProfileID: "profile-career",
                status: isEnabled ? .active : .paused,
                activity: NetworkingPlatformActivity(outbound: 3, inbound: 2, highlights: 4)
            ),
            NetworkingPlatformConfiguration(
                id: "knowyou-friends",
                name: "Know You Friends",
                subtitle: "Interests, activities, new friends",
                assignedProfileID: "profile-friends",
                status: isEnabled ? .active : .paused,
                activity: NetworkingPlatformActivity(outbound: 1, inbound: 3, highlights: 2)
            ),
        ]
    }
}

private struct StepPanel<Content: View>: View {
    let index: Int
    let title: String
    let subtitle: String
    let content: Content

    init(index: Int, title: String, subtitle: String, @ViewBuilder content: () -> Content) {
        self.index = index
        self.title = title
        self.subtitle = subtitle
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top, spacing: 12) {
                Text("\(index)")
                    .font(.headline.monospacedDigit())
                    .foregroundStyle(.white)
                    .frame(width: 30, height: 30)
                    .background(Circle().fill(Color.accentColor))

                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.title3.weight(.semibold))
                    Text(subtitle)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            content
        }
        .padding(18)
        .background(Color(nsColor: .controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(Color(nsColor: .separatorColor).opacity(0.55))
        )
    }
}

private struct ProfileScenarioCard: View {
    let profile: NetworkingGeneratedProfile
    let isSelected: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 10) {
                GeneratedFaceAvatar(avatar: profile.avatar, size: 48)
                Spacer()
                StatusPill(text: "default", color: .green)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(profile.label)
                    .font(.headline)
                Text(profile.scenarioDescription)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(3)
            }

            HStack(spacing: 6) {
                Image(systemName: "sparkles")
                    .font(.caption)
                Text(profile.lastUpdatedLabel ?? "Ready to generate")
                    .font(.caption2)
                    .lineLimit(1)
            }
            .foregroundStyle(.secondary)
        }
        .frame(width: 210, alignment: .topLeading)
        .frame(minHeight: 154, alignment: .topLeading)
        .padding(14)
        .background(Color(nsColor: .textBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(selectionStroke)
    }

    private var selectionStroke: some View {
        RoundedRectangle(cornerRadius: 8, style: .continuous)
            .stroke(isSelected ? Color.accentColor.opacity(0.78) : Color(nsColor: .separatorColor).opacity(0.5), lineWidth: isSelected ? 1.6 : 1)
    }
}

private struct CustomScenarioCard: View {
    let isSelected: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color.accentColor.opacity(0.12))
                    .frame(width: 48, height: 48)
                Image(systemName: "plus")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(Color.accentColor)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("Custom scenario")
                    .font(.headline)
                Text("Choose a scene, edit the hidden instruction, then generate a new profile from My Wiki.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(3)
            }

            StatusPill(text: "private draft", color: .gray)
        }
        .frame(width: 210, alignment: .topLeading)
        .frame(minHeight: 154, alignment: .topLeading)
        .padding(14)
        .background(Color(nsColor: .textBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(isSelected ? Color.accentColor.opacity(0.78) : Color(nsColor: .separatorColor).opacity(0.5), lineWidth: isSelected ? 1.6 : 1)
        )
    }
}

private struct GeneratedResultPreview: View {
    let profile: NetworkingGeneratedProfile

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 14) {
                GeneratedFaceAvatar(avatar: profile.avatar, size: 64)
                VStack(alignment: .leading, spacing: 5) {
                    Text("Generated result preview")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Text(profile.label)
                        .font(.title3.weight(.semibold))
                    Text(profile.scenarioDescription)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                StatusPill(text: "My Wiki + LLM", color: .green)
                StatusPill(text: "needs approval", color: .gray)
            }

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 220), spacing: 12)], spacing: 12) {
                ForEach(profile.summarySections) { section in
                    OutputSectionCard(section: section)
                }
            }
        }
        .padding(16)
        .background(Color(nsColor: .textBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(Color(nsColor: .separatorColor).opacity(0.45))
        )
    }
}

private struct CommunityBindingCard: View {
    let platform: NetworkingPlatformConfiguration
    let profile: NetworkingGeneratedProfile
    let isSelected: Bool
    let isEnabled: Bool
    let onSelect: () -> Void

    var body: some View {
        Button(action: onSelect) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .top, spacing: 10) {
                    PlatformMark(name: platform.name)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(platform.name)
                            .font(.headline)
                        Text(platform.subtitle)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    StatusBadge(status: platform.status)
                }

                Divider()

                HStack(alignment: .center, spacing: 10) {
                    GeneratedFaceAvatar(avatar: profile.avatar, size: 34)
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Matched profile")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        Text(profile.label)
                            .font(.caption.weight(.medium))
                    }
                    Spacer()
                    Button("Change") {}
                        .font(.caption)
                        .buttonStyle(.bordered)
                }

                HStack(spacing: 8) {
                    PlatformStat(title: "Outbound", value: platform.activity.outbound)
                    PlatformStat(title: "Inbound", value: platform.activity.inbound)
                    PlatformStat(title: "Highlights", value: platform.activity.highlights)
                }

                Text(isEnabled ? "Agent posting is permitted through local MCP." : "Enable Networking before the agent can post or reply.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(nsColor: .textBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(isSelected ? Color.accentColor.opacity(0.75) : Color(nsColor: .separatorColor).opacity(0.45), lineWidth: isSelected ? 1.5 : 1)
            )
        }
        .buttonStyle(.plain)
    }
}

private struct InboxCard: View {
    let item: NetworkingCockpitItem

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(spacing: 8) {
                Circle()
                    .fill(directionColor)
                    .frame(width: 7, height: 7)
                Text(directionLabel)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer()
            }
            Text(item.title)
                .font(.headline)
            Text(item.publicSummary)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            if let publicReferenceID = item.publicReferenceID {
                Text(publicReferenceID)
                    .font(.caption2.monospaced())
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(14)
        .background(Color(nsColor: .textBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(Color(nsColor: .separatorColor).opacity(0.45))
        )
    }

    private var directionLabel: String {
        switch item.direction {
        case .highlight: return "Highlight"
        case .inbound: return "Inbound"
        case .outbound: return "Outbound"
        case .activity: return "Activity"
        }
    }

    private var directionColor: Color {
        switch item.direction {
        case .highlight: return .yellow
        case .inbound: return .blue
        case .outbound: return .orange
        case .activity: return .green
        }
    }
}

private struct GeneratedFaceAvatar: View {
    let avatar: NetworkingProfileAvatar
    let size: CGFloat

    private var baseColor: Color {
        Color(hex: avatar.backgroundHex)
    }

    private var skinColor: Color {
        [Color(red: 0.92, green: 0.72, blue: 0.56), Color(red: 0.78, green: 0.58, blue: 0.44), Color(red: 0.96, green: 0.80, blue: 0.66)][seedValue(modulo: 3)]
    }

    private var hairColor: Color {
        [Color(red: 0.18, green: 0.14, blue: 0.12), Color(red: 0.30, green: 0.22, blue: 0.16), Color(red: 0.12, green: 0.18, blue: 0.20)][seedValue(modulo: 3, offset: 7)]
    }

    var body: some View {
        ZStack {
            Circle()
                .fill(baseColor.opacity(0.92))

            Circle()
                .fill(skinColor)
                .frame(width: size * 0.56, height: size * 0.60)
                .offset(y: size * 0.08)

            Capsule()
                .fill(hairColor)
                .frame(width: size * 0.48, height: size * 0.23)
                .offset(y: -size * 0.17)

            HStack(spacing: size * 0.14) {
                Circle().fill(Color.black.opacity(0.72))
                Circle().fill(Color.black.opacity(0.72))
            }
            .frame(width: size * 0.28, height: size * 0.05)
            .offset(y: size * 0.03)

            Capsule()
                .fill(Color.black.opacity(0.34))
                .frame(width: size * 0.17, height: size * 0.035)
                .offset(y: size * 0.18)
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }

    private func seedValue(modulo: Int, offset: Int = 0) -> Int {
        let scalars = Array(avatar.avatarSeed.unicodeScalars)
        let total = scalars.enumerated().reduce(offset) { partial, pair in
            partial + Int(pair.element.value) * (pair.offset + 1)
        }
        return abs(total) % modulo
    }
}

private struct PlatformMark: View {
    let name: String

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(Color.accentColor.opacity(0.13))
            Image(systemName: name.contains("Friends") ? "person.2" : "briefcase")
                .font(.headline.weight(.semibold))
                .foregroundStyle(Color.accentColor)
        }
        .frame(width: 34, height: 34)
    }
}

private struct StatusBadge: View {
    let status: NetworkingPlatformStatus

    var body: some View {
        StatusPill(text: title, color: color)
    }

    private var title: String {
        switch status {
        case .active: return "enabled"
        case .paused: return "paused"
        case .disconnected: return "setup"
        }
    }

    private var color: Color {
        switch status {
        case .active: return .green
        case .paused: return .gray
        case .disconnected: return .orange
        }
    }
}

private struct StatusPill: View {
    let text: String
    let color: Color

    var body: some View {
        Text(text)
            .font(.caption2.weight(.semibold))
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(color.opacity(0.12))
            .foregroundStyle(color)
            .clipShape(Capsule())
    }
}

private struct PlatformStat: View {
    let title: String
    let value: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("\(value)")
                .font(.headline.monospacedDigit())
            Text(title)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(8)
        .background(Color(nsColor: .controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
    }
}

private struct OutputSectionCard: View {
    let section: NetworkingProfileSummarySection

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(section.title)
                .font(.caption.weight(.semibold))
            Text(section.body)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(12)
        .background(Color(nsColor: .controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}

private extension Color {
    init(hex: String) {
        let cleaned = hex.trimmingCharacters(in: CharacterSet(charactersIn: "#"))
        let value = Int(cleaned, radix: 16) ?? 0x888888
        let red = Double((value >> 16) & 0xff) / 255
        let green = Double((value >> 8) & 0xff) / 255
        let blue = Double(value & 0xff) / 255
        self.init(red: red, green: green, blue: blue)
    }
}
