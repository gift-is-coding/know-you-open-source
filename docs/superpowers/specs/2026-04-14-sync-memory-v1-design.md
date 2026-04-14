# Sync Memory V1 Design

## Summary

This feature adds a new top-right `Sync Memory` entry point that lets Know You copy its daily Markdown diary into two external memory channels:

- Obsidian
- OpenClaw

V1 is intentionally narrow. It does not try to become a general "AI tool rules sync" system, and it does not include Claude Code, Codex, Cursor, Windsurf, or other coding-agent rule surfaces. The product goal is daily memory distribution, not project instruction management.

The first release should feel simple to a non-technical user:

1. Open `Sync Memory`
2. Let the app auto-detect likely destinations
3. Confirm or change the paths once
4. Click `Sync Now` or turn on `Auto Sync Daily`

After initial setup, Know You should handle future copies automatically while the app is running.

## Problem

Know You already generates a local daily Markdown diary, but users who rely on external knowledge tools still need to move that memory by hand. That breaks the "local-first but useful everywhere" story and makes daily memory capture feel unfinished.

The main product gap is not diary generation. It is the lack of a clean bridge from Know You's daily diary output into the external memory systems users already read and search.

## Goals

1. Add a visible and understandable `Sync Memory` entry point in the main window toolbar.
2. Support two daily-memory destinations in V1:
   - Obsidian
   - OpenClaw
3. Make first-time setup mostly automatic through path detection and sensible defaults.
4. Let users trigger a one-off sync with one click.
5. Support one fixed daily automatic sync while the app is running.
6. Show clear per-channel readiness and last-sync status.

## Non-Goals

V1 does not include:

- Claude Code integration
- Codex / Gemini / Cursor / Windsurf / Copilot / Continue / Cline support
- System-level background scheduling when the app is closed
- Bidirectional sync
- Live incremental sync after every diary refresh
- Editing external files in place
- Replacing or overwriting OpenClaw's native daily memory files
- Arbitrary user-entered path strings

## Why These Channels

### Obsidian

Obsidian is a natural destination because it already treats a user-selected vault as a local Markdown folder tree. Know You can copy diary files into a dedicated subdirectory inside the vault without requiring any proprietary API.

### OpenClaw

OpenClaw is relevant because it has a native memory system, but Know You should not take over or overwrite OpenClaw's own daily memory files. Instead, Know You should copy diary files into a dedicated Know You memory subdirectory inside the detected OpenClaw workspace so OpenClaw can read and search that material as additional memory.

### Why Not Claude Code

Claude Code's official memory model is better described as instruction/context files (`CLAUDE.md`, imports, local overrides) than as a first-class daily personal memory channel. That makes it a weaker fit for this feature's first release. It can be reconsidered later as a separate "agent context bridge" feature.

## Approaches Considered

### Approach A: Generic multi-tool sync surface

Build a flexible channel system now and include many tools from the start.

Pros:

- Broader surface area immediately
- More future-proof abstraction

Cons:

- Expands scope before validating the daily-memory workflow
- Pushes the UI toward configuration complexity
- Mixes true daily memory channels with coding-rule surfaces

### Approach B: Two daily-memory channels with a simple app-owned sync flow

Build a dedicated V1 around Obsidian and OpenClaw only. Use app-managed path detection, file copying, and daily scheduling while the app runs.

Pros:

- Matches the actual product need
- Keeps the user model simple
- Avoids unstable or weakly related integrations
- Low implementation risk

Cons:

- Does not sync while the app is closed
- Leaves future agent integrations for later

### Approach C: Full system-level sync from day one

Ship the same channels as Approach B, but include LaunchAgent or another system scheduling mechanism in V1.

Pros:

- Stronger automation story

Cons:

- Higher implementation and support burden
- More file-access and background-process edge cases
- Not necessary to validate the feature's core value

### Recommendation

Choose **Approach B**.

It delivers the intended user value with the least product and implementation risk. The user gets a visible sync feature, one-time setup, manual sync, and predictable daily automation without needing to understand macOS background infrastructure.

## User Experience

## Entry Point

The main window toolbar gains a new `Sync Memory` button on the right side, separate from diary engine controls.

The button should be more explicit than a generic settings icon. It should combine:

- a recognizable sync/storage-style symbol
- the visible label `Sync Memory`

The control should look like an action surface, not a hidden preferences affordance.

## Panel Layout

Clicking `Sync Memory` opens a compact panel with:

1. Two channel cards:
   - Obsidian
   - OpenClaw
2. A global `Sync Now` action
3. An `Auto Sync Daily` toggle
4. Last successful sync time or latest error summary

Each channel card shows:

- channel icon or recognizable symbol
- channel name
- status light
- short path summary
- `Change Folder`
- `Open Folder` when ready

