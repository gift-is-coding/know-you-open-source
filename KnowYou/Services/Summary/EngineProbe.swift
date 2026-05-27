import Foundation

struct EngineProbeResult: Equatable {
    let engine: DiaryEngine
    let state: EngineIndicatorState
    let detail: String
    let verifiedAt: Date?
}

struct EngineProbe: Sendable {
    let session: URLSession
    let processRunner: ProcessRunning

    init(
        session: URLSession = .shared,
        processRunner: ProcessRunning = SystemProcessRunner()
    ) {
        self.session = session
        self.processRunner = processRunner
    }

    func probe(engine: DiaryEngine, config: SummarizerConfig, environment: [String: String]) async -> EngineProbeResult {
        var engineConfig = config
        engineConfig.defaultEngine = engine

        switch engine {
        case .none:
            return makeResult(engine: engine, state: .gray, detail: "No engine selected.", verifiedAt: nil)
        case .llmAPI:
            return await probeAPI(config: engineConfig)
        case .codexAuth:
            return await probeCodexAuth(environment: environment)
        case .claudeCLI, .codexCLI, .geminiCLI, .openclawCLI:
            return await probeCLI(engine: engine, config: engineConfig, environment: environment)
        }
    }

    private func probeCLI(
        engine: DiaryEngine,
        config: SummarizerConfig,
        environment: [String: String]
    ) async -> EngineProbeResult {
        guard
            let tool = tool(for: engine),
            let executablePath = SummarizerConfig.resolvedExecutablePath(
                configuredPath: configuredPath(for: engine, in: config),
                commandName: commandName(for: engine),
                environment: environment
            )
        else {
            return makeResult(
                engine: engine,
                state: .gray,
                detail: "Executable not found.",
                verifiedAt: nil
            )
        }

        let summarizer = CLISummarizer(tool: tool, executablePath: executablePath, runner: processRunner)
        do {
            _ = try await summarizer.smokeTest()
            return makeResult(
                engine: engine,
                state: .green,
                detail: "Smoke test succeeded.",
                verifiedAt: Date()
            )
        } catch {
            return makeResult(
                engine: engine,
                state: .yellow,
                detail: "Smoke test failed: \(error.localizedDescription)",
                verifiedAt: Date()
            )
        }
    }

    private func probeAPI(config: SummarizerConfig) async -> EngineProbeResult {
        let providerConfig = config.activeLLMAPIProviderConfig
        let providerName = providerConfig.descriptor.displayName

        guard
            providerConfig.isComplete,
            providerConfig.validatedBaseURL() != nil
        else {
            return makeResult(
                engine: .llmAPI,
                state: .gray,
                detail: "API configuration is incomplete.",
                verifiedAt: nil
            )
        }

        do {
            let client = LLMAPIClient(providerConfig: providerConfig, session: session)
            let outputText = try await client.complete(input: "Reply with OK.")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard !outputText.isEmpty else {
                return makeResult(
                    engine: .llmAPI,
                    state: .yellow,
                    detail: "API response did not include any text.",
                    verifiedAt: Date()
                )
            }

            return makeResult(
                engine: .llmAPI,
                state: .green,
                detail: "\(providerName) returned non-empty text.",
                verifiedAt: Date()
            )
        } catch {
            return makeResult(
                engine: .llmAPI,
                state: .yellow,
                detail: "API request failed: \(error.localizedDescription)",
                verifiedAt: Date()
            )
        }
    }

    private func probeCodexAuth(environment: [String: String]) async -> EngineProbeResult {
        let store = CodexAuthStore(environment: environment)
        let refresher = CodexOAuthRefresher(session: session)
        let summarizer = CodexDirectSummarizer(
            credentialProvider: CodexCredentialProvider(store: store, refresher: refresher),
            session: session
        )

        do {
            _ = try await summarizer.smokeTest()
            return makeResult(
                engine: .codexAuth,
                state: .green,
                detail: "Codex Auth returned non-empty text.",
                verifiedAt: Date()
            )
        } catch CodexAuthStoreError.credentialNotFound {
            return makeResult(
                engine: .codexAuth,
                state: .gray,
                detail: "Codex Auth credentials not found. Sign in with Codex CLI.",
                verifiedAt: nil
            )
        } catch {
            return makeResult(
                engine: .codexAuth,
                state: .yellow,
                detail: "Codex Auth request failed: \(error.localizedDescription)",
                verifiedAt: Date()
            )
        }
    }

    private func makeResult(
        engine: DiaryEngine,
        state: EngineIndicatorState,
        detail: String,
        verifiedAt: Date?
    ) -> EngineProbeResult {
        EngineProbeResult(
            engine: engine,
            state: state,
            detail: detail,
            verifiedAt: verifiedAt
        )
    }

    private func tool(for engine: DiaryEngine) -> CLISummarizer.Tool? {
        switch engine {
        case .claudeCLI:
            return .claude
        case .codexCLI:
            return .codex
        case .geminiCLI:
            return .gemini
        case .openclawCLI:
            return .openclaw
        case .none, .llmAPI, .codexAuth:
            return nil
        }
    }

    private func commandName(for engine: DiaryEngine) -> String {
        switch engine {
        case .claudeCLI:
            return "claude"
        case .codexCLI:
            return "codex"
        case .geminiCLI:
            return "gemini"
        case .openclawCLI:
            return "openclaw"
        case .none, .llmAPI, .codexAuth:
            return ""
        }
    }

    private func configuredPath(for engine: DiaryEngine, in config: SummarizerConfig) -> String {
        switch engine {
        case .claudeCLI:
            return config.claudeCLIPath
        case .codexCLI:
            return config.codexCLIPath
        case .geminiCLI:
            return config.geminiCLIPath
        case .openclawCLI:
            return config.openclawCLIPath
        case .none, .llmAPI, .codexAuth:
            return ""
        }
    }

}
