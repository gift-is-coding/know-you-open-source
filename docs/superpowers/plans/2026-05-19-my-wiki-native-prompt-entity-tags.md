# My Wiki Native Prompt + Entity Tags Plan

## Steps

1. Add focused tests for duplicate summary removal, tag parsing, entity facet matching, and upstream LLM Wiki generation targets.
2. Add `tags` to `MyWikiEntry` and parse `tags` from markdown frontmatter.
3. Add entity facet definitions and filter `Entities` in the left index without affecting `Concepts` or `Sources`.
4. Remove the standalone detail `Summary` card while keeping the header summary.
5. Remove custom My Wiki prompt target generation from `ThirdParty/llm_wiki/src/lib/ingest.ts`, keeping cache invalidation and source-language proper-noun preservation.
6. Lightly update schema/purpose guidance so generated entity pages can include `person`, `project`, `organization`, or `other` tags.
7. Reset generated wiki outputs and rerun only three sources.
8. Run targeted TypeScript and Swift tests, then full macOS test/build verification.
