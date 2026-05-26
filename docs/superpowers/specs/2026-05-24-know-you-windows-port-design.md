# KnowYou Windows Port Design

## Goal

Create a separate sibling codebase named `know-you-win` that delivers a Windows version of KnowYou with product-equivalent behavior to the current macOS app. The Windows version must preserve the core user journey: local context capture, privacy filtering before persistence, day-scoped storage, story-first reading, source-linked evidence, Markdown export, engine configuration, refresh status, memory sync, reminders, and testable local-first behavior.

## Scope Decision

The Windows port follows product equivalence rather than literal operating-system equivalence.

This means the Windows app must preserve the product contract and user-visible workflows, but OS-specific capabilities may use Windows-native adapters when macOS APIs have no direct equivalent. In particular, the current macOS Notification Center SQLite importer is not portable. The Windows version will implement a maintainable Windows notification/event substitute and expose its availability honestly in service status instead of pretending it has the same data source as macOS.

## Repository

The Windows version lives outside this repository in a sibling directory:

```text
/Users/wutianfu/Documents/code/know-you-win
```

The repository is independent. It may copy product contracts and fixture data from the macOS project, but it must not depend on the macOS Xcode project at runtime.

## Technical Stack

- Desktop shell: Tauri
- UI: React + TypeScript
- Core services: Rust
- Local database: SQLite through Rust SQLx
- Testing:
  - Rust unit and integration tests for domain, storage, privacy, generation, and scheduling logic
  - Vitest for TypeScript presentation helpers
  - Playwright for web-rendered reader smoke tests
  - Documented Windows-only manual verification for native OS collectors, launch at login, task scheduler, and toast notifications

## Architecture

The app is split into five layers.

1. React UI
   - Three-pane reader with dates, story paragraphs, and source details
   - Onboarding coachmarks modeled after the macOS Demo Day flow
   - Settings, engine selector, sync memory panel, reminder controls, and update surfaces

2. Tauri command bridge
   - Typed app state and command facade
   - File/folder selection
   - Tray/window actions
   - Secure boundary between UI and Rust services

3. Rust core
   - Domain models matching the macOS `.story.json` shape where practical
   - Privacy filtering before persistence
   - SQLite event and run storage
   - Daily story fallback generation
   - Markdown composition
   - Full and incremental refresh planning
   - Summarizer engine configuration and execution

4. Windows adapters
   - Clipboard polling/watching
   - Windows notification/event substitute collector
   - Launch at login registration
   - Scheduled reminder task
   - Toast notification delivery and click routing
   - Update/feed behavior suitable for Windows distribution

5. Artifacts and integrations
   - `events.sqlite`
   - `RefreshLogs/*.json`
   - `Vault/YYYY-MM-DD.story.json`
   - `Vault/YYYY-MM-DD.md`
   - Obsidian sync target: `<vault>/KnowYou/Daily Memories/`
   - OpenClaw sync target: `<workspace>/know-you-memory/`

## Feature Mapping

### Must Match Product Behavior

- Local-first default storage under a Windows app-data directory
- Per-day `.story.json` and `.md` outputs
- Story-first reader with paragraph-level source links
- Privacy filter applied before any event reaches SQLite
- Clipboard capture with source attribution when available
- Day-scoped manual refresh
- Today-only automation refresh
- Fallback story when no external summarizer is configured
- Protection against overwriting a successful model story with fallback
- Incremental refresh semantics for an existing model story
- Engine selector for:
  - None
  - OpenAI-compatible API
  - Codex Auth
  - Claude CLI
  - Codex CLI
  - Gemini CLI
  - OpenClaw CLI
- Engine smoke-test statuses
- Refresh log records with stage and attempt details
- Sync Memory manual and scheduled flows
- Evening review reminder at 20:30 local time
- Settings status for collectors, engine, automation, sync, reminders, and app metadata
- Onboarding that teaches the real reader before permissions and engine setup

### Windows-Specific Replacements

- macOS Full Disk Access becomes Windows permission/status messaging for local collectors.
- macOS Notification Center SQLite import becomes a Windows notification/event substitute collector. The initial implementation may collect from a conservative maintainable source and must show status when the signal is unavailable or limited.
- macOS LaunchAgent/SMAppService behavior becomes Windows startup registration and Task Scheduler tasks.
- macOS local notifications become Windows toast notifications where available, with a graceful status when unsupported.
- macOS Developer ID/DMG release flow becomes a Windows installer/update path. The first implementation documents packaging hooks; a later release pass can add signed MSIX/MSI/NSIS artifacts.

## Data Contracts

The Windows app should keep the exported story contract close to the macOS model:

- `DailyStory`
- `DailyStorySection`
- `DailyStoryParagraph`
- paragraph `sourceEventIDs`
- `provenance.generationMode`

The app may use Rust-friendly field naming internally, but serialized JSON must remain stable and documented. Markdown export must include the story and source notes sections.

## Security And Privacy

- No secret is hardcoded.
- API tokens are stored in the Windows credential store when implemented; until then, token persistence must be clearly isolated and not committed.
- Sensitive strings are dropped or redacted before persistence.
- Cloud and CLI summarizers are optional enhancements.
- UI copy must not imply server-side storage.

## Testing Requirements

Implementation must be test-first for non-trivial behavior.

Required automated coverage for the initial build:

- Privacy filter keep/redact/drop decisions
- SQLite migrations and event de-duplication
- Day-key date handling
- Markdown composition
- Fallback story generation
- Refresh mode planning
- Sync memory path planning
- Reminder planning
- Engine configuration validation
- React reader state and source selection helpers
- Playwright smoke test for the three-pane reader UI

Required verification commands:

```bash
cargo test --manifest-path src-tauri/Cargo.toml
npm test
npm run build
```

Tauri desktop packaging and Windows-native OS behavior may not be fully verifiable from the current macOS development machine. Any unverified Windows-only behavior must be recorded in the final report and in `docs/windows-verification.md`.

## Acceptance Criteria

The task is acceptable when:

- `know-you-win` exists as a separate sibling repository.
- It has a runnable Tauri/React/Rust project structure.
- Core local-first behavior is implemented with automated tests.
- UI can render the story-first reader, settings, onboarding shell, engine selector, and status panels.
- Rust services expose commands for loading state, inserting test events, refreshing a day, syncing memory, and updating settings.
- Automated tests and build commands have fresh output from the current session.
- Windows-specific gaps are explicit rather than hidden.
- The macOS source repository contains this design spec and an implementation plan documenting the port.

## Self-Review

- Placeholder scan: no TBD/TODO placeholders remain.
- Scope check: the design is large but coherent as one porting project because the user explicitly requested a full Windows version in one separate codebase.
- Ambiguity check: product equivalence is defined; OS-level substitutions are explicit.
- Consistency check: stack, repository path, artifacts, tests, and acceptance criteria all refer to the same Tauri/Rust/React implementation.
