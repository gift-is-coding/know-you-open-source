import SwiftUI

struct NetworkingCockpitView: View {
    let presentation: NetworkingCockpitPresentation
    let projectRoot: URL?
    let summarizer: (any SummaryGenerating)?

    @State private var selectedProfileID = "profile-career"
    @State private var selectedPlatformID = "knowyou-careers"
    @State private var activationStatus: NetworkingActivationViewStatus = .pending
    @State private var generatedDrafts: [String: NetworkingProfileDraft] = [:]
    @State private var generationStatus: NetworkingGenerationStatus = .idle
    @State private var approvedProfileIDs: Set<String> = []
    @State private var attemptedAutoGenerationProfileIDs: Set<String> = []
    @State private var customUseCase = ""
    @State private var customImageDirection = ""
    @State private var customTone = "warm"
    @State private var customRedactionNotes = ""

    private let activePersonName = "Tianfu Wu"
    private let profileGenerationTimeoutNanoseconds: UInt64 = 45_000_000_000

    private var selectedProfile: NetworkingGeneratedProfile {
        profiles.first { $0.id == selectedProfileID } ?? profiles[0]
    }

    private var selectedPlatform: NetworkingPlatformConfiguration {
        platforms.first { $0.id == selectedPlatformID } ?? platforms[0]
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                header
                privacyNotice
                generateProfilesStep
                communitiesAndMessagesStep
            }
            .padding(.horizontal, 28)
            .padding(.bottom, 28)
        }
        .safeAreaInset(edge: .top) {
            Color.clear.frame(height: 18)
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .accessibilityIdentifier("networking-cockpit-native")
        .task {
            ensureActivationState()
            loadApprovalState()
            autoGenerateSelectedProfileIfNeeded()
        }
        .onChange(of: selectedProfileID) { _, _ in
            autoGenerateSelectedProfileIfNeeded()
        }
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 18) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Networking")
                    .font(.largeTitle.weight(.semibold))
                Text("Create public-facing profiles from local My Wiki context, approve what can be shared, then let your local agent work inside selected Know You communities.")
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 18)

            VStack(alignment: .trailing, spacing: 10) {
                StatusPill(text: activationStatus.title, color: activationStatus.color)

                if let message = activationStatus.message {
                    Text(message)
                        .font(.caption2)
                        .foregroundStyle(activationStatus.isFailure ? .red : .secondary)
                        .multilineTextAlignment(.trailing)
                        .frame(maxWidth: 260, alignment: .trailing)
                        .fixedSize(horizontal: false, vertical: true)
                }

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
                Text("Profiles are generated from local My Wiki context with sensitive details redacted. Contact info, account handles, exact locations, private relationships, health or finance details, raw diary or notification text, tokens, deep matching reasons, and unconfirmed claims stay private unless you rewrite and approve them.")
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
            subtitle: "Choose a default scenario or create a custom one. Default profiles start from a hidden prompt plus My Wiki; custom profiles use the fields below to shape that prompt."
        ) {
            VStack(alignment: .leading, spacing: 16) {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(alignment: .top, spacing: 12) {
                        ForEach(profiles) { profile in
                            Button {
                                selectedProfileID = profile.id
                            } label: {
                                ProfileScenarioCard(
                                    profile: profile,
                                    isSelected: profile.id == selectedProfileID,
                                    isApproved: approvedProfileIDs.contains(profile.id),
                                    hasDraft: generatedDrafts[profile.id] != nil
                                )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.vertical, 2)
                }

                if selectedProfileID == "profile-custom" {
                    CustomProfileEditor(
                        useCase: $customUseCase,
                        imageDirection: $customImageDirection,
                        tone: $customTone,
                        redactionNotes: $customRedactionNotes,
                        redactionItems: Self.defaultRedactionItems,
                        onGenerate: {
                            generateSelectedProfile()
                        },
                        isGenerating: generationStatus.isGenerating
                    )
                }

                HStack(alignment: .top, spacing: 12) {
                    Button {
                        generateSelectedProfile()
                    } label: {
                        Label(
                            generationStatus.isGenerating ? "Generating..." : refreshButtonTitle,
                            systemImage: generationStatus.isGenerating ? "hourglass" : "arrow.triangle.2.circlepath"
                        )
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(generationStatus.isGenerating)

                    GenerationStatusCard(
                        status: generationStatus,
                        onRetry: {
                            generateSelectedProfile()
                        }
                    )
                }

                GeneratedResultPreview(
                    profile: selectedProfile,
                    draft: generatedDrafts[selectedProfile.id],
                    isApproved: approvedProfileIDs.contains(selectedProfile.id),
                    isGenerating: generationStatus.isGenerating,
                    onApprove: approveSelectedProfile,
                    onRegenerate: generateSelectedProfile
                )
            }
        }
    }

    private var communitiesAndMessagesStep: some View {
        StepPanel(
            index: 2,
            title: "Communities and messages",
            subtitle: "Each community is linked to one approved profile. Choose a community above and the inbox below follows that source."
        ) {
            VStack(alignment: .leading, spacing: 16) {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 320), spacing: 14)], spacing: 14) {
                    ForEach(platforms) { platform in
                        let profile = platform.assignedProfile(in: profiles) ?? profiles[0]
                        CommunityBindingCard(
                            platform: platform,
                            profile: profile,
                            isSelected: platform.id == selectedPlatformID,
                            isAgentReady: activationStatus.isReady,
                            isProfileApproved: approvedProfileIDs.contains(profile.id)
                        ) {
                            selectedPlatformID = platform.id
                        }
                    }
                }

                SelectedCommunityDetail(
                    platform: selectedPlatform,
                    profile: selectedPlatform.assignedProfile(in: profiles) ?? profiles[0],
                    isAgentReady: activationStatus.isReady,
                    isProfileApproved: approvedProfileIDs.contains(selectedPlatform.assignedProfileID),
                    items: filteredInboxItems
                )
            }
        }
    }

    private var refreshButtonTitle: String {
        selectedProfileID == "profile-custom" ? "Generate custom profile" : "Refresh from My Wiki"
    }

    private var filteredInboxItems: [NetworkingCockpitItem] {
        let items = presentation.items(forPlatformID: selectedPlatformID)
        guard items.isEmpty == false else {
            return fallbackInboxItems.filter { item in
                item.platformID == selectedPlatformID
            }
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
                publicReferenceID: "post-careers-1",
                platformID: "knowyou-careers"
            ),
            NetworkingCockpitItem(
                id: "jobs-activity",
                direction: .activity,
                title: "Agent prepared a reply",
                publicSummary: "The local agent drafted a labeled AI comment as Tianfu Wu · Career / Hiring · AI.",
                privateReason: "Written through the local Networking MCP after activation and token permission.",
                publicReferenceID: "comment-agent-1",
                platformID: "knowyou-careers"
            ),
            NetworkingCockpitItem(
                id: "friends-inbound",
                direction: .inbound,
                title: "Inbound interaction",
                publicSummary: "Someone replied to the Friends profile with hiking, film photography, and small weekend gatherings.",
                privateReason: "Lifestyle overlap is high; source evidence stays local.",
                publicReferenceID: "comment-friends-1",
                platformID: "knowyou-friends"
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
                prompt: "Summarize work, projects, hiring needs, and collaboration context from My Wiki.",
                avatar: NetworkingProfileAvatar(fallbackLetter: "T", backgroundHex: "#3E6C68", avatarSeed: "tianfu-career-clean-professional", avatarStyle: "generated-face"),
                summarySections: [
                    NetworkingProfileSummarySection(title: "Draft not generated", body: "Open this profile to generate a fresh draft from My Wiki before approval."),
                    NetworkingProfileSummarySection(title: "Expected shape", body: "Work focus, projects you can own, hiring or job-search signals, and concrete collaboration preferences."),
                    NetworkingProfileSummarySection(title: "Redaction", body: "Contact details, account handles, exact locations, private evidence, and uncertain claims are removed by default."),
                ],
                autoUpdate: true,
                lastUpdatedLabel: "Draft not generated",
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
                prompt: "Summarize social interests, activities, personality, and meeting preferences from My Wiki.",
                avatar: NetworkingProfileAvatar(fallbackLetter: "T", backgroundHex: "#6D6FA6", avatarSeed: "tianfu-friends-soft-social", avatarStyle: "generated-face"),
                summarySections: [
                    NetworkingProfileSummarySection(title: "Draft not generated", body: "Open this profile to generate a fresh draft from My Wiki before approval."),
                    NetworkingProfileSummarySection(title: "Expected shape", body: "Interests, activities, social rhythm, and what kind of everyday friendship context is welcome."),
                    NetworkingProfileSummarySection(title: "Redaction", body: "Private relationships, exact locations, raw diary text, and sensitive life details stay local."),
                ],
                autoUpdate: true,
                lastUpdatedLabel: "Draft not generated",
                platformIDs: ["knowyou-friends"]
            ),
            NetworkingGeneratedProfile(
                id: "profile-custom",
                personName: activePersonName,
                displayName: activePersonName,
                label: "Custom profile",
                englishLabel: "Custom",
                scenarioID: "custom",
                scenarioDescription: customUseCase.isEmpty ? "Create a scene-specific public profile with custom goals, image direction, tone, and redaction notes." : customUseCase,
                prompt: customProfilePrompt,
                avatar: NetworkingProfileAvatar(
                    fallbackLetter: "T",
                    backgroundHex: customImageDirection.isEmpty ? "#8A6B5F" : "#6B7C8D",
                    avatarSeed: "tianfu-custom-\(customImageDirection)-\(customTone)",
                    avatarStyle: "generated-face"
                ),
                summarySections: [
                    NetworkingProfileSummarySection(title: "Draft not generated", body: "Fill the custom fields, then generate from My Wiki."),
                    NetworkingProfileSummarySection(title: "Use case", body: customUseCase.isEmpty ? "A user-defined scene such as events, research collaborators, investors, or small communities." : customUseCase),
                    NetworkingProfileSummarySection(title: "Public tone", body: customTone.capitalized),
                ],
                autoUpdate: false,
                lastUpdatedLabel: "Draft not generated",
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
                status: communityStatus(for: "profile-career"),
                activity: NetworkingPlatformActivity(outbound: 3, inbound: 2, highlights: 4)
            ),
            NetworkingPlatformConfiguration(
                id: "knowyou-friends",
                name: "Find Your Friends",
                subtitle: "Interests, activities, new friends",
                assignedProfileID: "profile-friends",
                status: communityStatus(for: "profile-friends"),
                activity: NetworkingPlatformActivity(outbound: 1, inbound: 3, highlights: 2)
            ),
        ]
    }

    private var customProfilePrompt: String {
        """
        Generate a public networking profile from local My Wiki context.
        Use case: \(customUseCase.isEmpty ? "User-defined networking scene." : customUseCase)
        Profile image direction: \(customImageDirection.isEmpty ? "Scene-appropriate, recognizable, and not overly literal." : customImageDirection)
        Public tone: \(customTone)
        Redaction notes: \(customRedactionNotes.isEmpty ? "Apply the default redaction rules." : customRedactionNotes)
        Default redaction rules: \(Self.defaultRedactionItems.joined(separator: ", "))
        """
    }

    private func communityStatus(for profileID: String) -> NetworkingPlatformStatus {
        guard activationStatus.isReady else { return .paused }
        return approvedProfileIDs.contains(profileID) ? .active : .paused
    }

    private func ensureActivationState() {
        guard let projectRoot else {
            activationStatus = .failed("My Wiki project is not ready yet.")
            return
        }

        let store = NetworkingActivationStateStore()
        if let state = store.load(projectRoot: projectRoot), state.isEnabled {
            activationStatus = .ready
            return
        }

        let safePersonID = activePersonName
            .lowercased()
            .replacingOccurrences(of: " ", with: "-")
        let state = NetworkingActivationState(
            isEnabled: true,
            personID: "local-\(safePersonID)",
            agentTokenPlaintext: "knw_agent_local_\(UUID().uuidString.replacingOccurrences(of: "-", with: "").lowercased())",
            supabaseURL: URL(string: "https://local.knowyou.invalid")!,
            publishableKey: "local-dev"
        )

        do {
            try store.save(state, projectRoot: projectRoot)
            activationStatus = .ready
        } catch {
            activationStatus = .failed("Could not prepare local agent permission: \(error.localizedDescription)")
        }
    }

    private func loadApprovalState() {
        guard let projectRoot else { return }
        approvedProfileIDs = NetworkingProfileApprovalStateStore()
            .load(projectRoot: projectRoot)
            .approvedProfileIDs
    }

    private func autoGenerateSelectedProfileIfNeeded() {
        guard generatedDrafts[selectedProfileID] == nil,
              attemptedAutoGenerationProfileIDs.contains(selectedProfileID) == false,
              generationStatus.isGenerating == false else {
            return
        }
        attemptedAutoGenerationProfileIDs.insert(selectedProfileID)
        generateSelectedProfile()
    }

    private func approveSelectedProfile() {
        guard let projectRoot,
              generatedDrafts[selectedProfile.id] != nil else {
            return
        }
        let nextState = NetworkingProfileApprovalState(approvedProfileIDs: approvedProfileIDs)
            .approving(selectedProfile.id)
        do {
            try NetworkingProfileApprovalStateStore().save(nextState, projectRoot: projectRoot)
            approvedProfileIDs = nextState.approvedProfileIDs
        } catch {
            activationStatus = .failed("Could not save profile approval: \(error.localizedDescription)")
        }
    }

    private func generateSelectedProfile() {
        guard let projectRoot else {
            generationStatus = .failed("My Wiki project is not ready yet.")
            return
        }
        guard let summarizer else {
            generationStatus = .failed("Select a Diary Engine before generating a real profile.")
            return
        }

        let profile = selectedProfile
        let scenario = scenario(for: profile)
        generationStatus = .generating(profile.id)

        Task {
            do {
                let service = NetworkingProfileGenerationService(
                    generator: NetworkingPromptProfileGenerator(summarizer: summarizer)
                )
                let draft = try await withProfileGenerationTimeout {
                    try await service.generateDraft(
                        scenario: scenario,
                        prompt: scenario.prompt,
                        personName: activePersonName,
                        projectRoot: projectRoot
                    )
                }
                await MainActor.run {
                    generatedDrafts[profile.id] = draft
                    generationStatus = .succeeded("Generated from My Wiki. Review and approve this draft before community automation can use it.")
                }
            } catch {
                await MainActor.run {
                    generationStatus = .failed(error.localizedDescription)
                }
            }
        }
    }

    private func withProfileGenerationTimeout<T: Sendable>(
        operation: @escaping @Sendable () async throws -> T
    ) async throws -> T {
        try await withThrowingTaskGroup(of: T.self) { group in
            group.addTask {
                try await operation()
            }
            group.addTask {
                try await Task.sleep(nanoseconds: profileGenerationTimeoutNanoseconds)
                throw NetworkingProfileGenerationError.llmFailed("Generation timed out. Try again after checking your Diary Engine.")
            }

            let result = try await group.next()!
            group.cancelAll()
            return result
        }
    }

    private func scenario(for profile: NetworkingGeneratedProfile) -> NetworkingProfileScenario {
        switch profile.id {
        case "profile-career":
            return .jobs
        case "profile-friends":
            return .friends
        default:
            return NetworkingProfileScenario(
                id: "custom",
                label: "Custom profile",
                prompt: customProfilePrompt,
                platformID: "",
                description: "A user-defined scene for KnowYou Networking."
            )
        }
    }

    private static let defaultRedactionItems = [
        "contact info",
        "account handles",
        "exact locations",
        "private relationships",
        "health/finance",
        "raw diary/notifications",
        "tokens/account details",
        "deep matching reasons",
        "unconfirmed claims",
    ]
}

