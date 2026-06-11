import XCTest
@testable import KnowYou

final class NetworkingCockpitPresentationTests: XCTestCase {
    func testNetworkingCockpitViewIsNativeSwiftUIWithoutWebView() throws {
        let sourceURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("KnowYou/UI/Networking/NetworkingCockpitView.swift")
        let source = try String(contentsOf: sourceURL, encoding: .utf8)

        XCTAssertFalse(source.contains("import WebKit"))
        XCTAssertFalse(source.contains("WKWebView"))
        XCTAssertFalse(source.contains("NSViewRepresentable"))
        XCTAssertFalse(source.contains("loadHTMLString"))
        XCTAssertTrue(source.contains("ScrollView"))
        XCTAssertTrue(source.contains("Generate profiles"))
    }

    func testNetworkingCockpitViewGuidesProfileCommunityAndMessageStepsInEnglish() throws {
        let sourceURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("KnowYou/UI/Networking/NetworkingCockpitView.swift")
        let source = try String(contentsOf: sourceURL, encoding: .utf8)

        XCTAssertTrue(source.contains("Privacy and redaction"))
        XCTAssertTrue(source.contains("Generate profiles"))
        XCTAssertTrue(source.contains("Choose a default scenario or create a custom one."))
        XCTAssertTrue(source.contains("Generated result preview"))
        XCTAssertTrue(source.contains("Custom scenario"))
        XCTAssertTrue(source.contains("Connect communities"))
        XCTAssertTrue(source.contains("Review messages and leads"))
        XCTAssertTrue(source.contains("Know You Careers"))
        XCTAssertTrue(source.contains("Know You Friends"))
        XCTAssertFalse(source.contains(#"Text("Prompt")"#))
        XCTAssertFalse(source.contains("selectedProfile.prompt"))
    }

    func testNetworkingCockpitViewWiresRealMyWikiGenerationAndActivation() throws {
        let sourceURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("KnowYou/UI/Networking/NetworkingCockpitView.swift")
        let source = try String(contentsOf: sourceURL, encoding: .utf8)

        XCTAssertTrue(source.contains("let projectRoot: URL?"))
        XCTAssertTrue(source.contains("let summarizer: (any SummaryGenerating)?"))
        XCTAssertTrue(source.contains("generateSelectedProfile"))
        XCTAssertTrue(source.contains("NetworkingProfileGenerationService"))
        XCTAssertTrue(source.contains("NetworkingActivationStateStore().save"))
        XCTAssertTrue(source.contains("Generate from My Wiki"))
        XCTAssertTrue(source.contains("Generation timed out. Try again after checking your Diary Engine."))
    }

    func testNetworkingCockpitVisibleCopyIsEnglishOnly() throws {
        let sourceURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("KnowYou/UI/Networking/NetworkingCockpitView.swift")
        let source = try String(contentsOf: sourceURL, encoding: .utf8)

        let containsChineseCharacter = source.unicodeScalars.contains { scalar in
            (0x4E00...0x9FFF).contains(Int(scalar.value))
        }
        XCTAssertFalse(containsChineseCharacter)
    }

    func testNetworkingCockpitViewUsesGeneratedFaceAvatarsInsteadOfLetterBadges() throws {
        let sourceURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("KnowYou/UI/Networking/NetworkingCockpitView.swift")
        let source = try String(contentsOf: sourceURL, encoding: .utf8)

        XCTAssertTrue(source.contains("GeneratedFaceAvatar"))
        XCTAssertTrue(source.contains("avatarSeed"))
        XCTAssertFalse(source.contains("Text(profile.avatar.displayLetter)"))
        XCTAssertFalse(source.contains("Text(profile.avatar.fallbackLetter)"))
        XCTAssertFalse(source.contains("Text(profile.personName)"))
    }

    func testProfileDraftRequiresHumanApprovalBeforePublicSync() {
        let draft = NetworkingProfileDraft(
            id: "draft-hiring",
            personName: "Tianfu",
            profileLabel: "Hiring",
            summary: "Hiring a founding full-stack engineer.",
            source: .myWiki,
            approvalStatus: .draft
        )

        XCTAssertFalse(draft.canPublish)
    }

    func testAIAttributionUsesPersonProfileAndAIMarker() {
        let item = NetworkingPublicContent(
            id: "ai-comment",
            kind: .comment,
            authorType: .ai,
            personName: "Tianfu",
            profileLabel: "Hiring",
            body: "This candidate may fit the role.",
            createdAt: Date(timeIntervalSince1970: 1_779_840_000)
        )

        XCTAssertEqual(NetworkingCockpitPresentation.attribution(for: item), "Tianfu · Hiring · AI")
    }

    func testHumanContentSortsBeforeAIContent() {
        let human = NetworkingPublicContent(
            id: "human",
            kind: .comment,
            authorType: .human,
            personName: "Echo",
            profileLabel: "Looking",
            body: "I am interested.",
            createdAt: Date(timeIntervalSince1970: 1_779_840_100)
        )
        let ai = NetworkingPublicContent(
            id: "ai",
            kind: .comment,
            authorType: .ai,
            personName: "Tianfu",
            profileLabel: "Hiring",
            body: "This looks relevant.",
            createdAt: Date(timeIntervalSince1970: 1_779_840_200)
        )

        XCTAssertEqual(NetworkingCockpitPresentation.sortedPublicContent([ai, human]).map(\.id), ["human", "ai"])
    }

    func testCockpitPayloadKeepsPrivateReasonLocal() {
        let presentation = NetworkingCockpitPresentation(
            items: [
                NetworkingCockpitItem(
                    id: "highlight-role",
                    direction: .highlight,
                    title: "Most relevant role",
                    publicSummary: "Founding engineer opening",
                    privateReason: "Matches My Wiki evidence about local-first agent products.",
                    publicReferenceID: "post-1"
                ),
                NetworkingCockpitItem(
                    id: "inbound",
                    direction: .inbound,
                    title: "Someone is looking at you",
                    publicSummary: "Echo's AI commented on your hiring post.",
                    privateReason: "Strong overlap with your Hiring profile.",
                    publicReferenceID: "comment-1"
                )
            ]
        )

        XCTAssertEqual(presentation.sections.map(\.direction), [.highlight, .inbound])
        XCTAssertTrue(presentation.localBridgePayload.contains("Matches My Wiki evidence"))
        XCTAssertFalse(presentation.publicPlatformPayload.contains("Matches My Wiki evidence"))
    }

    func testAgentPublicWritePayloadMarksAIAndStripsPrivateReason() throws {
        let action = NetworkingAgentAction(
            id: "agent-comment",
            kind: .comment,
            profileID: "profile-hiring",
            profileLabel: "Hiring",
            body: "This looks aligned with the founding role.",
            publicReferenceID: "post-1",
            privateReason: "My Wiki shows repeated work on local-first agent systems.",
            createdAt: Date(timeIntervalSince1970: 1_779_840_000),
            status: .queued
        )

        let payload = action.publicWritePayload
        let payloadData = try JSONEncoder().encode(payload)
        let payloadText = try XCTUnwrap(String(data: payloadData, encoding: .utf8))

        XCTAssertEqual(payload.authorType, .ai)
        XCTAssertEqual(payload.profileID, "profile-hiring")
        XCTAssertFalse(payloadText.contains("My Wiki shows"))
    }

    func testAgentActionsBecomeCockpitQueueWithoutUploadingPrivateReason() {
        let action = NetworkingAgentAction(
            id: "agent-post",
            kind: .post,
            profileID: "profile-founder",
            profileLabel: "Founder",
            body: "Looking for people building context-native products.",
            publicReferenceID: nil,
            privateReason: "Private matching reason from My Wiki.",
            createdAt: Date(timeIntervalSince1970: 1_779_840_000),
            status: .queued
        )

        let presentation = NetworkingCockpitPresentation(
            items: NetworkingCockpitPresentation.cockpitItems(for: [action])
        )

        XCTAssertEqual(presentation.sections.map(\.direction), [.outbound])
        XCTAssertTrue(presentation.localBridgePayload.contains("Private matching reason"))
        XCTAssertFalse(presentation.publicPlatformPayload.contains("Private matching reason"))
    }

    func testAgentFrequencyGuardBlocksDuplicateAndHourlyOverflow() {
        let now = Date(timeIntervalSince1970: 1_779_840_000)
        let guardrail = NetworkingAgentFrequencyGuard(maxActionsPerProfilePerHour: 2)
        let first = makeAgentAction(id: "first", body: "Same body", createdAt: now)
        let duplicate = makeAgentAction(id: "duplicate", body: " same body ", createdAt: now.addingTimeInterval(60))
        let second = makeAgentAction(id: "second", body: "Different body", createdAt: now.addingTimeInterval(120))
        let third = makeAgentAction(id: "third", body: "Third body", createdAt: now.addingTimeInterval(180))

        XCTAssertFalse(guardrail.shouldAllow(duplicate, existingActions: [first]))
        XCTAssertTrue(guardrail.shouldAllow(second, existingActions: [first]))
        XCTAssertFalse(guardrail.shouldAllow(third, existingActions: [first, second]))
    }

    func testRuntimeBuildsMultipleMyWikiDraftsWithoutAutoPublishing() {
        let runtime = NetworkingAgentRuntime()
        let drafts = runtime.profileDrafts(
            from: [
                NetworkingMyWikiProfileSignal(
                    id: "signal-founder",
                    personName: "Tianfu",
                    profileLabel: "Founder",
                    summary: "Building context-native products.",
                    body: "Looking for collaborators who care about local-first AI."
                ),
                NetworkingMyWikiProfileSignal(
                    id: "signal-hiring",
                    personName: "Tianfu",
                    profileLabel: "Hiring",
                    summary: "Hiring product-minded engineers.",
                    body: "Need people who can ship across Swift, web, and agent workflows."
                )
            ]
        )

        XCTAssertEqual(drafts.map(\.profileLabel), ["Founder", "Hiring"])
        XCTAssertEqual(drafts.map(\.source), [.myWiki, .myWiki])
        XCTAssertTrue(drafts.allSatisfy { $0.approvalStatus == .draft })
        XCTAssertTrue(runtime.publicSyncPayloads(for: drafts).isEmpty)
    }

    func testScenarioPromptAndMyWikiSignalCreateProfileDraft() {
        let scenario = NetworkingProfileScenario(
            id: "hiring",
            label: "招人",
            prompt: "强调我作为创业者和招聘方的样子。"
        )
        let signal = NetworkingMyWikiProfileSignal(
            id: "signal-hiring",
            personName: "Tianfu",
            profileLabel: "工作",
            summary: "正在做 KnowYou Networking。",
            body: "能负责 macOS、Web、agent runtime 和本地隐私边界。"
        )

        let draft = NetworkingAgentRuntime().profileDraft(
            from: scenario,
            prompt: scenario.prompt,
            signal: signal
        )

        XCTAssertEqual(draft.profileLabel, "工作")
        XCTAssertEqual(draft.source, .myWiki)
        XCTAssertEqual(draft.approvalStatus, .draft)
        XCTAssertTrue(draft.body.contains("强调我作为创业者"))
        XCTAssertTrue(draft.body.contains("agent runtime"))
    }

    func testDefaultPlatformsAreOnlyJobsAndFriends() {
        XCTAssertEqual(NetworkingPlatformDefinition.defaultPlatforms.map(\.id), ["knowyou-jobs", "knowyou-friends"])
        XCTAssertEqual(NetworkingPlatformDefinition.defaultPlatforms.map(\.displayName), ["Know You 求职", "Know You 认识新朋友"])
    }

    func testProfileGenerationUsesMyWikiContextAndLLMOutput() async throws {
        let service = NetworkingProfileGenerationService(
            contextProvider: StubNetworkingMyWikiContextProvider(
                result: .success(
                    NetworkingProfileContext(
                        summary: "My Wiki context: building KnowYou, SwiftUI, Supabase, agent runtime.",
                        citations: ["wiki/concepts/knowyou-networking.md"]
                    )
                )
            ),
            generator: StubNetworkingLLMProfileGenerator(
                result: .success(
                    NetworkingGeneratedProfileContent(
                        summary: "公开摘要：正在做 KnowYou Networking。",
                        sections: [
                            NetworkingProfileSummarySection(title: "能负责", body: "SwiftUI、Next.js、Supabase 和 agent runtime。")
                        ]
                    )
                )
            )
        )

        let draft = try await service.generateDraft(
            scenario: NetworkingProfileScenario.jobs,
            prompt: "强调求职和招聘相关能力。",
            personName: "林书涵",
            projectRoot: URL(fileURLWithPath: "/tmp/my-wiki")
        )

        XCTAssertEqual(draft.source, .myWiki)
        XCTAssertEqual(draft.approvalStatus, .draft)
        XCTAssertEqual(draft.summary, "公开摘要：正在做 KnowYou Networking。")
        XCTAssertTrue(draft.body.contains("SwiftUI、Next.js、Supabase"))
        XCTAssertTrue(draft.body.contains("wiki/concepts/knowyou-networking.md"))
    }

    func testPromptProfileGeneratorExtractsTextFromStructuredSummarizerOutput() async throws {
        let rawStructuredOutput = #"{"sections":[{"id":"daily-journal","paragraphs":[{"sourceEventIDs":["00000000-0000-0000-0000-000000000000"],"text":"Tianfu Wu builds local-first AI products and can own SwiftUI, web, Supabase, MCP, and product shipping."}]}]}"#
        let generator = NetworkingPromptProfileGenerator(
            summarizer: StubSummaryGenerating(output: rawStructuredOutput)
        )

        let content = try await generator.generateProfile(
            scenario: .jobs,
            prompt: "Generate a hiring profile.",
            personName: "Tianfu Wu",
            context: NetworkingProfileContext(
                summary: "KnowYou context",
                citations: ["wiki/entities/knowyou.md"]
            )
        )

        XCTAssertEqual(
            content.summary,
            "Tianfu Wu builds local-first AI products and can own SwiftUI, web, Supabase, MCP, and product shipping."
        )
        XCTAssertFalse(content.summary.contains(#""sections""#))
    }

    func testProfileGenerationFailureDoesNotCreateFictionalDraft() async {
        let service = NetworkingProfileGenerationService(
            contextProvider: StubNetworkingMyWikiContextProvider(result: .failure(NetworkingProfileGenerationError.myWikiUnavailable)),
            generator: StubNetworkingLLMProfileGenerator(
                result: .success(
                    NetworkingGeneratedProfileContent(
                        summary: "Should not be used",
                        sections: []
                    )
                )
            )
        )

        do {
            _ = try await service.generateDraft(
                scenario: NetworkingProfileScenario.friends,
                prompt: "生成认识新朋友 profile。",
                personName: "林书涵",
                projectRoot: URL(fileURLWithPath: "/missing")
            )
            XCTFail("Expected generation to fail instead of creating a fictional profile.")
        } catch NetworkingProfileGenerationError.myWikiUnavailable {
            XCTAssertTrue(true)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testActivationPayloadUsesAnonymousIdentityAndAgentToken() throws {
        let activation = NetworkingActivationService().activationPlan(
            personName: "林书涵",
            handle: "shuhan",
            approvedProfiles: [
                NetworkingProfileSyncPayload(
                    profileID: "profile-jobs",
                    personName: "林书涵",
                    profileLabel: "职业/求职",
                    summary: "公开职业摘要",
                    body: "公开职业正文"
                )
            ]
        )

        XCTAssertEqual(activation.authMode, .supabaseAnonymous)
        XCTAssertEqual(activation.peoplePayload.displayName, "林书涵")
        XCTAssertEqual(activation.profilePayloads.map(\.profileID), ["profile-jobs"])
        XCTAssertFalse(activation.agentTokenPlaintext.isEmpty)
        XCTAssertEqual(activation.agentTokenLabel, "Local KnowYou Networking agent")
    }

    func testActivationStateStorePersistsEnabledStateForNetworkingMCP() throws {
        let projectRoot = temporaryDirectory().appending(path: "KnowYouContext", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: projectRoot, withIntermediateDirectories: true)
        let state = NetworkingActivationState(
            isEnabled: true,
            personID: "person-real-user",
            agentTokenPlaintext: "knw_agent_real_user",
            supabaseURL: URL(string: "https://local.knowyou.invalid")!,
            publishableKey: "local-dev"
        )

        let store = NetworkingActivationStateStore()
        try store.save(state, projectRoot: projectRoot)

        XCTAssertEqual(store.load(projectRoot: projectRoot), state)
    }

    func testNetworkingMCPRequiresActivationForPublishing() {
        let request = #"{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"networking_publish_post","arguments":{"platform_id":"knowyou-jobs","profile_id":"profile-jobs","body":"hello"}}}"#

        let result = NetworkingMCPCommand.run(
            arguments: ["KnowYou", NetworkingMCPCommand.launchArgument, "--project-root", "/tmp/missing"],
            input: request
        )

        XCTAssertEqual(result.exitCode, 0)
        XCTAssertTrue(result.stdout.contains("permission required"))
    }

    func testNetworkingMCPPublishPayloadContainsPlatformProfileAIAndToken() throws {
        let state = NetworkingActivationState(
            isEnabled: true,
            personID: "person-1",
            agentTokenPlaintext: "agent-token",
            supabaseURL: URL(string: "https://example.supabase.co")!,
            publishableKey: "sb_publishable_test"
        )
        let request = #"{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"networking_publish_post","arguments":{"platform_id":"knowyou-jobs","profile_id":"profile-jobs","body":"hello"}}}"#

        let result = NetworkingMCPCommand.run(
            arguments: ["KnowYou", NetworkingMCPCommand.launchArgument, "--project-root", "/tmp/wiki"],
            input: request,
            activationState: state
        )

        XCTAssertEqual(result.exitCode, 0)
        XCTAssertTrue(result.stdout.contains(#""platform_id":"knowyou-jobs""#))
        XCTAssertTrue(result.stdout.contains(#""profile_id":"profile-jobs""#))
        XCTAssertTrue(result.stdout.contains(#""author_type":"ai""#))
        XCTAssertTrue(result.stdout.contains(#""token":"agent-token""#))
    }

    func testPlatformConfigurationRequiresGeneratedProfileBeforeAutomation() {
        let generated = NetworkingGeneratedProfile(
            id: "work",
            displayName: "Lin Shuhan · 林书涵",
            label: "工作",
            englishLabel: "Work",
            prompt: "工作相关 profile prompt",
            avatar: NetworkingProfileAvatar(fallbackLetter: "林", backgroundHex: "#c25a35"),
            summarySections: [
                NetworkingProfileSummarySection(title: "我能负责", body: "全栈到底和 agent 调试。")
            ],
            autoUpdate: true,
            lastUpdatedLabel: "12 小时前"
        )
        let draft = NetworkingGeneratedProfile(
            id: "academic",
            displayName: "Shuhan Lin",
            label: "学术",
            englishLabel: "Academic",
            prompt: "草稿",
            avatar: NetworkingProfileAvatar(fallbackLetter: "S", backgroundHex: "#9b6a3c"),
            summarySections: [],
            autoUpdate: false,
            lastUpdatedLabel: nil
        )
        let platform = NetworkingPlatformConfiguration(
            id: "knowyou",
            name: "KnowYou Networking",
            subtitle: "公开广场 · 内部",
            assignedProfileID: "work",
            status: .active,
            activity: NetworkingPlatformActivity(outbound: 7, inbound: 4, highlights: 2)
        )

        XCTAssertTrue(platform.canRunAutomation(with: [generated, draft]))
        XCTAssertEqual(platform.assignedProfile(in: [generated, draft])?.label, "工作")
        XCTAssertTrue(generated.hasGeneratedOutput)
        XCTAssertFalse(draft.hasGeneratedOutput)
    }

    func testProfileAvatarUsesStableInitialsFallbackWhenImageURLIsMissing() {
        let avatar = NetworkingProfileAvatar(fallbackLetter: "林", backgroundHex: "#c25a35")

        XCTAssertNil(avatar.imageURL)
        XCTAssertEqual(avatar.displayLetter, "林")
        XCTAssertEqual(avatar.backgroundHex, "#c25a35")
        XCTAssertTrue(avatar.usesFallback)
    }

    func testApprovedDraftCreatesPublicSyncPayloadAndDraftDoesNot() {
        let approved = NetworkingProfileDraft(
            id: "profile-hiring",
            personName: "Tianfu",
            profileLabel: "Hiring",
            summary: "Hiring founding engineers.",
            body: "Public-facing role context.",
            source: .myWiki,
            approvalStatus: .approved
        )
        let draft = NetworkingProfileDraft(
            id: "profile-founder",
            personName: "Tianfu",
            profileLabel: "Founder",
            summary: "Still private.",
            body: "Private draft.",
            source: .myWiki,
            approvalStatus: .draft
        )

        let payloads = NetworkingAgentRuntime().publicSyncPayloads(for: [approved, draft])

        XCTAssertEqual(payloads.map(\.profileID), ["profile-hiring"])
        XCTAssertEqual(payloads.first?.profileLabel, "Hiring")
        XCTAssertFalse(String(describing: payloads).contains("Private draft"))
    }

    func testRuntimeQueuesHighlightsAndAgentActionsWithoutUploadingPrivateReasons() {
        let now = Date(timeIntervalSince1970: 1_779_840_000)
        let runtime = NetworkingAgentRuntime(
            frequencyGuard: NetworkingAgentFrequencyGuard(maxActionsPerProfilePerHour: 2)
        )
        let opportunity = NetworkingPublicOpportunity(
            id: "role-1",
            direction: .highlight,
            title: "Founding Swift engineer",
            publicSummary: "A public post looking for local-first AI experience.",
            publicReferenceID: "post-1",
            profileID: "profile-hiring",
            profileLabel: "Hiring",
            suggestedActionKind: .comment,
            suggestedBody: "This looks closely aligned with our current local-first AI work.",
            privateReason: "My Wiki evidence links this to active KnowYou architecture work."
        )

        let actions = runtime.agentActions(
            for: [opportunity],
            existingActions: [],
            createdAt: now
        )
        let presentation = runtime.cockpitPresentation(
            highlights: [opportunity],
            agentActions: actions
        )

        XCTAssertEqual(actions.count, 1)
        XCTAssertEqual(actions.first?.publicWritePayload.authorType, .ai)
        XCTAssertEqual(presentation.sections.map(\.direction), [.highlight, .outbound])
        XCTAssertTrue(presentation.localBridgePayload.contains("active KnowYou architecture"))
        XCTAssertFalse(presentation.publicPlatformPayload.contains("active KnowYou architecture"))
    }

    private func makeAgentAction(id: String, body: String, createdAt: Date) -> NetworkingAgentAction {
        NetworkingAgentAction(
            id: id,
            kind: .comment,
            profileID: "profile-hiring",
            profileLabel: "Hiring",
            body: body,
            publicReferenceID: "post-1",
            privateReason: "Private reason",
            createdAt: createdAt,
            status: .queued
        )
    }

    private func temporaryDirectory() -> URL {
        FileManager.default.temporaryDirectory
            .appending(path: "knowyou-networking-tests-\(UUID().uuidString)", directoryHint: .isDirectory)
    }
}

private struct StubNetworkingMyWikiContextProvider: NetworkingMyWikiContextProviding {
    let result: Result<NetworkingProfileContext, Error>

    func context(for scenario: NetworkingProfileScenario, prompt: String, projectRoot: URL) throws -> NetworkingProfileContext {
        try result.get()
    }
}

private struct StubNetworkingLLMProfileGenerator: NetworkingLLMProfileGenerating {
    let result: Result<NetworkingGeneratedProfileContent, Error>

    func generateProfile(
        scenario: NetworkingProfileScenario,
        prompt: String,
        personName: String,
        context: NetworkingProfileContext
    ) async throws -> NetworkingGeneratedProfileContent {
        try result.get()
    }
}

private struct StubSummaryGenerating: SummaryGenerating {
    let output: String

    func summarize(dayKey: String, markdown: String, context: SummaryInvocationContext) async throws -> String {
        output
    }
}
