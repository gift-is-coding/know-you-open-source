# My Wiki Native Prompt + Entity Tags

## Goal

Keep KnowYou My Wiki on the upstream LLM Wiki `autoIngest` prompt and two-stage pipeline. KnowYou should not add a second page-writing prompt or dynamic generation target layer for native `Sources / Entities / Concepts`.

## Requirements

- Details must not repeat the same summary in both the header and a standalone `Summary` card.
- `MyWikiEntry` must load frontmatter `tags`.
- The left `Entities` section must offer lightweight tag filters: `人物`, `项目`, `组织`, `其他`.
- Entity filters should be driven by broad tags such as `person`, `project`, `organization`, `other`, with examples that allow generated pages to grow naturally.
- The ingest generation prompt must keep the upstream LLM Wiki native targets: source summary page, entity pages, concept pages, index, log, overview.
- KnowYou schema guidance may lightly encourage entity tags, but should not replace the native prompt with ontology-specific page instructions.

## Non-Goals

- Do not reintroduce hard People/Projects/Organizations folders.
- Do not embed the React/Tauri LLM Wiki UI.
- Do not add a separate custom page-body prompt.