private enum NetworkingActivationViewStatus: Equatable {
    case pending
    case ready
    case failed(String)

    var title: String {
        switch self {
        case .pending:
            return "Preparing agent"
        case .ready:
            return "Agent ready locally"
        case .failed:
            return "Agent needs attention"
        }
    }

    var message: String? {
        switch self {
        case .pending:
            return "Preparing local permission for this My Wiki project."
        case .ready:
            return nil
        case let .failed(message):
            return message
        }
    }

    var color: Color {
        switch self {
        case .pending:
            return .orange
        case .ready:
            return .green
        case .failed:
            return .red
        }
    }

    var isReady: Bool {
        if case .ready = self { return true }
        return false
    }

    var isFailure: Bool {
        if case .failed = self { return true }
        return false
    }
}

private enum NetworkingGenerationStatus: Equatable {
    case idle
    case generating(String)
    case succeeded(String)
    case failed(String)

    var isGenerating: Bool {
        if case .generating = self { return true }
        return false
    }

    var isFailure: Bool {
        if case .failed = self { return true }
        return false
    }

    var message: String? {
        switch self {
        case .idle:
            return nil
        case .generating:
            return "Reading My Wiki and asking your configured LLM to draft this profile."
        case let .succeeded(message), let .failed(message):
            return message
        }
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
    let isApproved: Bool
    let hasDraft: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 10) {
                GeneratedFaceAvatar(avatar: profile.avatar, size: 56)
                Spacer()
                StatusPill(text: statusTitle, color: statusColor)
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
                Text(profile.lastUpdatedLabel ?? "Draft not generated")
                    .font(.caption2)
                    .lineLimit(1)
            }
            .foregroundStyle(.secondary)
        }
        .frame(width: 246, alignment: .topLeading)
        .frame(minHeight: 174, alignment: .topLeading)
        .padding(14)
        .background(Color(nsColor: .textBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(selectionStroke)
    }

    private var statusTitle: String {
        if isApproved { return "Approved" }
        if hasDraft { return "Needs approval" }
        return profile.autoUpdate ? "default" : "custom"
    }

    private var statusColor: Color {
        if isApproved { return .green }
        if hasDraft { return .orange }
        return profile.autoUpdate ? .blue : .gray
    }

    private var selectionStroke: some View {
        RoundedRectangle(cornerRadius: 8, style: .continuous)
            .stroke(isSelected ? Color.accentColor.opacity(0.78) : Color(nsColor: .separatorColor).opacity(0.5), lineWidth: isSelected ? 1.6 : 1)
    }
}

