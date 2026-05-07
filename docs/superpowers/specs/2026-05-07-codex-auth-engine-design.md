# Codex Auth Engine Design

## Context

KnowYou currently supports these diary engines:

- OpenAI API
- Claude Code CLI
- Codex CLI
- Gemini CLI
- Openclaw CLI

The Codex CLI engine shells out through `codex exec`. That path is reliable and public from KnowYou's point of view, but every request pays process startup, CLI initialization, prompt handoff, schema/output-file handling, and terminal-output normalization costs.

OpenClaw implements a faster parallel path for Codex by reusing the local Codex CLI ChatGPT OAuth login state and calling the Codex backend directly. The relevant OpenClaw behavior is:

- Resolve `CODEX_HOME`, falling back to `~/.codex`.
- On macOS, read Keychain service `Codex Auth` with account `cli|sha256(realCodexHome).prefix(16)`.
- If Keychain lookup fails, read `<codexHome>/auth.json`.
- Extract `tokens.access_token`, `tokens.refresh_token`, and optional `tokens.account_id`.
- Parse token expiry and `chatgpt_account_id` from the access token JWT.
- Refresh expired credentials through `https://auth.openai.com/oauth/token`.
- Call `https://chatgpt.com/backend-api/codex/responses` with Codex-specific headers and a Responses-style streaming request body.

KnowYou should add the same capability as an independent diary engine, not as a replacement for the existing Codex CLI engine.

## Goal

Add a new `Codex Auth` diary engine that runs in parallel with the other engines and uses the user's existing local Codex ChatGPT OAuth login state to call the Codex backend directly.

The new engine must behave as its own selectable channel:

- `Codex (CLI)` continues to call `codex exec`.
- `Codex Auth` reads Codex OAuth credentials and calls the Codex backend directly.
- Neither engine silently mutates into the other.

## Non-Goals

- Do not remove or rewrite `Codex (CLI)`.
- Do not add automatic fallback from `Codex Auth` to `Codex (CLI)` in this first version.
- Do not store Codex access or refresh tokens in KnowYou `UserDefaults`.
- Do not display access tokens, refresh tokens, account IDs, or raw auth records in UI or logs.
- Do not implement a fresh browser OAuth login flow inside KnowYou. The first version only reuses the Codex CLI login state already present on the Mac.
- Do not make `Codex Auth` the automatic default over existing green engines.

## User Experience

Settings and the diary engine selector should show a new engine:

```text
Codex Auth
```

The configuration area for `Codex Auth` does not need an API key or executable path. It should explain that KnowYou will reuse the local Codex login state on this Mac.

Probe states:

- Gray: no usable Codex login state was found.
- Yellow: a credential exists but refresh or backend verification failed.
- Green: KnowYou successfully sent a smoke-test request through Codex Auth and received non-empty text.

When selected as the default engine, `Codex Auth` participates in generation exactly like the other `SummaryGenerating` engines. If it fails during generation, the existing daily story fallback rules still apply at the application level.

## Architecture

Add `DiaryEngine.codexAuth` as a new case alongside the existing engines.

Introduce four focused components under `KnowYou/Services/Summary/`:

- `CodexAuthStore`: discovers and reads Codex credentials from Keychain or `auth.json`.
- `CodexOAuthRefresher`: refreshes expired OAuth credentials and writes refreshed values back to the same Codex storage source when possible.
- `CodexJWT`: decodes the access-token payload to extract expiry and `chatgpt_account_id`.
- `CodexDirectSummarizer`: sends KnowYou summarization prompts to the Codex backend and returns the final text.

Keep these boundaries strict:

- Auth discovery does not know about diary prompts.
- Token refresh does not know about UI state.
- JWT parsing does not perform network or filesystem work.
- The summarizer only asks an auth provider for a valid credential, then performs the Codex request.

## Credential Discovery

`CodexAuthStore` resolves Codex home as:

