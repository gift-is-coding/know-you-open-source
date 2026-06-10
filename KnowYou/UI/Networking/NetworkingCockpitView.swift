import SwiftUI

struct NetworkingCockpitView: View {
    let presentation: NetworkingCockpitPresentation

    @State private var selectedProfileID = "profile-jobs"
    @State private var selectedPlatformID = "knowyou-jobs"
    @State private var isEnabled = false

    private var selectedProfile: NetworkingGeneratedProfile {
        profiles.first { $0.id == selectedProfileID } ?? profiles[0]
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                header
                profileStrip
                selectedProfilePanel
                platformsPanel
                messagesPanel
            }
            .padding(28)
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .accessibilityIdentifier("networking-cockpit-native")
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 18) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Networking")
                    .font(.largeTitle.weight(.semibold))
                Text("App 开启后，KnowYou 用 My Wiki 生成 profile，再让本地 agent 通过 MCP 在两个 Know You 平台发帖和回复。")
                    .font(.body)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button {
                isEnabled.toggle()
            } label: {
                Label(isEnabled ? "已开启" : "开启", systemImage: isEnabled ? "checkmark.circle.fill" : "power")
            }
            .buttonStyle(.borderedProminent)
        }
    }

    private var profileStrip: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionTitle("Profile Generator", detail: "同一个人，不同场景面向。头像、场景和描述不同，姓名固定。")
            HStack(spacing: 14) {
                ForEach(profiles) { profile in
                    Button {
                        selectedProfileID = profile.id
                    } label: {
                        ProfileFaceCard(
                            profile: profile,
                            isSelected: profile.id == selectedProfileID
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var selectedProfilePanel: some View {
        NativePanel {
            VStack(alignment: .leading, spacing: 16) {
                HStack(alignment: .top, spacing: 16) {
                    ProfileAvatar(profile: selectedProfile, size: 56)
                    VStack(alignment: .leading, spacing: 5) {
                        Text(selectedProfile.personName)
                            .font(.title3.weight(.semibold))
                        Text(selectedProfile.label)
                            .font(.subheadline.weight(.medium))
                        Text(selectedProfile.scenarioDescription)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    StatusPill(text: "My Wiki + LLM", color: .green)
                    StatusPill(text: "human confirm", color: .gray)
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text("Prompt")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Text(selectedProfile.prompt)
                        .font(.callout)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(12)
                        .background(Color(nsColor: .textBackgroundColor))
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                }

                LazyVGrid(columns: [GridItem(.adaptive(minimum: 220), spacing: 12)], spacing: 12) {
                    ForEach(selectedProfile.summarySections) { section in
                        OutputSectionCard(section: section)
                    }
                }
            }
        }
    }

    private var platformsPanel: some View {
        NativePanel {
            VStack(alignment: .leading, spacing: 14) {
                sectionTitle("Platforms", detail: "V1 只做 Know You 自己的平台。每个平台绑定一个已确认 profile。")
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 280), spacing: 14)], spacing: 14) {
                    ForEach(platforms) { platform in
                        PlatformCard(
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
    }

    private var messagesPanel: some View {
        NativePanel {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    sectionTitle("Messages", detail: "来自不同平台的 highlights、入站、出站和 agent activity。私有理由只在本地。")
                    Spacer()
                    Picker("Platform", selection: $selectedPlatformID) {
                        ForEach(platforms) { platform in
                            Text(platform.name).tag(platform.id)
                        }
                    }
                    .labelsHidden()
                    .frame(width: 210)
                }

                LazyVGrid(columns: [GridItem(.adaptive(minimum: 260), spacing: 12)], spacing: 12) {
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
                title: "Founding engineer 帖子值得人工跟进",
                publicSummary: "Know You 求职上有人在找本地优先 agent 产品经验。",
                privateReason: "My Wiki 显示你最近在做 KnowYou Networking 和 agent runtime。",
                publicReferenceID: "post-jobs-1"
            ),
            NetworkingCockpitItem(
                id: "friends-inbound",
                direction: .inbound,
                title: "有人回复了认识新朋友 profile",
                publicSummary: "对方提到徒步、胶片和周末小范围活动。",
                privateReason: "兴趣和生活节奏匹配，原始证据留本地。",
                publicReferenceID: "comment-friends-1"
            ),
            NetworkingCockpitItem(
                id: "agent-activity",
                direction: .activity,
                title: "Agent 已用职业/求职 profile 评论",
                publicSummary: "AI 评论已标注为 林书涵 · 职业/求职 · AI。",
                privateReason: "通过本地 Networking MCP 和 agent token 写入。",
                publicReferenceID: "comment-agent-1"
            ),
        ]
    }

    private var profiles: [NetworkingGeneratedProfile] {
        [
            NetworkingGeneratedProfile(
                id: "profile-jobs",
                personName: "林书涵",
                displayName: "林书涵",
                label: "职业/求职",
                englishLabel: "Jobs",
                scenarioID: NetworkingProfileScenario.jobs.id,
                scenarioDescription: NetworkingProfileScenario.jobs.description,
                prompt: NetworkingProfileScenario.jobs.prompt,
                avatar: NetworkingProfileAvatar(fallbackLetter: "林", backgroundHex: "#C25A35", avatarSeed: "lin-shuhan-jobs"),
                summarySections: [
                    NetworkingProfileSummarySection(title: "正在做", body: "KnowYou Networking：用本地 My Wiki 和 agent runtime 连接求职、招聘和合作机会。"),
                    NetworkingProfileSummarySection(title: "能负责", body: "macOS SwiftUI、Next.js、Supabase、agent MCP、产品判断和用户访谈。"),
                    NetworkingProfileSummarySection(title: "适合场景", body: "求职、招人、finding collaborators、找 founding engineer / design engineer。"),
                ],
                autoUpdate: true,
                lastUpdatedLabel: "My Wiki 12 小时前",
                platformIDs: ["knowyou-jobs"]
            ),
            NetworkingGeneratedProfile(
                id: "profile-friends",
                personName: "林书涵",
                displayName: "林书涵",
                label: "认识新朋友",
                englishLabel: "Friends",
                scenarioID: NetworkingProfileScenario.friends.id,
                scenarioDescription: NetworkingProfileScenario.friends.description,
                prompt: NetworkingProfileScenario.friends.prompt,
                avatar: NetworkingProfileAvatar(fallbackLetter: "涵", backgroundHex: "#5E7C66", avatarSeed: "lin-shuhan-friends"),
                summarySections: [
                    NetworkingProfileSummarySection(title: "兴趣", body: "安静的小桌饭局、长时间散步、产品和 AI 之外的真实生活细节。"),
                    NetworkingProfileSummarySection(title: "社交方式", body: "喜欢具体、自然、能慢慢展开的对话，不追求高频社交。"),
                    NetworkingProfileSummarySection(title: "适合场景", body: "认识同城朋友、活动搭子、能认真聊天的人。"),
                ],
                autoUpdate: true,
                lastUpdatedLabel: "My Wiki 3 天前",
                platformIDs: ["knowyou-friends"]
            ),
        ]
    }

    private var platforms: [NetworkingPlatformConfiguration] {
        [
            NetworkingPlatformConfiguration(
                id: "knowyou-jobs",
                name: "Know You 求职",
                subtitle: "求职、招聘、合作机会",
                assignedProfileID: "profile-jobs",
                status: isEnabled ? .active : .paused,
                activity: NetworkingPlatformActivity(outbound: 3, inbound: 2, highlights: 4)
            ),
            NetworkingPlatformConfiguration(
                id: "knowyou-friends",
                name: "Know You 认识新朋友",
                subtitle: "兴趣、活动、轻社交",
                assignedProfileID: "profile-friends",
                status: isEnabled ? .active : .paused,
                activity: NetworkingPlatformActivity(outbound: 1, inbound: 3, highlights: 2)
            ),
        ]
    }

    private func sectionTitle(_ title: String, detail: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title.uppercased())
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.tertiary)
            Text(detail)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}

private struct NativePanel<Content: View>: View {
    let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        content
            .padding(18)
            .background(Color(nsColor: .controlBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(Color(nsColor: .separatorColor).opacity(0.55))
            )
    }
}

private struct ProfileFaceCard: View {
    let profile: NetworkingGeneratedProfile
    let isSelected: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                ProfileAvatar(profile: profile, size: 42)
                VStack(alignment: .leading, spacing: 2) {
                    Text(profile.personName)
                        .font(.headline)
                    Text(profile.label)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
            }
            Text(profile.scenarioDescription)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(2)
            HStack {
                StatusPill(text: "generated", color: .green)
                StatusPill(text: profile.autoUpdate ? "auto" : "manual", color: .gray)
            }
        }
        .frame(width: 248, alignment: .topLeading)
        .frame(minHeight: 124, alignment: .topLeading)
        .padding(14)
        .background(Color(nsColor: .textBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(isSelected ? Color.accentColor.opacity(0.7) : Color(nsColor: .separatorColor).opacity(0.55), lineWidth: isSelected ? 1.5 : 1)
        )
    }
}

private struct PlatformCard: View {
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
                    VStack(alignment: .leading, spacing: 2) {
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

                HStack(spacing: 10) {
                    ProfileAvatar(profile: profile, size: 32)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("绑定 profile")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        Text(profile.label)
                            .font(.caption.weight(.medium))
                    }
                    Spacer()
                    StatusPill(text: isEnabled ? "agent permitted" : "not enabled", color: isEnabled ? .green : .secondary)
                }

                HStack(spacing: 8) {
                    PlatformStat(title: "出站", value: platform.activity.outbound)
                    PlatformStat(title: "入站", value: platform.activity.inbound)
                    PlatformStat(title: "高亮", value: platform.activity.highlights)
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(nsColor: .textBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(isSelected ? Color.accentColor.opacity(0.7) : Color(nsColor: .separatorColor).opacity(0.45))
            )
        }
        .buttonStyle(.plain)
    }
}

private struct InboxCard: View {
    let item: NetworkingCockpitItem

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
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

private struct ProfileAvatar: View {
    let profile: NetworkingGeneratedProfile
    let size: CGFloat

    var body: some View {
        ZStack {
            Circle()
                .fill(Color(hex: profile.avatar.backgroundHex).opacity(0.92))
            Text(profile.avatar.displayLetter)
                .font(.system(size: size * 0.42, weight: .semibold))
                .foregroundStyle(.white)
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

private struct PlatformMark: View {
    let name: String

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(Color.accentColor.opacity(0.13))
            Text(String(name.prefix(1)))
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