private struct CustomProfileEditor: View {
    @Binding var useCase: String
    @Binding var imageDirection: String
    @Binding var tone: String
    @Binding var redactionNotes: String

    let redactionItems: [String]
    let onGenerate: () -> Void
    let isGenerating: Bool

    private let toneOptions = ["concise", "warm", "professional", "playful"]

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "slider.horizontal.3")
                    .foregroundStyle(Color.accentColor)
                    .frame(width: 22)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Custom profile")
                        .font(.headline)
                    Text("Describe the public scene and the profile image direction. KnowYou will combine this with My Wiki and default redaction rules.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 260), spacing: 14)], spacing: 14) {
                LabeledTextEditor(title: "Use case", text: $useCase, placeholder: "Example: meet design-minded founders at small AI product events.")
                LabeledTextEditor(title: "Profile image direction", text: $imageDirection, placeholder: "Example: thoughtful product builder, calm, approachable, crisp.")
                LabeledTextEditor(title: "Redaction notes", text: $redactionNotes, placeholder: "Anything extra that should never appear publicly.")
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("Public tone")
                    .font(.caption.weight(.semibold))
                Picker("Public tone", selection: $tone) {
                    ForEach(toneOptions, id: \.self) { option in
                        Text(option.capitalized).tag(option)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(maxWidth: 520)
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("Default redaction checklist")
                    .font(.caption.weight(.semibold))
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 190), spacing: 8)], spacing: 8) {
                    ForEach(redactionItems, id: \.self) { item in
                        HStack(spacing: 7) {
                            Image(systemName: "checkmark.shield")
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(.green)
                            Text(item)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 9)
                        .padding(.vertical, 6)
                        .background(Color.green.opacity(0.07))
                        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                    }
                }
            }

            Button {
                onGenerate()
            } label: {
                Label(isGenerating ? "Generating..." : "Generate custom profile", systemImage: isGenerating ? "hourglass" : "sparkles")
            }
            .buttonStyle(.borderedProminent)
            .disabled(isGenerating)
        }
        .padding(14)
        .background(Color(nsColor: .textBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(Color.accentColor.opacity(0.28))
        )
    }
}

