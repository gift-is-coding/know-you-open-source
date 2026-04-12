# Spec: Global Diary Prompt Editor

**Date:** 2026-04-12  
**Branch:** feature/global-diary-prompt-editor  
**Status:** Draft

---

## Problem

The app already has a visible top-right runtime control for choosing the diary engine, but the diary prompt itself is still fixed inside the generation layer.

That creates a product gap:

- users cannot inspect the exact default diary prompt the app is using
- users cannot set a persistent global prompt override for their own diary style
- users have no first-level control over whether future diary generations should use the system prompt or a customized version

The requested behavior is not a one-off debug surface. It is a product-level global setting that should be easy to discover from the main window and clearly scoped in its effect.

The current app also needs to avoid a misleading rewrite model. Changing the prompt should not imply that existing diary files or story artifacts are being silently re-generated.

---

## Goals

1. Add an always-available top-right entry point for editing the diary prompt.
2. Let users inspect the current system default diary prompt from that UI.
3. Let users edit and persist a global custom prompt override for future diary generation.
4. Let users apply the custom prompt immediately so subsequent day generation uses it.
5. Let users restore the system default prompt in one click.
6. Clearly explain that prompt changes affect future diary generation only and do not automatically rewrite existing diary content.

## Non-Goals

- Adding per-day prompt customization
- Rewriting old `.md` or `.story.json` files when the prompt changes
- Introducing prompt version history or diff tooling
- Turning prompt editing into a full settings page redesign
- Changing the current diary engine selector interaction model

---

## Approaches Considered

### Approach A: Add prompt editing only inside Settings

This reuses an existing configuration surface.

Trade-offs:

- Lowest UI disruption
- Poor discoverability for a feature meant to affect day-to-day generation quality
- Does not satisfy the requested top-right entry point

### Approach B: Add a separate top-right prompt button beside the engine selector

This keeps engine choice and prompt customization as sibling runtime controls.

Trade-offs:

- Best match for the requested interaction
- Keeps responsibilities clear: engine control remains about execution path, prompt editor remains about diary generation instructions
- Requires one additional toolbar control and one new modal surface

### Approach C: Fold prompt editing into the existing diary engine panel

This uses the current top-right affordance without adding another toolbar button.

Trade-offs:

- Slightly fewer visible controls
- Weaker information architecture because engine readiness and writing prompt are different concepts
- Risks turning the engine panel into an overloaded mixed-responsibility surface

### Recommendation

Choose **Approach B**.

The app already treats the top-right area as the main runtime control zone. A separate prompt button keeps the design consistent while preserving clean boundaries between engine selection and prompt authoring.

---

## Design

### 1. Top-Right Prompt Entry

The main window toolbar should gain a second primary control beside the existing `DiaryEngineSelectorButton`.

The new control should:

- live in the same top-right toolbar cluster
- use the existing visual language rather than introducing a new styling system
- read as an explicit prompt-editing action, such as `Edit Prompt`
- open a dedicated prompt editor surface when clicked

This keeps the feature discoverable from the same place where users already control diary generation behavior.

### 2. Prompt Editor Surface

Clicking the toolbar button should open a dedicated editor surface implemented as a sheet, matching the app’s current detail-editing pattern used for API configuration.

The editor should contain four clearly separated parts:

1. a short explanatory note
2. a read-only preview of the current system default diary prompt
3. an editable text area for the user’s global custom prompt
4. footer actions for `Apply`, `Restore Default`, and close/cancel

The explanatory note must state, in plain language:

- this prompt affects future diary generation results
- existing diary content is not automatically changed
- users need a future refresh/new generation for the new prompt to appear in generated output

### 3. Default Prompt Visibility

The UI must let users inspect the current built-in system prompt without needing to read source code.

The system prompt preview should be:

- read-only
- scrollable
- derived from the same prompt builder that production generation uses
- visually labeled as the app default rather than the user override

