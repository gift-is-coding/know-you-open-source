# Spec: Diary Engine Selector And Availability Detection

**Date:** 2026-04-10  
**Branch:** dev  
**Status:** Draft

---

## Problem

The app currently treats summarizer selection as a conventional Settings form. That model is too hidden and too static for a feature that now needs to behave like an active runtime control.

The desired experience is different:

- The top-right area of the main app should always show which diary engine is currently selected.
- Users should be able to open a first-level engine panel and switch the default engine directly there.
- The app should detect which engines are actually available on the local machine.
- The app should give each engine a simple readiness signal using a small status light.
- API-based engines need deeper configuration than CLI-based engines, so API setup needs its own second-level detail view.

The current product supports OpenAI API, Claude Code CLI, Codex CLI, and Gemini CLI as optional summarizers. This feature expands that product surface into a visible engine system with five named engines:

- Claude Code
- Codex CLI
- Gemini CLI
- Openclaw CLI
- API

---

## Goals

1. Turn the top-right control into an always-visible diary engine entry point instead of a hidden-only settings flow.
2. Let users see the current default engine from the outer UI without opening Settings first.
3. Let users open a first-level panel that shows all five engines, their status lights, and the current default selection.
4. Detect local engine availability by running a short smoke test rather than only checking whether configuration exists.
5. Support OpenAI-compatible API configuration through a second-level API detail screen with `baseURL`, `token`, and `model`.
6. Keep secret handling safe by storing API tokens outside ordinary app storage.

## Non-Goals

- Replacing the existing fallback story generation path
- Redesigning onboarding around engine setup
- Supporting arbitrary provider-specific request shapes beyond OpenAI-compatible API format
- Building a full plugin marketplace or engine-install flow
- Automatically fixing missing CLI tools for the user

---

## Approaches Considered

### Approach A: Keep full engine configuration inside the Settings window

This is the smallest UI change and reuses the current `SettingsView` pattern.

Trade-offs:

- Lowest implementation risk
- Weak match for the requested interaction because engine choice remains hidden behind a generic settings entry
- Poor visibility for current default engine and runtime readiness

### Approach B: Top-right engine entry with a first-level engine panel and API second-level detail

This makes engine selection a visible product control while containing complexity by keeping only API-specific setup behind one deeper screen.

Trade-offs:

- Best match for the requested interaction model
- Keeps common operations, checking status and switching the default engine, in one surface
- Requires a clearer split between engine runtime state and engine configuration state

### Approach C: Top-right quick switch only, with detailed configuration still delegated to Settings

This preserves a simple top-right control while leaving complex setup in the existing settings surface.

Trade-offs:

- Moderately low implementation cost
- Still feels split and indirect
- API becomes awkward because users can see it in the engine switcher but cannot finish setup there

### Recommendation

Choose **Approach B**.

It best matches the requested behavior: the top-right control becomes a true engine entry point, the first-level panel becomes the place to pick the default engine and inspect availability, and only the API engine needs deeper configuration.

---

## Design

### 1. Top-Right Entry Control

The top-right control should stop behaving like a generic settings icon.

Instead, it should become a compact engine entry that always shows:

- the current default engine name
- a disclosure affordance or angle badge that indicates it can open a panel
- a three-color status light representing the current default engine state

Examples of displayed labels:

- `Codex CLI`
- `Claude Code`
- `API`

This control is not only informational. Clicking it opens the first-level engine panel.

If no engine is currently usable, the control should still display the persisted default selection when one exists, but the light reflects the current runtime state rather than the saved preference.

### 2. First-Level Engine Panel

Opening the top-right control reveals the primary engine panel.

This panel lists the five supported engines:

- Claude Code
- Codex CLI
- Gemini CLI
- Openclaw CLI
- API

Each row should include:

- engine name
- short descriptive label
- current three-color status light
- concise status text
- row-level action
- visible selected-state treatment when this row is the current default engine

The first-level panel is the place where users directly choose the default engine.

Recommended row actions:

- CLI rows: `Test` or `Retest`
- API row: `Configure`

The panel should also provide a global `Retest All` action and a lightweight timestamp or label indicating when engine detection was last refreshed.

### 3. Default Engine Selection Rules

The first-level panel should allow direct default-engine selection, but only for engines that are actually ready.

Selection rules:

- Green engine: selectable as default
- Yellow engine: not selectable as default yet
- Gray engine: not selectable as default

This avoids a misleading configuration where the user can mark an engine as default even though the app has not verified it can generate a diary with that engine.

If the currently persisted default engine later becomes unavailable, the app should keep showing it as the chosen default but reflect the degraded runtime status using the outer light and the panel row state. The app should not silently switch the default to another engine.

### 4. Status Light Model

The UI should use only three colors:

- Gray
- Yellow
- Green

Status meanings:

#### Gray

Use gray when the engine is not configured enough to attempt a real test.

Examples:

- CLI executable cannot be found
- API configuration is incomplete

#### Yellow

Use yellow for all intermediate or unsuccessful non-gray states.

Examples:

- CLI executable is found but has not been verified yet
- API fields are complete but the connection has not been tested yet
- The last smoke test failed
- The last smoke test timed out
- The command launched but returned empty or invalid output

This merges the previous "warning" and "error" states into one simpler "not yet trustworthy" state, which matches the requested UI simplification.