1. If `environment["CODEX_HOME"]` is non-empty, expand and resolve it.
2. Otherwise use `~/.codex`.
3. If the path exists, use its real path for Keychain account derivation; otherwise use the expanded path.

On macOS, Keychain lookup is attempted first:

```text
service: Codex Auth
account: cli|sha256(realCodexHome).prefix(16)
```

The stored secret is expected to be a JSON auth record containing `tokens.access_token` and `tokens.refresh_token`.

If Keychain lookup fails, the store reads:

```text
<codexHome>/auth.json
```

The file path is accepted only when:

- JSON parses successfully.
- `auth_mode` is either missing or `chatgpt`; `chatgpt` is the expected modern mode.
- `tokens.access_token` is a non-empty string.
- `tokens.refresh_token` is a non-empty string.

The resulting credential contains:

- `accessToken`
- `refreshToken`
- `expiresAt`
- `accountID`
- `source`

`source` is either Keychain or auth file, including the information needed to write refreshed credentials back to that same source.

## JWT Parsing

`CodexJWT` decodes JWT payloads using base64url rules. It extracts:

- `exp` as token expiry in seconds since epoch.
- `https://api.openai.com/auth.chatgpt_account_id` as the ChatGPT account id.

If `exp` is missing, the store falls back to a conservative one-hour expiry estimate based on `last_refresh`, auth file mtime, or the current time.

If `chatgpt_account_id` is missing, `Codex Auth` is unavailable. The backend request depends on the `chatgpt-account-id` header, so guessing or using a UI-visible account value is not acceptable.

## Token Refresh

Before every probe or summarization request, `CodexDirectSummarizer` asks for a valid credential.

If the credential is still valid with a small safety margin, it is used as-is.

If expired or close to expiry, `CodexOAuthRefresher` sends:

```http
POST https://auth.openai.com/oauth/token
Content-Type: application/x-www-form-urlencoded

grant_type=refresh_token
refresh_token=<refresh token>
client_id=app_EMoamEEZ73f0CkXaXp7hrann
```

The response must include:

- `access_token`
- `refresh_token`
- `expires_in`

The refreshed access token is parsed again to verify `chatgpt_account_id`.

When refresh succeeds:

- If the source was Keychain, update the same `Codex Auth` Keychain item.
- If the source was `auth.json`, update the same file.
- Preserve unrelated fields in the existing auth record.
- Set `auth_mode` to `chatgpt` when missing.
- Set `last_refresh` to the current ISO timestamp.

When refresh fails, no partial credential should be persisted.

## Codex Backend Request

`CodexDirectSummarizer` sends requests to:

```text
https://chatgpt.com/backend-api/codex/responses
```

Headers:

```text
Authorization: Bearer <accessToken>
chatgpt-account-id: <accountID>
originator: pi
OpenAI-Beta: responses=experimental
accept: text/event-stream
content-type: application/json
```

The first version mirrors OpenClaw's `originator: pi` header for backend compatibility.

The body uses the Codex Responses shape:

```json
{
  "model": "gpt-5.4",
  "store": false,
  "stream": true,
  "instructions": "You are KnowYou's diary writer...",
  "input": [
    {
      "role": "user",
      "content": [
        {
          "type": "input_text",
          "text": "KnowYou prompt text"
        }
      ]
    }
  ],
  "text": { "verbosity": "medium" },
  "include": ["reasoning.encrypted_content"],
  "tool_choice": "auto",
  "parallel_tool_calls": true,
  "reasoning": {
    "effort": "high",
    "summary": "auto"
  }
}
```

The first implementation should use SSE over `URLSession.bytes(for:)`. WebSocket support is not required for this feature.

The summarizer consumes SSE `data:` events until it sees a completed response event. It returns the same final text extraction semantics used by `CloudSummarizer`: prefer `output_text`, otherwise concatenate message content items of type `output_text`.

## Configuration

`SummarizerConfig` should not store a token for `Codex Auth`.

The only persisted value needed for this feature is the selected default engine, which is already handled by `SummarizerConfig.defaultEngine`.

