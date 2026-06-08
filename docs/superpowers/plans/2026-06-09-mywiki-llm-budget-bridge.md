# MyWiki LLM Budget Bridge Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Preserve MyWiki ingest LLM request budgets across the TypeScript runner, Swift bridge, and shared Diary Engine providers.

**Architecture:** Add a small Swift request-options type and pass it through the existing `MyWikiLLMCompleting` protocol. Keep provider-specific translation at the final request-construction layer, mirroring llm-wiki's TypeScript provider adapters.

**Tech Stack:** Swift, XCTest, TypeScript, Vitest, bundled llm-wiki runner.

---

### Task 1: Bridge Request Options

**Files:**
- Modify: `ThirdParty/llm_wiki/src/headless/knowyou-bridge-transport.ts`
- Test: `ThirdParty/llm_wiki/src/headless/knowyou-bridge-transport.test.ts`
- Modify: `KnowYou/Services/MyWiki/MyWikiLLMBridge.swift`
- Test: `KnowYouTests/MyWikiLLMBridgeTests.swift`
- Test: `KnowYouTests/MyWikiPipelineBridgeTests.swift`

- [x] Add failing tests that assert `max_tokens` and `reasoning` are serialized by TS, decoded by Swift, and passed to the injected engine.
- [x] Implement direct JSON fields `max_tokens` and `reasoning` in the bridge request.
- [x] Pass request options through `MyWikiLLMCompleting`.

### Task 2: Provider Request Translation

**Files:**
- Modify: `KnowYou/Services/Summary/CloudSummarizer.swift`
- Modify: `KnowYou/Services/Summary/CodexDirectSummarizer.swift`
- Modify: `KnowYou/Services/Summary/CLISummarizer.swift`
- Test: `KnowYouTests/CloudSummarizerTests.swift`
- Test: `KnowYouTests/CodexDirectSummarizerTests.swift`
- Test: `KnowYouTests/CLISummarizerTests.swift`

- [x] Add failing tests for Anthropic, OpenAI Responses, OpenAI Chat, Gemini, Codex Direct, CLI compatibility, and provider-specific `reasoning: off` handling.
- [x] Add optional completion options to `LLMAPIClient.complete`.
- [x] Map options to provider-native JSON keys, including Gemini/Qwen3/Codex Direct reasoning-off controls.
- [x] Keep CLI raw command arguments unchanged while accepting the new protocol signature.

### Task 3: Ingest Parser and Indexing Hardening

**Files:**
- Modify: `ThirdParty/llm_wiki/src/lib/ingest.ts`
- Test: `ThirdParty/llm_wiki/src/lib/ingest-parse.test.ts`
- Test: `ThirdParty/llm_wiki/src/lib/ingest.scenarios.test.ts`

- [x] Add failing tests for CRLF review blocks.
- [x] Add failing tests for unclosed code fences that previously swallowed `---END FILE---`.
- [x] Add failing tests that source truncation follows `maxContextSize` instead of a fixed 50,000-character cap.
- [x] Add failing tests that existing source summaries are not overwritten by fallback summaries.
- [x] Add failing tests that embedding page ids include the relative wiki path.
- [x] Normalize CRLF in review parsing, preserve pages with unclosed code fences, use `maxContextSize` for source truncation, skip fallback overwrite when the file exists, and derive embedding ids from normalized relative paths.

### Task 4: Verification

**Commands:**
- `cd ThirdParty/llm_wiki && npm run test:mocks -- src/headless/knowyou-bridge-transport.test.ts src/lib/ingest-parse.test.ts src/lib/ingest.scenarios.test.ts`
- `xcodebuild test -scheme KnowYou -destination 'platform=macOS' -only-testing:KnowYouTests/MyWikiLLMBridgeTests -only-testing:KnowYouTests/MyWikiPipelineBridgeTests -only-testing:KnowYouTests/CloudSummarizerTests -only-testing:KnowYouTests/CodexDirectSummarizerTests -only-testing:KnowYouTests/CLISummarizerTests`
- `xcodebuild build -scheme KnowYou -destination 'platform=macOS'`