private struct LabeledTextEditor: View {
    let title: String
    @Binding var text: String
    let placeholder: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.caption.weight(.semibold))
            ZStack(alignment: .topLeading) {
                if text.isEmpty {
                    Text(placeholder)
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 8)
                }
                TextEditor(text: $text)
                    .font(.caption)
                    .scrollContentBackground(.hidden)
                    .frame(minHeight: 74)
                    .padding(3)
            }
            .background(Color(nsColor: .controlBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        }
    }
}

private struct GenerationStatusCard: View {
    let status: NetworkingGenerationStatus
    let onRetry: () -> Void

    var body: some View {
        Group {
            switch status {
            case .idle:
                EmptyView()
            case .generating:
                HStack(spacing: 8) {
                    ProgressView()
                        .controlSize(.small)
                    Text(status.message ?? "")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .frame(maxWidth: 420, alignment: .leading)
                .background(Color.accentColor.opacity(0.08))
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            case let .succeeded(message):
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
                    .frame(maxWidth: 420, alignment: .leading)
                    .background(Color.green.opacity(0.08))
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            case let .failed(message):
                VStack(alignment: .leading, spacing: 7) {
                    Text("Could not finish profile generation")
                        .font(.caption.weight(.semibold))
                    Text(message)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    Text("Check your Diary Engine, then retry.")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Button("Retry", action: onRetry)
                        .font(.caption)
                        .buttonStyle(.bordered)
                }
                .padding(10)
                .frame(maxWidth: 420, alignment: .leading)
                .background(Color.red.opacity(0.08))
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .stroke(Color.red.opacity(0.18))
                )
            }
        }
    }
}

