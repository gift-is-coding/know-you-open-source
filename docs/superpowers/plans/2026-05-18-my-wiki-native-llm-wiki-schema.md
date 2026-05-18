# My Wiki Native LLM Wiki Schema Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Move KnowYou My Wiki's default backend contract back to llm_wiki native `sources/entities/concepts` while keeping KnowYou diary source tags and schema-driven Swift UI.

**Architecture:** Keep `MyWikiProjectExporter -> MyWikiPipelineBridge -> ThirdParty/llm_wiki headless ingest` as the core flow. Change the default schema so it no longer triggers the custom My Wiki output contract, add source tags at export, and make ingest cache keys include schema/purpose/version so old strong-category cache entries are stale.

**Tech Stack:** Swift/XCTest for KnowYou app code; TypeScript/Vitest for `ThirdParty/llm_wiki`; Markdown docs.

---

## File Map

- Modify `KnowYou/Services/MyWiki/MyWikiSchemaConfig.swift`: default schema becomes `Sources`, `Entities`, `Concepts` with legacy directory compatibility.
- Modify `KnowYou/Services/MyWiki/MyWikiProjectExporter.swift`: exported KnowYou diary frontmatter includes `tags: [knowyou, diary]`; generated `schema.md` no longer forbids native llm_wiki folders.
- Modify `KnowYou/Services/MyWiki/MyWikiMarkdownStore.swift` only if tests expose reader assumptions tied to old category IDs.
- Modify `ThirdParty/llm_wiki/src/headless/knowyou-ingest.ts`: do not generate `KNOWYOU_MY_WIKI_OUTPUT_CONTRACT` for native schemas; keep custom contract only when schema declares non-native categories.
- Modify `ThirdParty/llm_wiki/src/lib/ingest-cache.ts`: cache hash includes source content plus cache context.
- Modify `ThirdParty/llm_wiki/src/lib/ingest.ts`: pass schema/purpose/cache version into cache check/save.
- Update tests in `KnowYouTests/*` and `ThirdParty/llm_wiki/src/**/*test.ts`.
- Update `docs/architecture.md` and `docs/requirements-spec.md`.

---

### Task 1: Swift Default Schema And Export Contract

**Files:**
- Modify: `KnowYouTests/MyWikiSchemaConfigTests.swift`
- Modify: `KnowYouTests/MyWikiProjectExporterTests.swift`
- Modify: `KnowYou/Services/MyWiki/MyWikiSchemaConfig.swift`
- Modify: `KnowYou/Services/MyWiki/MyWikiProjectExporter.swift`

- [x] **Step 1: Write failing schema tests**

Change `testDefaultPersonalContextSchemaKeepsOntologyCategoriesConfigurable` to expect:

```swift
XCTAssertEqual(schema.categories.map(\.id), ["sources", "entities", "concepts"])
XCTAssertEqual(schema.categories.map(\.directory), ["wiki/sources", "wiki/entities", "wiki/concepts"])
XCTAssertEqual(schema.categories.map { $0.frontmatterTypes.first }, ["source", "entity", "concept"])
XCTAssertEqual(schema.categories.first(where: { $0.id == "entities" })?.legacyDirectories, [
    "wiki/people",
    "wiki/organizations",
    "wiki/projects",
    "wiki/events"
])
XCTAssertEqual(schema.categories.first(where: { $0.id == "concepts" })?.legacyDirectories, [
    "wiki/topics",
    "wiki/decisions",
    "wiki/preferences",
    "wiki/follow-ups",
    "wiki/summaries"
])
```

Add assertions to `MyWikiProjectExporterTests.testEnsureProjectCreatesConfigDrivenMyWikiStructureAndReadableSchema`:

```swift
XCTAssertTrue(FileManager.default.fileExists(atPath: root.appending(path: "wiki/entities").path))
XCTAssertTrue(FileManager.default.fileExists(atPath: root.appending(path: "wiki/concepts").path))
XCTAssertFalse(FileManager.default.fileExists(atPath: root.appending(path: "wiki/people").path))
XCTAssertFalse(schemaMarkdown.contains("KNOWYOU_MY_WIKI_OUTPUT_CONTRACT"))
XCTAssertFalse(schemaMarkdown.contains("Do not write `wiki/entities/`"))
```

- [x] **Step 2: Run red tests**

Run:

```bash
xcodebuild test -scheme KnowYou -destination 'platform=macOS' -only-testing:KnowYouTests/MyWikiSchemaConfigTests -only-testing:KnowYouTests/MyWikiProjectExporterTests
```

Expected: FAIL because defaults still include People/Projects and source tags are absent.

- [x] **Step 3: Implement native default schema**

Update `defaultPersonalContextJSON` to categories:

- `sources`: display `Sources`, singular `Source`, directory `wiki/sources`, types `["source", "knowyou-diary"]`
- `entities`: display `Entities`, singular `Entity`, directory `wiki/entities`, types `["entity"]`, legacy directories `wiki/people`, `wiki/organizations`, `wiki/projects`, `wiki/events`, legacy types `person`, `organization`, `company`, `team`, `project`, `event`
- `concepts`: display `Concepts`, singular `Concept`, directory `wiki/concepts`, types `["concept"]`, legacy directories `wiki/topics`, `wiki/decisions`, `wiki/preferences`, `wiki/follow-ups`, `wiki/summaries`, legacy types `topic`, `decision`, `preference`, `follow-up`, `summary`, `overview`

