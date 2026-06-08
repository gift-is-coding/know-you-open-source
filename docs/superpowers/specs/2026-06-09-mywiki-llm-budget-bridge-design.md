# MyWiki LLM Budget Bridge Design

## Goal

MyWiki ingest must preserve the LLM output budget requested by the bundled llm-wiki pipeline when it calls the shared Diary Engine. Generation currently asks for a larger response budget than analysis, but the KnowYou bridge drops that request before Swift sees it.

## Scope

- Forward `temperature`, `max_tokens`, and `reasoning` from the headless TypeScript runner to Swift.
- Decode those fields in `MyWikiLLMBridge` and pass them through the shared `MyWikiLLMCompleting` interface.
- Apply `max_tokens` and `temperature` to cloud providers using each provider's native request shape.
- Apply `max_tokens` to Codex Direct Responses requests.
- Preserve `reasoning: off` through provider request construction for engines where it controls visible-output budget: Gemini thinking budget, Qwen3 thinking template, and Codex Direct reasoning payload omission.
- Keep CLI engines compatible by accepting the options but not inventing unsupported command flags.
- Harden adjacent ingest losses that can silently hide generated work: CRLF review blocks, unclosed code fences around FILE closers, source-summary fallback overwrite, embedding page id collisions, and fixed source truncation budgets.

## Non-Goals

- Do not reintroduce a separate `LLM Wiki.app`.
- Do not add user-facing MyWiki API configuration.
- Do not redesign the upstream ontology generation prompt or split generation into separate per-page calls in this pass.

## Expected Behavior

- A generation request with `max_tokens: 8192` reaches Swift as `maxTokens == 8192`.
- Anthropic sends `max_tokens: 8192` instead of the prior fixed `4096`.
- OpenAI Responses sends `max_output_tokens: 8192`; OpenAI-compatible Chat sends `max_tokens: 8192`; Gemini sends `generation_config.max_output_tokens: 8192`.
- MyWiki `reasoning: off` disables Gemini thinking budget, disables Qwen3 template thinking, and omits Codex Direct reasoning/include fields for that MyWiki request.
- Review blocks parse with LF or CRLF line endings.
- A FILE block with an unclosed code fence still closes at `---END FILE---`, preserving the page and surfacing a warning instead of dropping the whole block.
- Source truncation follows the configured `maxContextSize`; invalid or missing configs keep the prior 50,000-character fallback behavior.
- Embeddings use stable ids that include the wiki subfolder, so `entities/foo.md` and `concepts/foo.md` do not collide.
- If a source summary already exists and the current generation omitted one, fallback summary creation does not overwrite the existing page.

## Verification

- Vitest focused bridge/parser/ingest tests.
- Focused Swift tests for `MyWikiLLMBridge`, `MyWikiPipelineBridge`, `CloudSummarizer`, `CodexDirectSummarizer`, and `CLISummarizer`.
- `xcodebuild build -scheme KnowYou -destination 'platform=macOS'`.