private struct GeneratedResultPreview: View {
    let profile: NetworkingGeneratedProfile
    let draft: NetworkingProfileDraft?
    let isApproved: Bool
    let isGenerating: Bool
    let onApprove: () -> Void
    let onRegenerate: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 14) {
                GeneratedFaceAvatar(avatar: profile.avatar, size: 68)
                VStack(alignment: .leading, spacing: 5) {
                    Text("Generated result preview")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Text(profile.label)
                        .font(.title3.weight(.semibold))
                    Text(profile.scenarioDescription)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer()
                StatusPill(text: "My Wiki + LLM", color: .green)
                StatusPill(text: approvalTitle, color: approvalColor)
            }

            if let draft {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Draft summary")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Text(draft.summary)
                        .font(.callout)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(12)
                .background(Color(nsColor: .controlBackgroundColor))
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

                HStack(spacing: 10) {
                    if isApproved {
                        Label("Approved", systemImage: "checkmark.circle.fill")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.green)
                    } else {
                        Button("Approve profile", action: onApprove)
                            .buttonStyle(.borderedProminent)
                    }

                    Button("Regenerate", action: onRegenerate)
                        .buttonStyle(.bordered)
                        .disabled(isGenerating)
                }
            } else {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Draft not generated")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 220), spacing: 12)], spacing: 12) {
                        ForEach(profile.summarySections) { section in
                            OutputSectionCard(section: section)
                        }
                    }
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

    private var approvalTitle: String {
        if draft == nil { return "Draft not generated" }
        return isApproved ? "Approved" : "Needs approval"
    }

    private var approvalColor: Color {
        if draft == nil { return .gray }
        return isApproved ? .green : .orange
    }
}