Update `views` to use `["sources", "entities", "concepts"]`.

Update `MyWikiSchemaMarkdownRenderer.render` shared rules to describe native llm_wiki use and remove the line that implies bespoke My Wiki categories.

- [x] **Step 4: Add source tags**

Update `exportedDiaryMarkdown` frontmatter:

```swift
---
type: knowyou-diary
source: KnowYou
day: \(dayKey)
tags: [knowyou, diary]
---
```

Add a project exporter test that syncs one `2026-05-18.md` and asserts the exported raw source contains `tags: [knowyou, diary]`.

- [x] **Step 5: Run green tests and commit**

Run the same `xcodebuild test` command. Expected: PASS.

Commit:

```bash
git add KnowYou/Services/MyWiki/MyWikiSchemaConfig.swift KnowYou/Services/MyWiki/MyWikiProjectExporter.swift KnowYouTests/MyWikiSchemaConfigTests.swift KnowYouTests/MyWikiProjectExporterTests.swift
git commit -m "feat: default my wiki to native llm wiki schema"
```

---

### Task 2: Swift Reader Compatibility

**Files:**
- Modify: `KnowYouTests/MyWikiMarkdownStoreTests.swift`
- Modify: `KnowYou/UI/MyWiki/MyWikiModels.swift`
- Modify: `KnowYou/Services/MyWiki/MyWikiMarkdownStore.swift` if required by failing tests.

- [ ] **Step 1: Write failing reader tests**

Add a test that creates default schema project with:

- `wiki/entities/huang-shan.md`, frontmatter type `entity`
- `wiki/concepts/agentic-engineering.md`, frontmatter type `concept`
- legacy `wiki/people/alex.md`, frontmatter type `person`

Assert:

```swift
XCTAssertEqual(snapshot.categories.map(\.id), ["sources", "entities", "concepts"])
XCTAssertEqual(snapshot.entries(for: "entities").map(\.title), ["Alex", "Huang Shan"])
XCTAssertEqual(snapshot.entries(for: "concepts").map(\.title), ["Agentic Engineering"])
XCTAssertEqual(snapshot.primaryEntries.map(\.category.id).sorted(), ["concepts", "entities", "entities"])
```

- [ ] **Step 2: Run red test**

Run:

```bash
xcodebuild test -scheme KnowYou -destination 'platform=macOS' -only-testing:KnowYouTests/MyWikiMarkdownStoreTests
```

Expected: FAIL if old convenience accessors or category constants assume People/Projects defaults.

- [ ] **Step 3: Implement minimal compatibility**

If needed, update `MyWikiCategory` static constants to include:

```swift
static let source = MyWikiCategory(id: "sources", displayTitle: "Sources", singularTitle: "Source", frontmatterType: "source")
static let entity = MyWikiCategory(id: "entities", displayTitle: "Entities", singularTitle: "Entity", frontmatterType: "entity")
static let concept = MyWikiCategory(id: "concepts", displayTitle: "Concepts", singularTitle: "Concept", frontmatterType: "concept")
```

Keep legacy constants for old tests and old pages. Do not hardcode default UI to old categories.

- [ ] **Step 4: Run green tests and commit**

Run the same `xcodebuild test` command. Expected: PASS.

Commit:

```bash
git add KnowYou/UI/MyWiki/MyWikiModels.swift KnowYou/Services/MyWiki/MyWikiMarkdownStore.swift KnowYouTests/MyWikiMarkdownStoreTests.swift
git commit -m "feat: read native my wiki categories"
```

---

### Task 3: Headless Contract And Cache Context

**Files:**
- Modify: `ThirdParty/llm_wiki/src/headless/knowyou-ingest.test.ts`
- Modify: `ThirdParty/llm_wiki/src/headless/knowyou-ingest.ts`
- Modify: `ThirdParty/llm_wiki/src/lib/ingest-cache.test.ts`
- Modify: `ThirdParty/llm_wiki/src/lib/ingest-cache.ts`
- Modify: `ThirdParty/llm_wiki/src/lib/ingest.ts`

- [ ] **Step 1: Write failing headless tests**

Update `knowyou-ingest.test.ts` so the default/no-schema case expects:

```ts
expect(await readFileRaw(path.join(tmp.path, "schema.md"))).not.toContain("KNOWYOU_MY_WIKI_OUTPUT_CONTRACT")
expect(await readFileRaw(path.join(tmp.path, "schema.md"))).not.toContain("Do not write `wiki/entities/`")
expect(await fileExists(path.join(tmp.path, "wiki/entities/huang-shan.md"))).toBe(true)
```

Keep the custom schema test for non-native categories, and make it assert the contract still appears when schema has `wiki/relationships`.

- [ ] **Step 2: Write failing cache context test**