#### Green

Use green only when the app has successfully run the engine-specific smoke test and received a valid non-empty output in the expected shape.

### 5. Engine Detection Model

The app should distinguish between lightweight discovery and real verification.

#### CLI Engines

For Claude Code, Codex CLI, Gemini CLI, and Openclaw CLI, detection should happen in two steps:

1. executable discovery
2. smoke test

Executable discovery rules:

- first check the configured path for that engine, if present
- otherwise fall back to resolving the command from `PATH`

Smoke test rules:

- run a very short fixed prompt
- require normal process exit
- require non-empty output
- cap execution with a short timeout

The smoke test prompt must be static and not derived from the user’s diary content.

#### API Engine

For API, detection should also happen in two steps:

1. configuration completeness check
2. connection smoke test

Configuration completeness requires all of:

- `baseURL`
- `token`
- `model`

Smoke test rules:

- send a minimal OpenAI-compatible request
- require a successful HTTP response
- require extractable non-empty text output from the response
- treat incompatible or malformed success responses as yellow, not green

### 6. API Second-Level Detail Screen

The API row in the first-level panel should open a second-level detail view.

This screen should contain:

- `Base URL`
- `API Token`
- `Model`
- `Test Connection`
- short help text explaining that the format is OpenAI-compatible by default
- optional provider/help links that point users to token-generation pages or setup docs

The API detail view is configuration-specific and should not force users through the full app Settings window.

When the user edits any API field:

- the saved API engine state should return to gray if fields become incomplete
- otherwise it should return to yellow until `Test Connection` succeeds again

### 7. Persistence And Secret Handling

Persisted configuration needs to separate normal preferences from secrets.

Store in ordinary app preferences:

- selected default engine
- CLI executable paths
- API `baseURL`
- API `model`
- last known non-secret runtime metadata such as verification timestamps or non-sensitive state

Store in Keychain:

- API token

Do not persist API token in:

- SQLite
- story artifacts
- plain logs
- user-visible status text

### 8. Runtime Behavior

Engine detection should be user-visible but not disruptive.

Recommended behavior:

- when the first-level panel opens, perform lightweight discovery immediately
- if an engine is discoverable and needs verification, allow explicit `Test` / `Retest`
- allow `Retest All` from the panel
- when API settings change, only API returns to an unverified state

The app should not automatically switch the default engine due to failed verification. Failure is communicated through status, and the user decides whether to reconfigure or choose another engine.

---

## Components

### `KnowYou/UI/Reader/...`

The top-right reader area needs a new engine entry control and popover-style first-level panel. Exact file placement should follow the existing reader composition once implementation planning begins.

### `KnowYou/UI/Settings/SettingsView.swift`

Settings may still remain as a secondary place for deeper service and storage configuration, but engine control should no longer depend on this view as the primary interaction surface.

### `KnowYou/Services/Summary/SummarizerConfig.swift`

This area needs to evolve from a simple summarizer-type config into a richer engine configuration model that can represent:

- five named engines
- default engine selection
- CLI paths including Openclaw
- OpenAI-compatible API settings

### `KnowYou/Services/Summary/CLISummarizer.swift`

This area should support smoke-test execution rules for all supported CLI engines, including the new Openclaw CLI engine.

### API summarizer service

The current cloud summarizer path needs a configuration model that can target a user-provided OpenAI-compatible endpoint rather than only assuming the official OpenAI default.

### App-level state

App state needs a runtime status model per engine so the UI can render:

- current status light
- current status text
- last verification time
- current default engine

---

## Error Handling

- Missing CLI executable should resolve to gray, not a crash.
- Failed CLI launch, timeout, or invalid output should resolve to yellow with a concise user-facing explanation.
- Incomplete API fields should resolve to gray.
- HTTP failures, authentication failures, and invalid API response shapes should resolve to yellow.
- Help text should guide the user toward fixing configuration, but the app should not expose secrets in those messages.

---

## Testing

1. Add focused unit coverage for engine configuration persistence, including Openclaw and API-compatible fields.
2. Add focused tests for CLI executable discovery and smoke-test result mapping to gray/yellow/green states.
3. Add focused tests for API completeness checks and API smoke-test state mapping.
4. Add UI-facing tests for:
   - outer control displaying current default engine
   - panel showing all five engine rows
   - only green engines being selectable as default
   - API row opening the second-level detail screen
5. Run targeted test slices during implementation.
6. Run full verification before claiming completion:
   - `xcodebuild test -scheme KnowYou -destination 'platform=macOS'`
   - `xcodebuild build -scheme KnowYou -destination 'platform=macOS'`

---

## Open Decisions Resolved

- The chosen interaction model is a top-right engine entry with a first-level engine panel and API second-level detail.
- The outer top-right control shows the current default engine name, a disclosure affordance, and a status light.
- The first-level panel is where users directly choose the default engine.
- The supported engines are Claude Code, Codex CLI, Gemini CLI, Openclaw CLI, and API.
- Status lights use only three colors: gray, yellow, and green.
- Yellow merges both "not yet verified" and "test failed" states.
- Default engine selection is limited to green engines.
- API uses an OpenAI-compatible configuration shape with `baseURL`, `token`, and `model`.
- API token must be stored in Keychain rather than regular app preferences.