private struct CommunityBindingCard: View {
    let platform: NetworkingPlatformConfiguration
    let profile: NetworkingGeneratedProfile
    let isSelected: Bool
    let isAgentReady: Bool
    let isProfileApproved: Bool
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
                    GeneratedFaceAvatar(avatar: profile.avatar, size: 38)
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

                Text(statusMessage)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
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

    private var statusMessage: String {
        guard isAgentReady else {
            return "Local agent permission is still being prepared for this My Wiki project."
        }
        guard isProfileApproved else {
            return "Approve the matched profile before agent automation starts."
        }
        return "Agent can use this approved profile through local MCP."
    }
}

private struct SelectedCommunityDetail: View {
    let platform: NetworkingPlatformConfiguration
    let profile: NetworkingGeneratedProfile
    let isAgentReady: Bool
    let isProfileApproved: Bool
    let items: [NetworkingCockpitItem]

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 12) {
                PlatformMark(name: platform.name)
                VStack(alignment: .leading, spacing: 4) {
                    Text(platform.name)
                        .font(.title3.weight(.semibold))
                    Text("Matched to \(profile.label)")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                StatusPill(text: isAgentReady ? "Agent ready locally" : "Agent pending", color: isAgentReady ? .green : .orange)
                StatusPill(text: isProfileApproved ? "Approved profile" : "Needs approval", color: isProfileApproved ? .green : .orange)
            }

            HStack(spacing: 8) {
                PlatformStat(title: "Outbound", value: platform.activity.outbound)
                PlatformStat(title: "Inbound", value: platform.activity.inbound)
                PlatformStat(title: "Highlights", value: platform.activity.highlights)
            }

            Divider()

            HStack {
                Text("Messages and agent activity")
                    .font(.headline)
                Spacer()
                Text(platform.id)
                    .font(.caption2.monospaced())
                    .foregroundStyle(.tertiary)
            }

            if items.isEmpty {
                Text("No messages for this community yet.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color(nsColor: .controlBackgroundColor))
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            } else {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 270), spacing: 12)], spacing: 12) {
                    ForEach(items) { item in
                        InboxCard(item: item)
                    }
                }
            }
        }
        .padding(16)
        .background(Color(nsColor: .textBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(Color.accentColor.opacity(0.18))
        )
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
        .background(Color(nsColor: .controlBackgroundColor))
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
        [
            Color(red: 0.92, green: 0.72, blue: 0.56),
            Color(red: 0.78, green: 0.58, blue: 0.44),
            Color(red: 0.96, green: 0.80, blue: 0.66),
            Color(red: 0.72, green: 0.52, blue: 0.40),
        ][seedValue(modulo: 4)]
    }

    private var hairColor: Color {
        [
            Color(red: 0.15, green: 0.12, blue: 0.10),
            Color(red: 0.30, green: 0.22, blue: 0.16),
            Color(red: 0.12, green: 0.18, blue: 0.20),
            Color(red: 0.20, green: 0.16, blue: 0.24),
        ][seedValue(modulo: 4, offset: 7)]
    }

    var body: some View {
        ZStack {
            backgroundShape
                .fill(
                    LinearGradient(
                        colors: [baseColor.opacity(0.92), baseColor.opacity(0.62)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )

            decorativeLine
                .stroke(Color.white.opacity(0.22), lineWidth: max(1, size * 0.035))
                .frame(width: size * 0.78, height: size * 0.78)
                .offset(x: -size * 0.06, y: -size * 0.04)

            Capsule()
                .fill(baseColor.opacity(0.95))
                .frame(width: size * 0.50, height: size * 0.18)
                .offset(y: size * 0.34)

            Circle()
                .fill(skinColor)
                .frame(width: size * 0.58, height: size * 0.60)
                .offset(y: size * 0.07)

            hairShape
                .fill(hairColor)
                .frame(width: size * 0.58, height: size * 0.34)
                .offset(y: -size * 0.18)

            if seedValue(modulo: 2, offset: 11) == 0 {
                glasses
            }

            HStack(spacing: size * 0.13) {
                Circle().fill(Color.black.opacity(0.70))
                Circle().fill(Color.black.opacity(0.70))
            }
            .frame(width: size * 0.30, height: size * 0.05)
            .offset(y: size * 0.02)

            expression
                .stroke(Color.black.opacity(0.45), lineWidth: max(1.1, size * 0.024))
                .frame(width: size * 0.18, height: size * 0.09)
                .offset(y: size * 0.18)
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }

    private var backgroundShape: AnyShape {
        switch seedValue(modulo: 3, offset: 3) {
        case 0:
            return AnyShape(Circle())
        case 1:
            return AnyShape(RoundedRectangle(cornerRadius: size * 0.22, style: .continuous))
        default:
            return AnyShape(RoundedRectangle(cornerRadius: size * 0.34, style: .continuous))
        }
    }

    private var decorativeLine: Path {
        var path = Path()
        path.move(to: CGPoint(x: size * 0.16, y: size * 0.72))
        path.addCurve(
            to: CGPoint(x: size * 0.72, y: size * 0.18),
            control1: CGPoint(x: size * 0.36, y: size * 0.42),
            control2: CGPoint(x: size * 0.48, y: size * 0.22)
        )
        return path
    }

    private var hairShape: AnyShape {
        switch seedValue(modulo: 3, offset: 5) {
        case 0:
            return AnyShape(Capsule())
        case 1:
            return AnyShape(RoundedRectangle(cornerRadius: size * 0.14, style: .continuous))
        default:
            return AnyShape(UnevenRoundedRectangle(topLeadingRadius: size * 0.24, bottomLeadingRadius: size * 0.04, bottomTrailingRadius: size * 0.18, topTrailingRadius: size * 0.08))
        }
    }

    private var glasses: some View {
        HStack(spacing: size * 0.05) {
            RoundedRectangle(cornerRadius: size * 0.04, style: .continuous)
                .stroke(Color.black.opacity(0.38), lineWidth: max(1, size * 0.018))
            RoundedRectangle(cornerRadius: size * 0.04, style: .continuous)
                .stroke(Color.black.opacity(0.38), lineWidth: max(1, size * 0.018))
        }
        .frame(width: size * 0.42, height: size * 0.14)
        .offset(y: size * 0.02)
    }

    private var expression: Path {
        var path = Path()
        if seedValue(modulo: 2, offset: 13) == 0 {
            path.move(to: CGPoint(x: 0, y: size * 0.02))
            path.addQuadCurve(to: CGPoint(x: size * 0.18, y: size * 0.02), control: CGPoint(x: size * 0.09, y: size * 0.09))
        } else {
            path.move(to: CGPoint(x: 0, y: size * 0.04))
            path.addLine(to: CGPoint(x: size * 0.18, y: size * 0.04))
        }
        return path
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
        case .active: return "active"
        case .paused: return "waiting"
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

private struct AnyShape: Shape {
    private let pathBuilder: @Sendable (CGRect) -> Path

    init<S: Shape & Sendable>(_ shape: S) {
        pathBuilder = { rect in
            shape.path(in: rect)
        }
    }

    func path(in rect: CGRect) -> Path {
        pathBuilder(rect)
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