Optional future configuration, such as Codex model choice, can be added later. The first version should hardcode a conservative model default matching OpenClaw's current Codex provider behavior.

## Engine Probe

`EngineProbe` gets a new branch for `.codexAuth`.

Probe behavior:

1. Resolve a valid Codex credential.
2. Refresh it when needed.
3. Send a small Codex backend request with input `Reply with OK.`
4. Return green when a non-empty text response is parsed.

Probe details must not include tokens, account IDs, raw Keychain errors, or raw backend response bodies.

## Security And Privacy

`Codex Auth` is a third-party summarizer path. It sends filtered diary material to OpenAI/ChatGPT Codex backend when selected.

Required safeguards:

- Never log access tokens, refresh tokens, account IDs, auth JSON, or Authorization headers.
- Do not store Codex credentials in KnowYou's own settings.
- Keep token refresh writes scoped to the original Codex storage source.
- Use clear UI copy that this engine reuses the local Codex login state.
- Keep the existing privacy filter and prompt-budget trimming ahead of all summarizer calls.
- Add privacy documentation noting `Codex Auth` as another optional external summarizer.

## Error Handling

Use typed errors internally, then map them to user-safe messages.

Expected unavailable cases:

- Codex home missing.
- Keychain item missing and `auth.json` missing.
- Auth record malformed.
- Access token lacks account id.
- Refresh token missing.
- Refresh request rejected.
- Backend request rejected.
- SSE response malformed or empty.

User-facing messages should describe the recovery path:

- Sign in with Codex CLI again when login state is missing or expired.
- Retest the engine after signing in.
- Use `Codex (CLI)` or another engine if direct Codex Auth remains unavailable.

## Testing

Tests should cover the feature without reading the developer's real Keychain or real `~/.codex`.

Required focused tests:

- `CodexJWTTests`
  - Decodes `exp`.
  - Decodes `chatgpt_account_id`.
  - Rejects malformed tokens.

- `CodexAuthStoreTests`
  - Computes the Keychain account from a known Codex home path.
  - Prefers Keychain JSON over auth file JSON.
  - Falls back to auth file JSON.
  - Rejects malformed or incomplete auth records.
  - Preserves unrelated auth record fields when building refreshed records.

- `CodexOAuthRefresherTests`
  - Sends form-encoded refresh requests.
  - Parses refreshed credentials.
  - Rejects responses missing required fields.
  - Does not log or expose token values in errors.

- `CodexDirectSummarizerTests`
  - Sends the expected URL and headers.
  - Includes `store: false` and `stream: true`.
  - Parses SSE completion into output text.
  - Surfaces empty responses as failure.

- `SummarizerConfigTests`
  - `.codexAuth` round-trips as default engine.
  - `makeSummarizer(for: .codexAuth)` returns `CodexDirectSummarizer`.

- `EngineProbeTests`
  - Missing auth returns gray.
  - Refresh/backend failure returns yellow.
  - Successful backend smoke test returns green.

## Documentation Updates

During implementation, update:

- `docs/architecture.md`: add `Codex Auth` to generation layer and engine status behavior.
- `docs/requirements-spec.md`: add `Codex Auth` to optional diary engines.
- `PRIVACY.md`: clarify that `Codex Auth` is an optional external summarizer that reuses local Codex login state.

## Risks

The backend endpoint is not a stable public OpenAI API surface. The implementation should isolate this behavior in `CodexDirectSummarizer` and keep `Codex (CLI)` available as a separate engine.

The OAuth client behavior may change. KnowYou should not attempt to hide this risk. If refresh or backend calls start failing, the engine should become yellow rather than corrupting credentials or silently switching channels.

The user's Codex OAuth credentials are highly sensitive. The implementation must treat them at least as carefully as API keys, with stronger logging discipline because the credentials originate from another tool's login state.

## Approval

This design implements option 2 from the product discussion: `Codex Auth` is a standalone channel parallel to the other diary engines.
