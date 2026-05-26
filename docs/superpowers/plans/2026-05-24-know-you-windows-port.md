# KnowYou Windows Port Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a separate `know-you-win` Tauri/React/Rust codebase that implements KnowYou's Windows product-equivalent local-first diary workflow.

**Architecture:** React renders the story-first desktop UI. Tauri commands expose a Rust core that owns privacy filtering, SQLite storage, story composition, refresh planning, summarizer configuration, memory sync planning, and Windows adapter boundaries. Windows-native behavior is isolated behind traits so automated tests can verify behavior on macOS while real Windows verification remains documented.

**Tech Stack:** Tauri, React, TypeScript, Vite, Rust, SQLx SQLite, Serde, Chrono, Vitest, Playwright.

---

### Task 1: Scaffold Independent Repository

**Files:**
- Create: `/Users/wutianfu/Documents/code/know-you-win/package.json`
- Create: `/Users/wutianfu/Documents/code/know-you-win/index.html`
- Create: `/Users/wutianfu/Documents/code/know-you-win/src/main.tsx`
- Create: `/Users/wutianfu/Documents/code/know-you-win/src/App.tsx`
- Create: `/Users/wutianfu/Documents/code/know-you-win/src/styles.css`
- Create: `/Users/wutianfu/Documents/code/know-you-win/src-tauri/Cargo.toml`
- Create: `/Users/wutianfu/Documents/code/know-you-win/src-tauri/tauri.conf.json`
- Create: `/Users/wutianfu/Documents/code/know-you-win/src-tauri/src/main.rs`

- [ ] **Step 1: Create repository directories and initialize git**

Run:

```bash
mkdir -p /Users/wutianfu/Documents/code/know-you-win
cd /Users/wutianfu/Documents/code/know-you-win
git init
```

Expected: an empty independent git repository exists.

- [ ] **Step 2: Add minimal Tauri/Vite project files**

Add package, Vite, TypeScript, React, Tauri, and Rust files with a placeholder UI and Tauri command.

- [ ] **Step 3: Run initial install/build checks**

Run:

```bash
npm install
npm run build
cargo test --manifest-path src-tauri/Cargo.toml
```

Expected: frontend builds and Rust tests compile.

### Task 2: Implement Rust Domain Contracts With Tests

**Files:**
- Create: `/Users/wutianfu/Documents/code/know-you-win/src-tauri/src/domain.rs`
- Create: `/Users/wutianfu/Documents/code/know-you-win/src-tauri/src/day_key.rs`
- Modify: `/Users/wutianfu/Documents/code/know-you-win/src-tauri/src/main.rs`

- [ ] **Step 1: Write failing tests for day keys and JSON story shape**

Tests must cover stable `YYYY-MM-DD` day keys and serialization of `DailyStory`, `DailyStorySection`, and `DailyStoryParagraph`.

- [ ] **Step 2: Implement domain models and day-key helpers**

Add Rust structs with Serde serialization and tests.

- [ ] **Step 3: Run Rust tests**

Run:

```bash
cargo test --manifest-path src-tauri/Cargo.toml domain day_key
```

Expected: tests pass.

### Task 3: Implement Privacy Filter With Tests

**Files:**
- Create: `/Users/wutianfu/Documents/code/know-you-win/src-tauri/src/privacy.rs`
- Modify: `/Users/wutianfu/Documents/code/know-you-win/src-tauri/src/main.rs`

- [ ] **Step 1: Write failing tests for keep, redact, and drop**

Cover benign text, long numeric sequences, password/token/OTP/private key strings, audit text, and non-persistence of sensitive raw text.

- [ ] **Step 2: Implement privacy filter**

Add `PrivacyAction` and `PrivacyFilter::filter`.

- [ ] **Step 3: Run Rust tests**

Run:

```bash
cargo test --manifest-path src-tauri/Cargo.toml privacy
```

Expected: tests pass.

### Task 4: Implement SQLite Storage With Tests

**Files:**
- Create: `/Users/wutianfu/Documents/code/know-you-win/src-tauri/src/storage.rs`
- Modify: `/Users/wutianfu/Documents/code/know-you-win/src-tauri/Cargo.toml`
- Modify: `/Users/wutianfu/Documents/code/know-you-win/src-tauri/src/main.rs`

- [ ] **Step 1: Write failing storage tests**

Cover migrations, event insert, day fetch, duplicate content hash ignore, run start/finish, and latest successful run lookup.

- [ ] **Step 2: Implement storage**

Use SQLx SQLite with runtime migrations executed from Rust.

- [ ] **Step 3: Run Rust tests**

Run:

```bash
cargo test --manifest-path src-tauri/Cargo.toml storage
```

Expected: tests pass.

### Task 5: Implement Composer And Refresh Planning With Tests

**Files:**
- Create: `/Users/wutianfu/Documents/code/know-you-win/src-tauri/src/composer.rs`
- Create: `/Users/wutianfu/Documents/code/know-you-win/src-tauri/src/refresh.rs`
- Modify: `/Users/wutianfu/Documents/code/know-you-win/src-tauri/src/main.rs`

- [ ] **Step 1: Write failing composer tests**

Cover fallback story generation, Markdown output, source notes, paragraph source IDs, and model-story fallback overwrite protection.

- [ ] **Step 2: Write failing refresh planner tests**

