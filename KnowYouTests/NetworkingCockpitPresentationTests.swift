import XCTest
@testable import KnowYou

final class NetworkingCockpitPresentationTests: XCTestCase {
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
                    publicReferenceID: "post-1",
                    platformID: "knowyou-jobs"
                ),
                NetworkingCockpitItem(
                    id: "inbound",
                    direction: .inbound,
                    title: "Someone is looking at you",
                    publicSummary: "Echo's AI commented on your hiring post.",
                    privateReason: "Strong overlap with your Hiring profile.",
                    publicReferenceID: "comment-1",
                    platformID: "knowyou-friends"
                )
            ]
        )

        XCTAssertEqual(presentation.sections.map(\.direction), [.highlight, .inbound])
        XCTAssertTrue(presentation.localBridgePayload.contains("Matches My Wiki evidence"))
        XCTAssertFalse(presentation.publicPlatformPayload.contains("Matches My Wiki evidence"))
    }

    func testCockpitItemsFilterBySelectedPlatform() {
        let presentation = NetworkingCockpitPresentation(
            items: [
                NetworkingCockpitItem(
                    id: "jobs",
                    direction: .highlight,
                    title: "Career role",
                    publicSummary: "A career post.",
                    privateReason: "Career private reason.",
                    publicReferenceID: "post-careers",
                    platformID: "knowyou-jobs"
                ),
                NetworkingCockpitItem(
                    id: "friends",
                    direction: .inbound,
                    title: "Friend reply",
                    publicSummary: "A social reply.",
                    privateReason: "Friends private reason.",
                    publicReferenceID: "comment-friends",
                    platformID: "knowyou-friends"
                )
            ]
        )

        XCTAssertEqual(presentation.items(forPlatformID: "knowyou-jobs").map(\.id), ["jobs"])
        XCTAssertEqual(presentation.items(forPlatformID: "knowyou-friends").map(\.id), ["friends"])
    }

    func testCockpitSectionTitlesMatchAgentHomeQueueLanguage() {
        let presentation = NetworkingCockpitPresentation(
            items: [
                NetworkingCockpitItem(
                    id: "reply",
                    direction: .inbound,
                    title: "Reply needed",
                    publicSummary: "Someone replied to your public comment.",
                    privateReason: "Local reason.",
                    publicReferenceID: "comment-1",
                    platformID: "knowyou-friends"
                ),
                NetworkingCockpitItem(
                    id: "match",
                    direction: .highlight,
                    title: "Potential match",
                    publicSummary: "A public post matches your profile.",
                    privateReason: "Local reason.",
                    publicReferenceID: "post-1",
                    platformID: "knowyou-friends"
                ),
                NetworkingCockpitItem(
                    id: "saved",
                    direction: .outbound,
                    title: "Saved",
                    publicSummary: "The agent saved a risky item for review.",
                    privateReason: "Local reason.",
                    publicReferenceID: "post-2",
                    platformID: "knowyou-friends"
                )
            ]
        )

        XCTAssertEqual(presentation.sections.map(\.title), [
            "Potential matches",
            "Needs reply",
            "Saved for you"
        ])
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
        XCTAssertFalse(draft.body.contains("wiki/concepts/knowyou-networking.md"))
        XCTAssertEqual(draft.citations, ["wiki/concepts/knowyou-networking.md"])
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

    func testPromptProfileGeneratorRequestsPublicRedactedScenarioProfile() async throws {
        let summarizer = CapturingJSONSummaryGenerating(
            output: #"{"summary":"Tianfu builds local-first AI products.","sections":[{"title":"What I do","body":"Builds product and agent systems."}]}"#
        )
        let generator = NetworkingPromptProfileGenerator(summarizer: summarizer)

        _ = try await generator.generateProfile(
            scenario: .jobs,
            prompt: "Generate a career profile.",
            personName: "Tianfu Wu",
            context: NetworkingProfileContext(
                summary: "- Work Platform Builder [wiki/concepts/work-platform-builder.md]\n  excerpt: Builds product architecture and agent systems.",
                citations: ["wiki/concepts/work-platform-builder.md"]
            )
        )

        let capturedPrompt = summarizer.capturedPrompt ?? ""
        XCTAssertTrue(capturedPrompt.contains("Output language: English"))
        XCTAssertTrue(capturedPrompt.contains("Scenario lens: Career / Hiring"))
        XCTAssertTrue(capturedPrompt.contains("public profile"))
        XCTAssertTrue(capturedPrompt.contains("Redact"))
        XCTAssertTrue(capturedPrompt.contains("Do not include raw My Wiki evidence"))
        XCTAssertTrue(capturedPrompt.contains("Do not include deep matching reasons"))
        XCTAssertTrue(capturedPrompt.contains("Use the citations only as grounding"))
        XCTAssertTrue(capturedPrompt.contains("Do not write a diary entry"))
        XCTAssertTrue(capturedPrompt.contains("Use third-person public profile prose"))
        XCTAssertTrue(capturedPrompt.contains("If public-safe evidence is sparse"))
        XCTAssertTrue(capturedPrompt.contains("Write a long-form profile"))
        XCTAssertTrue(capturedPrompt.contains("2,000 to 3,000 words"))
        XCTAssertTrue(capturedPrompt.contains("6 to 10 titled sections"))
        XCTAssertFalse(capturedPrompt.contains("生成公开 profile 草稿"))
        XCTAssertTrue(summarizer.capturedSchema?.contains(#""minItems":6"#) ?? false)
        XCTAssertTrue(summarizer.capturedSchema?.contains(#""maxItems":10"#) ?? false)
    }

    func testLaunchModeRecognizesNetworkingProfileDraftCommand() {
        XCTAssertEqual(
            LaunchMode(arguments: ["KnowYou", "--networking-profile-draft"]),
            .networkingProfileDraft
        )
    }

    func testNetworkingProfileDraftCommandGeneratesDraftFromCuratedMyWiki() throws {
        let projectRoot = temporaryDirectory().appending(path: "KnowYouContext", directoryHint: .isDirectory)
        try writeMyWikiPage(
            """
            ---
            type: concept
            title: Work Platform Builder
            tags: [career, product, engineering, agent, collaboration]
            ---

            # Work Platform Builder

            Tianfu builds local-first AI products, SwiftUI app surfaces, Supabase-backed web systems, MCP runtime flows, and agent collaboration workflows.
            """,
            to: projectRoot.appending(path: "wiki/concepts/work-platform-builder.md")
        )
        try writeMyWikiPage(
            """
            # Raw Private Source

            This raw source should never be read by networking profile generation.
            """,
            to: projectRoot.appending(path: "raw/sources/private-source.md")
        )

        let result = NetworkingProfileDraftCommand.run(
            arguments: [
                "KnowYou",
                "--networking-profile-draft",
                "--project-root", projectRoot.path,
                "--scenario", "jobs",
                "--person-name", "Tianfu Wu",
                "--pretty",
            ],
            summarizer: StubSummaryGenerating(
                output: #"{"summary":"Tianfu builds local-first AI products and agent systems.","sections":[{"title":"What I build","body":"Local-first app, web, Supabase, MCP, and agent workflows."}]}"#
            )
        )

        XCTAssertEqual(result.exitCode, 0)
        XCTAssertEqual(result.stderr, "")

        let draft = try JSONDecoder().decode(NetworkingProfileDraft.self, from: Data(result.stdout.utf8))
        XCTAssertEqual(draft.personName, "Tianfu Wu")
        XCTAssertEqual(draft.summary, "Tianfu builds local-first AI products and agent systems.")
        XCTAssertFalse(draft.body.contains("wiki/concepts/work-platform-builder.md"))
        XCTAssertEqual(draft.citations, ["wiki/concepts/work-platform-builder.md"])
        XCTAssertFalse(draft.body.contains("raw/sources/private-source.md"))
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

    func testMyWikiNetworkingContextProviderUsesOnlyCuratedWikiPages() throws {
        let projectRoot = temporaryDirectory().appending(path: "KnowYouContext", directoryHint: .isDirectory)
        try writeMyWikiPage(
            """
            ---
            type: concept
            title: Career Agent Product Work
            tags: [career, agent, product, hiring]
            ---

            # Career Agent Product Work

            Tianfu builds local-first agent products, SwiftUI surfaces, Supabase-backed web systems, and MCP runtime flows for hiring and collaboration.
            """,
            to: projectRoot.appending(path: "wiki/concepts/career-agent-product-work.md")
        )
        try writeMyWikiPage(
            """
            ---
            type: knowyou-diary
            day: 2026-06-01
            ---

            # Raw Diary

            raw private hiring agent product work should never be cited directly by Networking profile generation.
            """,
            to: projectRoot.appending(path: "raw/sources/knowyou-diary-2026-06-01.md")
        )
        try writeMyWikiPage(
            """
            ---
            type: source
            day: 2026-06-01
            ---

            # Source-Layer Diary Page

            source layer hiring agent product work should not be used for public profile generation.
            """,
            to: projectRoot.appending(path: "wiki/sources/knowyou-diary-2026-06-01.md")
        )

        let context = try MyWikiNetworkingContextProvider().context(
            for: .jobs,
            prompt: "Generate a career profile for hiring and collaboration.",
            projectRoot: projectRoot
        )

        XCTAssertEqual(context.citations, ["wiki/concepts/career-agent-product-work.md"])
        XCTAssertTrue(context.summary.contains("Career Agent Product Work"))
        XCTAssertFalse(context.summary.contains("Raw Diary"))
        XCTAssertFalse(context.summary.contains("Source-Layer Diary Page"))
        XCTAssertFalse(context.citations.contains { $0.hasPrefix("raw/sources/") })
        XCTAssertFalse(context.citations.contains { $0.hasPrefix("wiki/sources/") })
    }

    func testPromptProfileGeneratorExtractsDiaryEntryJSONFallback() async throws {
        let rawStructuredOutput = #"{"diary_entry":"Tianfu builds local-first agent products, knowledge memory systems, and public-safe profile workflows."}"#
        let generator = NetworkingPromptProfileGenerator(
            summarizer: StubSummaryGenerating(output: rawStructuredOutput)
        )

        let content = try await generator.generateProfile(
            scenario: .jobs,
            prompt: "Generate a hiring profile.",
            personName: "Tianfu Wu",
            context: NetworkingProfileContext(
                summary: "KnowYou context",
                citations: ["wiki/concepts/knowyou.md"]
            )
        )

        XCTAssertEqual(
            content.summary,
            "Tianfu builds local-first agent products, knowledge memory systems, and public-safe profile workflows."
        )
        XCTAssertFalse(content.summary.contains("diary_entry"))
    }

    func testMyWikiNetworkingContextProviderUsesScenarioLensForCareerAndFriends() throws {
        let projectRoot = temporaryDirectory().appending(path: "KnowYouContext", directoryHint: .isDirectory)
        try writeMyWikiPage(
            """
            ---
            type: concept
            title: Work Platform Builder
            tags: [career, product, engineering, agent, collaboration]
            ---

            # Work Platform Builder

            Tianfu can own product architecture, macOS app details, web platform delivery, agent workflows, enterprise AI work, and hiring conversations.
            """,
            to: projectRoot.appending(path: "wiki/concepts/work-platform-builder.md")
        )
        try writeMyWikiPage(
            """
            ---
            type: concept
            title: Social Rhythm and Interests
            tags: [friends, social, interests, activities, personal]
            ---

            # Social Rhythm and Interests

            Tianfu likes relaxed conversations about products, cities, food, creative tools, weekend activities, and meeting thoughtful new friends.
            """,
            to: projectRoot.appending(path: "wiki/concepts/social-rhythm-and-interests.md")
        )

        let provider = MyWikiNetworkingContextProvider()
        let careerContext = try provider.context(
            for: .jobs,
            prompt: "Generate a career profile.",
            projectRoot: projectRoot
        )
        let friendsContext = try provider.context(
            for: .friends,
            prompt: "Generate a personal profile for meeting friends.",
            projectRoot: projectRoot
        )

        XCTAssertEqual(careerContext.citations.first, "wiki/concepts/work-platform-builder.md")
        XCTAssertEqual(friendsContext.citations.first, "wiki/concepts/social-rhythm-and-interests.md")
        XCTAssertTrue(careerContext.summary.contains("agent workflows"))
        XCTAssertTrue(friendsContext.summary.contains("meeting thoughtful new friends"))
    }

    func testMyWikiNetworkingContextProviderCanReadOnlyPagesChangedAfterDate() throws {
        let projectRoot = temporaryDirectory().appending(path: "KnowYouContext", directoryHint: .isDirectory)
        let oldPage = projectRoot.appending(path: "wiki/concepts/old-career-context.md")
        let newPage = projectRoot.appending(path: "wiki/concepts/new-career-context.md")
        try writeMyWikiPage(
            """
            ---
            type: concept
            title: Old Career Context
            tags: [career, agent, product]
            ---

            # Old Career Context

            Tianfu has older agent product context that should already be folded into the profile.
            """,
            to: oldPage
        )
        try writeMyWikiPage(
            """
            ---
            type: concept
            title: New Career Context
            tags: [career, hiring, collaboration, agent]
            ---

            # New Career Context

            Tianfu recently added a new hiring and collaboration signal for incremental profile update.
            """,
            to: newPage
        )
        let cutoff = Date(timeIntervalSince1970: 1_779_840_000)
        try FileManager.default.setAttributes(
            [.modificationDate: cutoff.addingTimeInterval(-60 * 60)],
            ofItemAtPath: oldPage.path
        )
        try FileManager.default.setAttributes(
            [.modificationDate: cutoff.addingTimeInterval(60 * 60)],
            ofItemAtPath: newPage.path
        )

        let context = try MyWikiNetworkingContextProvider().context(
            for: .jobs,
            prompt: "Update a career profile with new hiring and collaboration material.",
            projectRoot: projectRoot,
            changedAfter: cutoff
        )

        XCTAssertEqual(context.citations, ["wiki/concepts/new-career-context.md"])
        XCTAssertTrue(context.summary.contains("New Career Context"))
        XCTAssertFalse(context.summary.contains("Old Career Context"))
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

    func testApprovalStateStorePersistsApprovedProfiles() throws {
        let projectRoot = temporaryDirectory().appending(path: "KnowYouContext", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: projectRoot, withIntermediateDirectories: true)
        let store = NetworkingProfileApprovalStateStore()

        try store.save(
            NetworkingProfileApprovalState(approvedProfileIDs: ["profile-career", "profile-custom"]),
            projectRoot: projectRoot
        )

        XCTAssertEqual(
            store.load(projectRoot: projectRoot),
            NetworkingProfileApprovalState(approvedProfileIDs: ["profile-career", "profile-custom"])
        )
    }

    func testProfileDraftStateStorePersistsGeneratedDraftsForReopen() throws {
        let projectRoot = temporaryDirectory().appending(path: "KnowYouContext", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: projectRoot, withIntermediateDirectories: true)
        let store = NetworkingProfileDraftStateStore()
        let generatedAt = Date(timeIntervalSince1970: 1_779_840_000)
        let updatedAt = Date(timeIntervalSince1970: 1_779_926_400)
        let draft = NetworkingProfileDraft(
            id: "jobs",
            personName: "Tianfu Wu",
            profileLabel: "Career / Hiring",
            summary: "Builds local-first AI products.",
            body: "Long public-safe career profile body.",
            source: .myWiki,
            approvalStatus: .draft,
            citations: ["wiki/concepts/work-platform-builder.md"],
            generatedAt: generatedAt,
            updatedAt: updatedAt
        )

        try store.save(
            NetworkingProfileDraftState(draftsByProfileID: ["profile-career": draft]),
            projectRoot: projectRoot
        )

        XCTAssertEqual(
            store.load(projectRoot: projectRoot),
            NetworkingProfileDraftState(draftsByProfileID: ["profile-career": draft])
        )
    }

    func testProfileDraftStateStorePersistsAdditiveCustomProfilesAndDailyCheck() throws {
        let projectRoot = temporaryDirectory().appending(path: "KnowYouContext", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: projectRoot, withIntermediateDirectories: true)
        let store = NetworkingProfileDraftStateStore()
        let lastCheck = Date(timeIntervalSince1970: 1_779_926_400)
        let custom = NetworkingCustomProfileConfiguration(
            id: "profile-custom-founder-events",
            label: "Founder events",
            useCase: "Meet design-minded founders at small AI product events.",
            imageDirection: "Calm product builder with crisp visual language.",
            tone: "warm",
            redactionNotes: "Do not include exact event locations.",
            createdAt: Date(timeIntervalSince1970: 1_779_840_000)
        )
        let state = NetworkingProfileDraftState(
            draftsByProfileID: [:],
            customProfiles: [custom],
            lastDailyUpdateCheckAt: lastCheck
        )

        try store.save(state, projectRoot: projectRoot)

        XCTAssertEqual(store.load(projectRoot: projectRoot), state)
    }

    func testProfileDraftStateStoreBackfillsLegacyDraftTimestampsFromStateFile() throws {
        let projectRoot = temporaryDirectory().appending(path: "KnowYouContext", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: projectRoot, withIntermediateDirectories: true)
        let store = NetworkingProfileDraftStateStore()
        let draft = NetworkingProfileDraft(
            id: "jobs",
            personName: "Tianfu Wu",
            profileLabel: "Career / Hiring",
            summary: "Legacy summary",
            body: "Legacy body",
            source: .myWiki,
            approvalStatus: .draft
        )
        let legacyData = try JSONEncoder().encode(NetworkingProfileDraftState(draftsByProfileID: ["profile-career": draft]))
        let stateURL = store.stateURL(projectRoot: projectRoot)
        try FileManager.default.createDirectory(at: stateURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try legacyData.write(to: stateURL)
        let modifiedAt = Date(timeIntervalSince1970: 1_779_840_000)
        try FileManager.default.setAttributes([.modificationDate: modifiedAt], ofItemAtPath: stateURL.path)

        let loadedDraft = try XCTUnwrap(store.load(projectRoot: projectRoot).draftsByProfileID["profile-career"])

        XCTAssertEqual(loadedDraft.generatedAt, modifiedAt)
        XCTAssertEqual(loadedDraft.updatedAt, modifiedAt)
    }

    func testProfileUpdatePolicyRunsAtMostDaily() {
        let policy = NetworkingProfileUpdatePolicy()
        let now = Date(timeIntervalSince1970: 1_779_926_400)

        XCTAssertTrue(policy.shouldRunDailyUpdate(now: now, lastCheckedAt: nil))
        XCTAssertFalse(policy.shouldRunDailyUpdate(now: now, lastCheckedAt: now.addingTimeInterval(-60 * 60)))
        XCTAssertTrue(policy.shouldRunDailyUpdate(now: now, lastCheckedAt: now.addingTimeInterval(-25 * 60 * 60)))
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

    func testNetworkingMCPSandboxModeRefusesPublishingWithClearMessage() {
        let state = NetworkingActivationState(
            isEnabled: true,
            personID: "local-person",
            agentTokenPlaintext: "agent-token",
            supabaseURL: URL(string: "https://local.knowyou.invalid")!,
            publishableKey: "local-dev",
            mode: .localSandbox
        )
        let request = #"{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"networking_publish_post","arguments":{"platform_id":"knowyou-jobs","profile_id":"profile-jobs","body":"hello"}}}"#

        let result = NetworkingMCPCommand.run(
            arguments: ["KnowYou", NetworkingMCPCommand.launchArgument, "--project-root", "/tmp/wiki"],
            input: request,
            activationState: state
        )

        XCTAssertEqual(result.exitCode, 0)
        XCTAssertTrue(result.stdout.contains("local sandbox mode"))
        XCTAssertFalse(result.stdout.contains("agent-token"))
    }

    func testNetworkingMCPPublishPostCallsPlatformRPCWithoutLeakingToken() throws {
        let state = NetworkingActivationState(
            isEnabled: true,
            personID: "person-uuid",
            agentTokenPlaintext: "agent-token",
            supabaseURL: URL(string: "https://example.supabase.co")!,
            publishableKey: "sb_publishable_test",
            mode: .platform,
            profileIDMapping: ["profile-jobs": "platform-profile-uuid"]
        )
        let capturedRequests = MCPRequestRecorder()
        let transport: NetworkingPlatformTransport = { request in
            capturedRequests.append(request)
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: 200,
                httpVersion: "HTTP/1.1",
                headerFields: nil
            )!
            return (Data("\"post-uuid\"".utf8), response)
        }
        let request = #"{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"networking_publish_post","arguments":{"platform_id":"knowyou-jobs","profile_id":"profile-jobs","body":"hello"}}}"#

        let result = NetworkingMCPCommand.run(
            arguments: ["KnowYou", NetworkingMCPCommand.launchArgument, "--project-root", "/tmp/wiki"],
            input: request,
            activationState: state,
            transport: transport
        )

        XCTAssertEqual(result.exitCode, 0)
        XCTAssertTrue(result.stdout.contains(#""post_id":"post-uuid""#))
        XCTAssertTrue(result.stdout.contains(#""author_type":"ai""#))
        XCTAssertTrue(result.stdout.contains("platform-profile-uuid"))
        XCTAssertFalse(result.stdout.contains("agent-token"), "the plaintext token must never appear in MCP output")

        let rpcRequest = try XCTUnwrap(capturedRequests.requests.first)
        XCTAssertEqual(rpcRequest.url?.path, "/rest/v1/rpc/networking_agent_create_post")
        let bodyText = String(decoding: rpcRequest.httpBody ?? Data(), as: UTF8.self)
        XCTAssertTrue(bodyText.contains("agent-token"), "the token goes to the platform RPC, not to the MCP caller")
    }

    func testNetworkingMCPAgentHomeReturnsQueues() throws {
        let state = NetworkingActivationState(
            isEnabled: true,
            personID: "person-uuid",
            agentTokenPlaintext: "agent-token",
            supabaseURL: URL(string: "https://example.supabase.co")!,
            publishableKey: "sb_publishable_test",
            mode: .platform
        )
        let transport: NetworkingPlatformTransport = { request in
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: 200,
                httpVersion: "HTTP/1.1",
                headerFields: nil
            )!
            let home = #"{"needsReply":[],"potentialMatches":[{"id":"task-1"}],"savedForYou":[]}"#
            return (Data(home.utf8), response)
        }
        let request = #"{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"networking_agent_home","arguments":{"platform_id":"knowyou-jobs"}}}"#

        let result = NetworkingMCPCommand.run(
            arguments: ["KnowYou", NetworkingMCPCommand.launchArgument, "--project-root", "/tmp/wiki"],
            input: request,
            activationState: state,
            transport: transport
        )

        XCTAssertEqual(result.exitCode, 0)
        XCTAssertTrue(result.stdout.contains(#""potentialMatches""#))
        XCTAssertTrue(result.stdout.contains("task-1"))
        XCTAssertFalse(result.stdout.contains("agent-token"))
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

        XCTAssertTrue(platform.canRunAutomation(with: [generated, draft], approvedProfileIDs: ["work"]))
        XCTAssertFalse(platform.canRunAutomation(with: [generated, draft], approvedProfileIDs: []))
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

    func testCockpitItemsFromAgentHomeMapThreeQueuesToDirections() {
        let home: [String: Any] = [
            "needsReply": [
                [
                    "id": "task-event-1",
                    "summary": "回复别人对我内容的新互动",
                    "publicReferenceID": "comment-1",
                    "publicEvidence": ["reply_to_my_comment on post-1"],
                    "reasonCodes": ["direct_inbox"],
                ],
            ],
            "potentialMatches": [
                [
                    "id": "task-candidate-post-2",
                    "summary": "候选帖子与当前公开 profile 相关",
                    "publicReferenceID": "post-2",
                    "publicEvidence": ["founding engineer / agent runtime"],
                    "reasonCodes": ["watching_community"],
                ],
            ],
            "savedForYou": [
                [
                    "id": "task-candidate-post-3",
                    "summary": "候选内容需要人类处理",
                    "publicReferenceID": "post-3",
                    "publicEvidence": [],
                    "reasonCodes": ["risky_content"],
                ],
            ],
        ]

        let items = NetworkingCockpitPresentation.cockpitItems(fromAgentHome: home, platformID: "knowyou-jobs")

        XCTAssertEqual(items.map(\.direction), [.inbound, .highlight, .outbound])
        XCTAssertEqual(items.map(\.platformID), Array(repeating: "knowyou-jobs", count: 3))
        XCTAssertEqual(items[0].publicReferenceID, "comment-1")
        XCTAssertEqual(items[0].id, "knowyou-jobs-task-event-1")
        XCTAssertEqual(items[1].publicSummary, "founding engineer / agent runtime")
        XCTAssertTrue(items[2].privateReason.contains("risky_content"))
    }

    func testCockpitItemsFromAgentHomeSkipsTasksWithoutIDs() {
        let home: [String: Any] = [
            "needsReply": [["summary": "missing id"]],
            "potentialMatches": [],
            "savedForYou": [],
        ]

        let items = NetworkingCockpitPresentation.cockpitItems(fromAgentHome: home, platformID: "knowyou-jobs")

        XCTAssertTrue(items.isEmpty)
    }

    private func temporaryDirectory() -> URL {
        FileManager.default.temporaryDirectory
            .appending(path: "knowyou-networking-tests-\(UUID().uuidString)", directoryHint: .isDirectory)
    }

    private func writeMyWikiPage(_ contents: String, to url: URL) throws {
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try contents.write(to: url, atomically: true, encoding: .utf8)
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

private final class CapturingJSONSummaryGenerating: JSONSummaryGenerating, @unchecked Sendable {
    let output: String
    private(set) var capturedPrompt: String?
    private(set) var capturedSchema: String?

    init(output: String) {
        self.output = output
    }

    func summarize(dayKey: String, markdown: String, context: SummaryInvocationContext) async throws -> String {
        capturedPrompt = markdown
        return output
    }

    func summarizeJSON(
        dayKey: String,
        prompt: String,
        schema: String,
        context: SummaryInvocationContext
    ) async throws -> String {
        capturedPrompt = prompt
        capturedSchema = schema
        return output
    }
}

private final class MCPRequestRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var storage: [URLRequest] = []

    var requests: [URLRequest] {
        lock.lock()
        defer { lock.unlock() }
        return storage
    }

    func append(_ request: URLRequest) {
        lock.lock()
        defer { lock.unlock() }
        storage.append(request)
    }
}