## Status Model

Each channel should expose one of these product states:

- `Detecting`
- `Ready`
- `Needs confirmation`
- `Missing`
- `Error`

Color can reinforce the state, but the text label must remain explicit so the feature is understandable at a glance.

## Channel Behavior

### Obsidian

Know You should try to detect likely vaults automatically. Detection may surface one or more candidate vaults, but V1 must still let the user confirm the chosen vault once.

When configured, Know You writes into a fixed subdirectory inside the selected vault:

`Know You/Daily Memories/`

The synced files should remain plain Markdown and be easy for users to inspect in Finder or inside Obsidian.

### OpenClaw

Know You should auto-detect the OpenClaw workspace using OpenClaw's default workspace conventions and known compatibility fallbacks. Once found, Know You should create and use a dedicated subdirectory:

`<openclaw-workspace>/know-you-memory/`

This directory is intentionally separate from OpenClaw's own native memory files. Know You should add memory material to OpenClaw's readable workspace without replacing or overwriting OpenClaw's daily-memory mechanism.

The user should still be allowed to change the folder if the detected workspace is wrong or non-standard.

## File Model

Know You remains the canonical source of truth for diary generation.

The sync feature copies from Know You's existing daily Markdown output into external destinations. It does not generate a different diary format per channel in V1.

Recommended destination filename:

`YYYY-MM-DD.md`

This keeps the file model stable and human-readable across both channels.

## Sync Semantics

## Manual Sync

`Sync Now` copies the currently eligible daily memory files into every enabled, ready channel.

V1 should be conservative:

- overwrite only files that Know You previously synced into its own destination directories
- do not mutate unrelated user files
- fail one channel independently without blocking the other

## Automatic Sync

V1 supports one fixed daily sync time while the app is running.

Behavior:

- user enables `Auto Sync Daily`
- user chooses one daily time
- Know You performs the sync once per day at that time, only while the app is active/running

V1 does not promise sync when the app is closed.

## Scope of What Gets Copied

V1 should sync daily diary files, not arbitrary historical exports or all vault content. The simplest starting rule is:

- copy the latest eligible daily diary file from Know You into each enabled destination

If the implementation needs a bounded history window for better UX or recovery, that should still remain explicitly limited and predictable.

## Path Detection

## Obsidian Detection

Obsidian path detection should:

1. search for likely vaults
2. identify candidates that look like real vault roots
3. present the detected result as a prefilled default
4. allow the user to replace it via folder picker

The app should not rely on the vault folder being named "Obsidian". A valid vault is defined by structure, not by folder name.

## OpenClaw Detection

OpenClaw detection should:

1. prefer current default workspace conventions
2. check known compatibility fallbacks
3. create `know-you-memory/` inside the resolved workspace
4. allow the user to override if needed

## Persistence

The app should persist:

- whether each channel is enabled
- confirmed destination folder bookmark/path
- last detection result summary
- auto-sync enabled/disabled
- chosen daily sync time
- last successful sync timestamp
- latest sync error summary

This configuration belongs to a new sync-memory settings model, separate from summarizer configuration.

## Failure Handling

Failures must be channel-local and understandable.

Examples:

- Obsidian vault moved
- OpenClaw workspace missing
- destination not writable
- source daily Markdown missing

UI behavior:

- show the failing channel as `Error`
- keep the other channel usable
- preserve the last known path so the user can repair rather than reconfigure from scratch
- expose a short human-readable reason inline

## Testing

V1 should include focused tests for:

- path detection helpers
- destination path resolution
- channel status derivation
- sync planner behavior
- copy behavior for both channels
- partial failure handling
- daily auto-sync scheduling logic while app is running

UI tests or view-model tests should cover:

- toolbar button visibility
- panel state for detected vs missing paths
- enabling auto-sync
- manual sync status updates

## Architecture Impact

Expected new areas:

- sync-memory configuration model
- path detection helpers
- file-copy service / sync coordinator
- runtime schedule hook in app state
- toolbar button + panel UI

The design should keep sync-memory logic separate from diary-engine selection and from diary generation itself. This feature consumes existing diary output; it should not alter generation behavior.

## Open Questions Resolved

- V1 channels: `Obsidian` and `OpenClaw` only
- Claude Code: excluded from V1
- Obsidian destination: fixed `Know You/Daily Memories/`
- OpenClaw destination: fixed `know-you-memory/` inside detected workspace
- OpenClaw native memory files: do not replace, do not overwrite
- Auto sync timing: fixed once per day
- Background model: app-running only for V1

## Future Extensions

Possible later additions:

- LaunchAgent-backed system scheduling when the app is closed
- Claude Code context bridge
- more agent-specific channels
- configurable history window
- per-channel file templates or rollups