Cover full recovery without model story, incremental mode with model story, today-only automation, day-scoped manual refresh, and chunk sizes of 50 events.

- [ ] **Step 3: Implement composer and refresh planner**

Add deterministic fallback generation and refresh plan structures.

- [ ] **Step 4: Run Rust tests**

Run:

```bash
cargo test --manifest-path src-tauri/Cargo.toml composer refresh
```

Expected: tests pass.

### Task 6: Implement App Services And Tauri Commands

**Files:**
- Create: `/Users/wutianfu/Documents/code/know-you-win/src-tauri/src/app_state.rs`
- Create: `/Users/wutianfu/Documents/code/know-you-win/src-tauri/src/settings.rs`
- Create: `/Users/wutianfu/Documents/code/know-you-win/src-tauri/src/sync_memory.rs`
- Create: `/Users/wutianfu/Documents/code/know-you-win/src-tauri/src/reminders.rs`
- Create: `/Users/wutianfu/Documents/code/know-you-win/src-tauri/src/windows_adapters.rs`
- Modify: `/Users/wutianfu/Documents/code/know-you-win/src-tauri/src/main.rs`

- [ ] **Step 1: Write failing tests for settings, sync, reminder, and adapter status**

Cover vault defaults, engine validation, sync target paths, 20:30 reminder planning, and unavailable Windows adapter status on non-Windows.

- [ ] **Step 2: Implement service modules**

Add app-data path resolution, settings load/save, sync copying, reminder planning, and adapter traits.

- [ ] **Step 3: Implement Tauri commands**

Expose commands for loading app state, inserting sample events, refreshing a day, updating settings, syncing memory, and reading service status.

- [ ] **Step 4: Run Rust tests**

Run:

```bash
cargo test --manifest-path src-tauri/Cargo.toml app_state settings sync_memory reminders windows_adapters
```

Expected: tests pass.

### Task 7: Implement React UI With Tests

**Files:**
- Create: `/Users/wutianfu/Documents/code/know-you-win/src/types.ts`
- Create: `/Users/wutianfu/Documents/code/know-you-win/src/fixtures/demoStory.ts`
- Create: `/Users/wutianfu/Documents/code/know-you-win/src/state/reader.ts`
- Create: `/Users/wutianfu/Documents/code/know-you-win/src/components/DateSidebar.tsx`
- Create: `/Users/wutianfu/Documents/code/know-you-win/src/components/StoryReader.tsx`
- Create: `/Users/wutianfu/Documents/code/know-you-win/src/components/SourceDetail.tsx`
- Create: `/Users/wutianfu/Documents/code/know-you-win/src/components/EngineSelector.tsx`
- Create: `/Users/wutianfu/Documents/code/know-you-win/src/components/SettingsPanel.tsx`
- Create: `/Users/wutianfu/Documents/code/know-you-win/src/components/OnboardingOverlay.tsx`
- Create: `/Users/wutianfu/Documents/code/know-you-win/src/state/reader.test.ts`
- Modify: `/Users/wutianfu/Documents/code/know-you-win/src/App.tsx`
- Modify: `/Users/wutianfu/Documents/code/know-you-win/src/styles.css`

- [ ] **Step 1: Write failing Vitest tests for reader selection**

Cover date selection, paragraph selection, source-event resolution, and keyboard focus transitions.

- [ ] **Step 2: Implement reader state helpers**

Add pure TypeScript functions for selection and focus behavior.

- [ ] **Step 3: Implement UI components**

Build the three-pane reader, onboarding shell, engine selector, settings panel, status surfaces, and action buttons.

- [ ] **Step 4: Run frontend tests**

Run:

```bash
npm test
```

Expected: Vitest passes.

### Task 8: Add Playwright Smoke Test And Documentation

**Files:**
- Create: `/Users/wutianfu/Documents/code/know-you-win/playwright.config.ts`
- Create: `/Users/wutianfu/Documents/code/know-you-win/tests/reader.spec.ts`
- Create: `/Users/wutianfu/Documents/code/know-you-win/README.md`
- Create: `/Users/wutianfu/Documents/code/know-you-win/docs/windows-verification.md`
- Create: `/Users/wutianfu/Documents/code/know-you-win/docs/architecture.md`
- Create: `/Users/wutianfu/Documents/code/know-you-win/docs/requirements-spec.md`

- [ ] **Step 1: Write Playwright reader smoke test**

Test that the Vite-rendered app shows the date list, story reader, source detail panel, engine selector, and settings surfaces.

- [ ] **Step 2: Add documentation**

Document architecture, requirements, Windows-specific verification, known native gaps, and development commands.

- [ ] **Step 3: Run full verification**

Run:

```bash
cargo test --manifest-path src-tauri/Cargo.toml
npm test
npm run build
npm run e2e
```

Expected: all available automated checks pass. Any Windows-only behavior that cannot be verified from macOS is listed in `docs/windows-verification.md`.

## Self-Review

- Spec coverage: repository, stack, contracts, product-equivalent behavior, Windows substitutions, tests, and verification are covered.
- Placeholder scan: no `TBD`, `TODO`, or deferred implementation markers are present.
- Type consistency: file names and module names are consistent across tasks.
- Execution note: user approved continuous `/goal` execution, so implementation proceeds inline without asking for execution mode.