In `ingest-cache.test.ts`, add:

```ts
it("invalidates when cache context changes even if source content is unchanged", async () => {
  let persisted = ""
  mockReadFile.mockImplementation(async () => persisted || JSON.stringify({ entries: {} }))
  mockWriteFile.mockImplementation(async (_p: string, c: string) => {
    persisted = c
  })
  await saveIngestCache("/project", "foo.md", "hello", ["wiki/sources/foo.md"], {
    schema: "old schema",
    purpose: "purpose",
    pipelineVersion: "v1",
  })

  mockFileExists.mockResolvedValue(true)
  const result = await checkIngestCache("/project", "foo.md", "hello", {
    schema: "new schema",
    purpose: "purpose",
    pipelineVersion: "v1",
  })
  expect(result).toBeNull()
})
```

- [ ] **Step 3: Run red tests**

Run:

```bash
npx vitest run src/headless/knowyou-ingest.test.ts src/lib/ingest-cache.test.ts
```

Expected: FAIL because default headless still writes custom contract and cache API has no context argument.

- [ ] **Step 4: Implement native/custom contract split**

Add helper in `knowyou-ingest.ts`:

```ts
function isNativeLlmWikiSchema(categories: MyWikiSchemaCategory[]): boolean {
  const normalized = new Set(categories.map((category) => normalizeDirectory(category.directory)))
  return normalized.size > 0 && [...normalized].every((directory) =>
    ["wiki/sources", "wiki/entities", "wiki/concepts"].includes(directory)
  )
}
```

Only append `buildMyWikiOutputContract(categories)` when `isNativeLlmWikiSchema(categories)` is false.

Change default categories to Sources/Entities/Concepts.

- [ ] **Step 5: Implement cache context**

In `ingest-cache.ts` add:

```ts
export interface IngestCacheContext {
  schema?: string
  purpose?: string
  pipelineVersion?: string
}
```

Change hash input to `JSON.stringify({ sourceContent, schema, purpose, pipelineVersion })`.

Update `checkIngestCache` and `saveIngestCache` signatures to accept optional context. Keep default context empty so existing tests can be migrated incrementally.

In `ingest.ts`, define:

```ts
const INGEST_CACHE_PIPELINE_VERSION = "knowyou-native-llm-wiki-schema-v1"
```

Pass `{ schema, purpose, pipelineVersion: INGEST_CACHE_PIPELINE_VERSION }` to cache check/save.

- [ ] **Step 6: Run green tests and commit**

Run:

```bash
npx vitest run src/headless/knowyou-ingest.test.ts src/lib/ingest-cache.test.ts
```

Expected: PASS.

Commit:

```bash
git add ThirdParty/llm_wiki/src/headless/knowyou-ingest.ts ThirdParty/llm_wiki/src/headless/knowyou-ingest.test.ts ThirdParty/llm_wiki/src/lib/ingest.ts ThirdParty/llm_wiki/src/lib/ingest-cache.ts ThirdParty/llm_wiki/src/lib/ingest-cache.test.ts
git commit -m "feat: use native llm wiki ingest contract"
```

---

### Task 4: Documentation And Verification

**Files:**
- Modify: `docs/architecture.md`
- Modify: `docs/requirements-spec.md`

- [ ] **Step 1: Update docs**

Update My Wiki sections to say:

- Default backend schema is native llm_wiki `Sources / Entities / Concepts`.
- KnowYou adds source metadata/tags, not forced People/Projects classification.
- Legacy People/Projects/etc. directories may be read for compatibility but are not the default generation target.
- `ThirdParty/llm_wiki` remains the trusted generation path; no starter extractor fallback.

- [ ] **Step 2: Run targeted verification**

Run:

```bash
xcodebuild test -scheme KnowYou -destination 'platform=macOS' -only-testing:KnowYouTests/MyWikiSchemaConfigTests -only-testing:KnowYouTests/MyWikiProjectExporterTests -only-testing:KnowYouTests/MyWikiMarkdownStoreTests -only-testing:KnowYouTests/MyWikiPipelineBridgeTests
npx vitest run src/headless/knowyou-ingest.test.ts src/lib/ingest-cache.test.ts
```

Expected: PASS.

- [ ] **Step 3: Run full required verification**

Run:

```bash
xcodebuild test -scheme KnowYou -destination 'platform=macOS'
xcodebuild build -scheme KnowYou -destination 'platform=macOS'
```

Also run:

```bash
npm audit --audit-level=high
```

Expected: Xcode test/build pass. `npm audit` may still fail on existing `fast-uri`/`mermaid`; report exact output if unchanged.

- [ ] **Step 4: Commit docs and any verification-only fixes**

```bash
git add docs/architecture.md docs/requirements-spec.md
git commit -m "docs: document native my wiki schema"
```

---

## Self-Review

- Spec coverage: Covers native schema, source tags, cache invalidation, legacy directory compatibility, docs, and verification.
- Placeholder scan: No TBD/TODO/placeholder steps.
- Type consistency: Swift schema names match `MyWikiSchemaConfig`; TS cache context signatures are consistent across cache and ingest call sites.
