# Add Source Visual Interaction Polish Design

## Goal

Improve the Add Source and source sidebar experience so users can clearly see and operate sources without hidden inline prompt panels or tiny controls.

## Requirements

- `Generate Prompt` opens a modal sheet instead of rendering the prompt builder inline below the source cards.
- The prompt sheet defaults to `daily` at `11:00`, not the current time.
- The Add Source page uses larger, more readable typography, card spacing, and button sizes.
- Add Source cards and sidebar source rows use real source logos where KnowYou already has assets:
  - Obsidian: `SourceLogoObsidian`
  - Feishu: `SourceLogoFeishu`
  - Notion: `SourceLogoNotion`
  - Google Drive: `SourceLogoGoogleDrive`
- Built-in or generic sources can still use system symbols where no brand asset exists.
- The sidebar keeps `Add Source` as a standalone row.
- Connector rows remain first-level peers of `My Diary`.
- Connector roots expand local Markdown trees in the left sidebar.
- If an imported document path includes the connector root folder name, the sidebar must not show that root folder as an extra second-level wrapper.

## Non-Goals

- Do not change remote authentication behavior.
- Do not store any Feishu, Notion, or Google Drive tokens.
- Do not redesign Daily Memory Export.

## Testing

- Presentation tests cover brand asset names, modal prompt state, default time, and source tree path trimming.
- Targeted tests run before and after implementation.
