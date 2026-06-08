/**
 * Scenario-driven tests for autoIngest.
 *
 * Each scenario materializes an initial project, a source document, and two
 * canned LLM responses (stage 1 analysis, stage 2 generation with FILE +
 * REVIEW blocks). The runner mocks streamChat to emit them sequentially.
 *
 * After ingest runs, the runner asserts:
 *   - expected files exist on disk with expected substrings
 *   - expected review items were injected into the review store
 */
import { describe, it, expect, beforeAll, beforeEach, afterEach, vi } from "vitest"
import path from "node:path"
import fs from "node:fs/promises"
import { realFs, createTempProject, readFileRaw, fileExists } from "@/test-helpers/fs-temp"
import { materializeScenario, copyDir } from "@/test-helpers/scenarios/materialize"
import { ingestScenarios } from "@/test-helpers/scenarios/ingest-scenarios"
import type { IngestScenario } from "@/test-helpers/scenarios/types"

vi.mock("@/commands/fs", () => realFs)

const embeddingMocks = vi.hoisted(() => ({
  embedPage: vi.fn(),
}))

vi.mock("@/lib/embedding", () => ({
  embedPage: embeddingMocks.embedPage,
}))

// Sequenced streamChat: stage-1 returns analysisResponse, stage-2 returns
// generationResponse. Any further calls return empty (shouldn't happen in a
// typical autoIngest run).
let pendingResponses: string[] = []
vi.mock("./llm-client", () => ({
  streamChat: vi.fn(async (_cfg, _msgs, cb) => {
    const resp = pendingResponses.shift() ?? ""
    cb.onToken(resp)
    cb.onDone()
  }),
}))

import { autoIngest } from "./ingest"
import { useWikiStore } from "@/stores/wiki-store"
import { useReviewStore } from "@/stores/review-store"
import { useActivityStore } from "@/stores/activity-store"
import { useChatStore } from "@/stores/chat-store"

const FIXTURES_ROOT = path.join(
  process.cwd(),
  "tests",
  "fixtures",
  "scenarios-ingest",
)

beforeAll(async () => {
  await fs.rm(FIXTURES_ROOT, { recursive: true, force: true })
  await fs.mkdir(FIXTURES_ROOT, { recursive: true })
  for (const s of ingestScenarios) {
    await materializeScenario(s, FIXTURES_ROOT)
  }
})

beforeEach(() => {
  pendingResponses = []
  embeddingMocks.embedPage.mockReset()
  useReviewStore.setState({ items: [] })
  useActivityStore.setState({ items: [] })
  useChatStore.setState({
    conversations: [],
    messages: [],
    activeConversationId: null,
    mode: "chat",
    ingestSource: null,
    isStreaming: false,
    streamingContent: "",
  })
})

async function setupBareProject(name: string): Promise<Ctx> {
  const tmp = await createTempProject(name)
  await fs.mkdir(path.join(tmp.path, "raw", "sources"), { recursive: true })
  await fs.mkdir(path.join(tmp.path, "wiki", "sources"), { recursive: true })
  await fs.writeFile(path.join(tmp.path, "schema.md"), "", "utf-8")
  await fs.writeFile(path.join(tmp.path, "purpose.md"), "", "utf-8")
  await fs.writeFile(path.join(tmp.path, "wiki", "index.md"), "# Index\n", "utf-8")
  await fs.writeFile(path.join(tmp.path, "wiki", "overview.md"), "# Overview\n", "utf-8")

  useWikiStore.setState({
    project: {
      name: "t",
      path: tmp.path,
      createdAt: 0,
      purposeText: "",
      fileTree: [],
    } as unknown as ReturnType<typeof useWikiStore.getState>["project"],
  })
  useWikiStore.getState().setLlmConfig({
    provider: "openai",
    apiKey: "test-key",
    model: "gpt-4",
    ollamaUrl: "",
    customEndpoint: "",
    maxContextSize: 128000,
  })

  return { tmp }
}

interface Ctx {
  tmp: { path: string; cleanup: () => Promise<void> }
}
let ctx: Ctx | undefined

async function setup(scenario: IngestScenario): Promise<Ctx> {
  const tmp = await createTempProject(
    `ingest-${scenario.name.replace(/\//g, "-")}`,
  )
  const initialWikiDir = path.join(FIXTURES_ROOT, scenario.name, "initial-wiki")
  await copyDir(initialWikiDir, tmp.path)

  useWikiStore.setState({
    project: {
      name: "t",
      path: tmp.path,
      createdAt: 0,
      purposeText: "",
      fileTree: [],
    } as unknown as ReturnType<typeof useWikiStore.getState>["project"],
  })
  useWikiStore.getState().setLlmConfig({
    provider: "openai",
    apiKey: "test-key",
    model: "gpt-4",
    ollamaUrl: "",
    customEndpoint: "",
    maxContextSize: 128000,
  })

  // Queue up the two sequenced LLM responses
  const analysis = await fs.readFile(
    path.join(FIXTURES_ROOT, scenario.name, "llm-analysis.txt"),
    "utf-8",
  )
  const generation = await fs.readFile(
    path.join(FIXTURES_ROOT, scenario.name, "llm-generation.txt"),
    "utf-8",
  )
  pendingResponses = [analysis, generation]

  return { tmp }
}