This is important because `Restore Default` should be understandable and trustworthy: users can see exactly what they are restoring to.

### 4. Global Custom Prompt Model

The app should support one persisted global prompt override.

Behavior rules:

- when no custom prompt exists, generation uses the system default prompt
- when a custom prompt exists and has been applied, generation uses the custom prompt instead of the default prompt body
- the custom prompt is global across the app, not tied to a single date
- the custom prompt persists across app relaunches

This should be modeled as a prompt-specific configuration object or config extension rather than being scattered across ad hoc `UserDefaults` calls from the view layer.

### 5. Apply Semantics

`Apply` should do two things:

1. persist the current custom prompt text as the active global override
2. update the app’s in-memory generation configuration immediately

`Apply` must not:

- auto-refresh the selected day
- auto-regenerate historical days
- rewrite any existing generated files

The product meaning is:

"From now on, new diary generations use this prompt."

### 6. Restore Default Semantics

`Restore Default` should remove the active custom override and return the app to using the built-in system prompt.

Behavior rules:

- the editable custom prompt field should be reset to the system default prompt text or otherwise reflect that no override is active, depending on the final UI implementation
- persistence should no longer store an active custom override after restoration
- subsequent diary generations should again use the built-in prompt logic
- existing files remain unchanged

The operation should be reversible in the same editing session until the sheet is closed or the user applies a different value.

### 7. Generation Integration

The production prompt path currently flows through `DailyMarkdownComposer.storyPrompt(dayKey:events:)`.

That architecture should evolve to keep one canonical prompt-construction boundary:

- base prompt generation still lives in the composer/generation layer
- prompt override resolution happens before the final prompt string is handed to a summarizer
- tests should verify both the default prompt path and the custom prompt path through that same generation boundary

The app should not duplicate prompt templates in the UI just for display. The editor’s default preview and the generator’s default prompt must come from the same canonical source.

### 8. Existing Content Safety

The UI and runtime behavior must make the historical-content rule explicit.

Hard rules:

- editing or applying a prompt never mutates existing `DailyStory` artifacts already on disk
- editing or applying a prompt never mutates existing Markdown exports already on disk
- the only time the new prompt affects content is when a day is generated again after the change

This avoids surprising users and keeps prompt editing as a generation-input change, not a retroactive migration.

### 9. Testing Scope

The feature should be covered with tests in three layers:

#### Prompt configuration tests

- loading default state with no custom override
- saving and loading a custom global prompt
- restoring default clears the override

#### Composer / generation tests

- default prompt generation remains unchanged when no override exists
- custom override becomes the prompt used for future summarizer generation
- restoring default returns generation to the built-in prompt

#### Main-window / interaction tests

- the new toolbar button is present in the main window structure
- opening the editor shows the explanatory note about future generations only
- `Apply` updates app state without triggering automatic regeneration
- `Restore Default` resets the active prompt configuration

---

## Files Likely To Change

- `KnowYou/UI/MainWindowView.swift`
- `KnowYou/Services/Composer/DailyMarkdownComposer.swift`
- `KnowYou/App/AppState.swift`
- `KnowYou/Services/Summary/SummarizerConfig.swift` or a new prompt-specific config file if that creates cleaner boundaries
- new prompt editor UI file(s) under `KnowYou/UI/Reader/` or another existing configuration-oriented UI folder
- focused test files in `KnowYouTests/`

---

## Acceptance Criteria

The feature is complete when all of the following are true:

1. The main app toolbar shows a dedicated prompt-editing button in the top-right area.
2. Users can open a prompt editor and inspect the current system default diary prompt.
3. Users can edit and apply a global custom prompt override.
4. The app uses the applied custom prompt for subsequent diary generation.
5. Users can restore the built-in default prompt in one action.
6. The UI explicitly states that prompt changes affect future diary generation only and do not automatically modify old content.
7. No existing diary artifacts are rewritten merely because the prompt setting changed.
