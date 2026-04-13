# Details Paragraph Splitting Design

## Overview

The reader currently selects evidence at the `DailyStoryParagraph` level. When a generated story writes the whole `# Details` section as one paragraph containing several `##` subsections, the UI can only switch the right-side source pane for that entire block.

This pass keeps the existing paragraph-level interaction model and fixes the data shape instead:

- new story generation should emit each Details workstream as its own paragraph
- legacy `.story.json` should be normalized on load and rewritten once so old days permanently move to the new format
- source linking remains paragraph-level; this change does not introduce sentence-level citations

## Problem

Current behavior makes the center pane look segmented while the source pane still behaves as if the whole Details block were one unit. That mismatch is confusing because each `##` subheading reads like a separate story thread but shares one selection state.

## Product Decision

The product should continue to use `DailyStoryParagraph` as the unit of evidence selection.

The canonical structured-story contract becomes:

- `# 你今天做得很棒` / `# You did a good job today`: one paragraph
- `# 今日总结` / `# Summary`: one paragraph using bullets
- `# 详情` / `# Details`: one paragraph per workstream, with the first paragraph owning the first-level Details heading
- `# 待办事项` / `# To-do`: one paragraph using task list items

There is no hard paragraph-count limit for Details. The prompt should ask for reasonable grouping and should explicitly avoid fragmenting the day into tiny paragraphs.

## Legacy Compatibility

Historical `.story.json` files may still store multiple Details subsections inside one paragraph. The app must normalize those stories when they are loaded and rewrite them back to disk in the new format.

Compatibility rules:

- only split paragraphs whose first-level heading is `# Details` or `# 详情`
- only split when the paragraph contains multiple `##` subsections
- preserve paragraph order
- generate stable derived ids for split paragraphs
- preserve or narrow `sourceEventIDs` without dropping evidence entirely

Legacy source narrowing should stay deterministic and local:

- first try matching subsection text to source app names
- then use keyword overlap against candidate event text
- if no subsection-specific match is found, keep the original full source list

## Acceptance Criteria

- Selecting different Details workstreams changes the right-side source pane
- Freshly generated stories no longer need one giant Details paragraph
- Old stories with merged Details subsections become selectable and are migrated to the new format after first load
- Markdown export still renders a single top-level Details heading