afterEach(async () => {
  if (ctx) {
    await ctx.tmp.cleanup()
    ctx = undefined
  }
})

// ── Assertions ──────────────────────────────────────────────────────────────

async function assertOutcome(
  scenario: IngestScenario,
  tmpPath: string,
): Promise<void> {
  const expected = scenario.expected

  // 1. Expected files exist
  for (const p of expected.writtenPaths) {
    const full = path.join(tmpPath, p)
    const exists = await fileExists(full)
    if (!exists) {
      // eslint-disable-next-line no-console
      console.error(
        `\n[ingest: ${scenario.name}] expected file not written: ${p}`,
      )
    }
    expect(exists, `file not written: ${p}`).toBe(true)
  }

  // 2. File contents contain expected substrings
  if (expected.fileContains) {
    for (const [relPath, substrs] of Object.entries(expected.fileContains)) {
      const full = path.join(tmpPath, relPath)
      const content = await readFileRaw(full)
      for (const sub of substrs) {
        expect(content, `${relPath} missing substring "${sub}"`).toContain(sub)
      }
    }
  }

  // 3. Review store has the expected items
  const expectedReviews = expected.reviewsCreated ?? []
  const actualReviews = useReviewStore.getState().items
  for (const e of expectedReviews) {
    const match = actualReviews.find(
      (r) => r.type === e.type && r.title.includes(e.titleContains),
    )
    if (!match) {
      // eslint-disable-next-line no-console
      console.error(
        `\n[ingest: ${scenario.name}] no review matching ${JSON.stringify(e)}. Actual:\n` +
          JSON.stringify(
            actualReviews.map((r) => ({ type: r.type, title: r.title })),
            null,
            2,
          ),
      )
    }
    expect(match, `review missing: ${JSON.stringify(e)}`).toBeTruthy()
  }

  // 4. If the scenario declared no reviews, store must be empty.
  if (expectedReviews.length === 0) {
    expect(actualReviews).toHaveLength(0)
  }
}

// ── Tests ───────────────────────────────────────────────────────────────────

describe("ingest scenarios (fixture-driven)", () => {
  it.each(ingestScenarios.map((s) => [s.name, s]))(
    "%s",
    async (_name, scenario) => {
      ctx = await setup(scenario)

      const sourceFullPath = path.join(ctx.tmp.path, scenario.source.path)
      await autoIngest(
        ctx.tmp.path,
        sourceFullPath,
        useWikiStore.getState().llmConfig,
      )

      await assertOutcome(scenario, ctx.tmp.path)
    },
  )
})

describe("autoIngest hardening", () => {
  it("does not overwrite an existing source summary when fallback summary is needed", async () => {
    ctx = await setupBareProject("ingest-existing-source-summary")
    const sourcePath = path.join(ctx.tmp.path, "raw", "sources", "meeting.md")
    await fs.writeFile(sourcePath, "Alice helped Bob ship release notes.", "utf-8")
    const summaryPath = path.join(ctx.tmp.path, "wiki", "sources", "meeting.md")
    const existingSummary = "# Source: meeting.md\n\nExisting curated summary."
    await fs.writeFile(summaryPath, existingSummary, "utf-8")

    pendingResponses = [
      "Alice and Bob worked together.",
      [
        "---FILE: wiki/entities/alice.md---",
        "# Alice",
        "",
        "Alice helped Bob.",
        "---END FILE---",
      ].join("\n"),
    ]

    await autoIngest(ctx.tmp.path, sourcePath, useWikiStore.getState().llmConfig)

    await expect(fs.readFile(summaryPath, "utf-8")).resolves.toBe(existingSummary)
  })

  it("uses relative wiki paths for embedding page ids so same-name entity and concept pages do not collide", async () => {
    ctx = await setupBareProject("ingest-embedding-page-id")
    const sourcePath = path.join(ctx.tmp.path, "raw", "sources", "meeting.md")
    await fs.writeFile(sourcePath, "KnowYou is both a product and a concept here.", "utf-8")
    useWikiStore.setState({
      embeddingConfig: {
        enabled: true,
        endpoint: "http://example.test/v1/embeddings",
        apiKey: "test-key",
        model: "text-embedding-test",
        maxChunkChars: undefined,
        overlapChunkChars: undefined,
      },
    } as Partial<ReturnType<typeof useWikiStore.getState>>)
    embeddingMocks.embedPage.mockResolvedValue(undefined)

    pendingResponses = [
      "KnowYou appears as an entity and concept.",
      [
        "---FILE: wiki/sources/meeting.md---",
        "# Source: meeting.md",
        "",
        "Source summary.",
        "---END FILE---",
        "---FILE: wiki/entities/knowyou.md---",
        "# KnowYou",
        "",
        "KnowYou product.",
        "---END FILE---",
        "---FILE: wiki/concepts/knowyou.md---",
        "# KnowYou",
        "",
        "KnowYou concept.",
        "---END FILE---",
      ].join("\n"),
    ]

    await autoIngest(ctx.tmp.path, sourcePath, useWikiStore.getState().llmConfig)

    const pageIds = embeddingMocks.embedPage.mock.calls
      .map((call) => call[1])
      .filter((pageId) => pageId.includes("knowyou"))
      .sort()
    expect(pageIds).toEqual(["concepts/knowyou", "entities/knowyou"])
  })
})
