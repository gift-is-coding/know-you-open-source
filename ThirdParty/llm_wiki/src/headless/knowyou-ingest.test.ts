import { describe, expect, it, vi, beforeEach } from "vitest"
import fs from "node:fs/promises"
import path from "node:path"
import { createTempProject, fileExists, readFileRaw, realFs, writeFileRaw } from "@/test-helpers/fs-temp"
import { useWikiStore } from "@/stores/wiki-store"

vi.mock("@/commands/fs", () => realFs)

let pendingResponses: Array<string | Error> = []
let streamedPrompts: string[] = []
vi.mock("@/lib/llm-client", () => ({
  streamChat: vi.fn(async (_cfg, messages, callbacks) => {
    streamedPrompts.push(
      messages
        .map((message: { content: string }) => message.content)
        .join("\n\n"),
    )
    const response = pendingResponses.shift() ?? ""
    if (response instanceof Error) {
      throw response
    }
    callbacks.onToken(response)
    callbacks.onDone()
  }),
}))

import { INGEST_CACHE_PIPELINE_VERSION } from "@/lib/ingest"
import { runKnowYouIngest, runKnowYouIngestCli } from "./knowyou-ingest"

beforeEach(() => {
  pendingResponses = []
  streamedPrompts = []
})

describe("KnowYou headless ingest runner", () => {
  it("uses a cache version that invalidates pre-context-removal outputs", () => {
    expect(INGEST_CACHE_PIPELINE_VERSION).toContain("v5")
    expect(INGEST_CACHE_PIPELINE_VERSION).toContain("native-contextless")
  })

  it("reuses autoIngest to materialize wiki pages from raw journal sources", async () => {
    const tmp = await createTempProject("knowyou-headless-ingest")
    try {
      await fs.mkdir(path.join(tmp.path, "raw/sources"), { recursive: true })
      await fs.mkdir(path.join(tmp.path, "wiki"), { recursive: true })
      await writeFileRaw(
        path.join(tmp.path, "schema.md"),
        "# My Wiki Schema\n\nDo not copy secrets. person, project, organization, or other.",
      )
      await writeFileRaw(path.join(tmp.path, "purpose.md"), "# Project Purpose\n\nBuild My Wiki.")
      await writeFileRaw(path.join(tmp.path, "mywiki.schema.json"), "{}")
      await writeFileRaw(path.join(tmp.path, "wiki/index.md"), "# My Wiki Index\n")
      await writeFileRaw(path.join(tmp.path, "wiki/overview.md"), "# Overview\n")
      await writeFileRaw(
        path.join(tmp.path, "raw/sources/knowyou-diary-2026-05-14.md"),
        "# 2026-05-14\n\n和黄山讨论联想平台归属问题。",
      )

      pendingResponses = [
        "黄山是日记中出现的人物，和联想平台归属有关。",
        [
          "---FILE: wiki/entities/huang-shan.md---",
          "---",
          "type: entity",
          "title: Huang Shan",
          "aliases: [黄山]",
          "related: [Lenovo]",
          "source_days: [2026-05-14]",
          "confidence: medium",
          "---",
          "",
          "# Huang Shan",
          "",
          "## Summary",
          "",
          "黄山在日记中作为联想平台联系人出现，讨论平台归属和协作边界。",
          "---END FILE---",
          "---FILE: wiki/index.md---",
          "# My Wiki Index",
          "",
          "## Entities",
          "",
          "- [[entities/huang-shan|Huang Shan]]",
          "---END FILE---",
        ].join("\n"),
      ]

      const status = await runKnowYouIngest({
        projectPath: tmp.path,
        provider: "openai",
        model: "test-model",
      })

      expect(status.status).toBe("succeeded")
      expect(status.sourcesProcessed).toBe(1)
      expect(status.sourcesTotal).toBe(1)
      expect(await fileExists(path.join(tmp.path, "wiki/entities/huang-shan.md"))).toBe(true)
      expect(await fileExists(path.join(tmp.path, "schema.md"))).toBe(false)
      expect(await fileExists(path.join(tmp.path, "purpose.md"))).toBe(false)
      expect(await fileExists(path.join(tmp.path, "mywiki.schema.json"))).toBe(false)
      const promptText = streamedPrompts.join("\n\n")
      expect(promptText).not.toContain("My Wiki Schema")
      expect(promptText).not.toContain("Project Purpose")
      expect(promptText).not.toContain("person, project, organization, or other")
      expect(promptText).not.toContain("Do not copy secrets")
      expect(await readFileRaw(path.join(tmp.path, ".llm-wiki/last-ingest-status.json"))).toContain(
        '"status": "succeeded"',
      )
      expect(await readFileRaw(path.join(tmp.path, ".llm-wiki/last-ingest-status.json"))).toContain(
        '"sourcesTotal": 1',
      )
    } finally {
      await tmp.cleanup()
    }
  })

  it("limits each run to unindexed sources before revisiting indexed sources", async () => {
    const tmp = await createTempProject("knowyou-headless-ingest-batch")
    try {
      await fs.mkdir(path.join(tmp.path, "raw/sources"), { recursive: true })
      await fs.mkdir(path.join(tmp.path, "wiki/sources"), { recursive: true })
      await writeFileRaw(path.join(tmp.path, "wiki/index.md"), "# My Wiki Index\n")
      await writeFileRaw(path.join(tmp.path, "wiki/overview.md"), "# Overview\n")

      for (const day of ["10", "11", "12", "13", "14"]) {
        await writeFileRaw(
          path.join(tmp.path, `raw/sources/knowyou-diary-2026-05-${day}.md`),
          `# 2026-05-${day}\n\nJournal content for ${day}.`,
        )
      }
      await writeFileRaw(path.join(tmp.path, "wiki/sources/knowyou-diary-2026-05-14.md"), "# Already indexed 14\n")
      await writeFileRaw(path.join(tmp.path, "wiki/sources/knowyou-diary-2026-05-13.md"), "# Already indexed 13\n")

      pendingResponses = [
        "Analysis for May 12.",
        sourceSummaryBlock("2026-05-12"),
        "Analysis for May 11.",
        sourceSummaryBlock("2026-05-11"),
      ]

      const status = await runKnowYouIngest({
        projectPath: tmp.path,
        provider: "openai",
        model: "test-model",
        maxSources: 2,
      })

      expect(status.sourcesProcessed).toBe(2)
      expect(status.sourcesTotal).toBe(2)
      expect(streamedPrompts.join("\n")).toContain("knowyou-diary-2026-05-12.md")
      expect(streamedPrompts.join("\n")).toContain("knowyou-diary-2026-05-11.md")
      expect(streamedPrompts.join("\n")).not.toContain("knowyou-diary-2026-05-14.md")
      expect(streamedPrompts.join("\n")).not.toContain("knowyou-diary-2026-05-13.md")
      expect(await fileExists(path.join(tmp.path, "wiki/sources/knowyou-diary-2026-05-12.md"))).toBe(true)
      expect(await fileExists(path.join(tmp.path, "wiki/sources/knowyou-diary-2026-05-11.md"))).toBe(true)
      expect(await fileExists(path.join(tmp.path, "wiki/sources/knowyou-diary-2026-05-10.md"))).toBe(false)
    } finally {
      await tmp.cleanup()
    }
  })

  it("ingests only manifest-listed sources and passes folder context into prompts", async () => {
    const tmp = await createTempProject("knowyou-headless-manifest")
    try {
      await fs.mkdir(path.join(tmp.path, "raw/sources/My Diary"), { recursive: true })
      await fs.mkdir(path.join(tmp.path, ".knowyou"), { recursive: true })
      await fs.mkdir(path.join(tmp.path, "wiki"), { recursive: true })
      await writeFileRaw(path.join(tmp.path, "purpose.md"), "# Purpose\n\nBuild My Wiki.")
      await writeFileRaw(path.join(tmp.path, "wiki/index.md"), "# My Wiki Index\n")
      await writeFileRaw(path.join(tmp.path, "wiki/overview.md"), "# Overview\n")
      await writeFileRaw(
        path.join(tmp.path, "raw/sources/My Diary/knowyou-diary-2026-05-27.md"),
        "# 2026-05-27\n\nDiscussed source catalog handoff with Task 2.",
      )
      await writeFileRaw(
        path.join(tmp.path, "raw/sources/skip-me.md"),
        "# Skip me\n\nThis source must not be ingested by a manifest run.",
      )
      const manifestPath = path.join(tmp.path, ".knowyou/ingest-manifest.json")
      await writeFileRaw(
        manifestPath,
        JSON.stringify({
          sources: [
            {
              sourcePath: "raw/sources/My Diary/knowyou-diary-2026-05-27.md",
              sourceID: "diary-2026-05-27",
              displayTitle: "May 27 Diary",
              folderContext: "My Diary > 2026 > May",
              sourceKind: "diary",
              contentHash: "abc123",
            },
          ],
        }),
      )

      pendingResponses = [
        "Analysis for May 27.",
        sourceSummaryBlock("2026-05-27"),
      ]

      const status = await runKnowYouIngest({
        projectPath: tmp.path,
        provider: "openai",
        model: "test-model",
        manifestPath,
      })

      const promptText = streamedPrompts.join("\n\n")
      expect(status.sourcesProcessed).toBe(1)
      expect(status.sourcesTotal).toBe(1)
      expect(promptText).toContain("knowyou-diary-2026-05-27.md")
      expect(promptText).toContain("**Folder context:** My Diary > 2026 > May")
      expect(promptText).not.toContain("skip-me.md")
      expect(await fileExists(path.join(tmp.path, "wiki/sources/knowyou-diary-2026-05-27.md"))).toBe(true)
    } finally {
      await tmp.cleanup()
    }
  })

  it("can resume by skipping already indexed source summaries", async () => {
    const tmp = await createTempProject("knowyou-headless-skip-indexed")
    try {
      await fs.mkdir(path.join(tmp.path, "raw/sources"), { recursive: true })
      await fs.mkdir(path.join(tmp.path, "wiki/sources"), { recursive: true })
      await writeFileRaw(path.join(tmp.path, "wiki/index.md"), "# My Wiki Index\n")
      await writeFileRaw(path.join(tmp.path, "wiki/overview.md"), "# Overview\n")

      for (const day of ["10", "11", "12"]) {
        await writeFileRaw(
          path.join(tmp.path, `raw/sources/knowyou-diary-2026-05-${day}.md`),
          `# 2026-05-${day}\n\nJournal content for ${day}.`,
        )
      }
      await writeFileRaw(path.join(tmp.path, "wiki/sources/knowyou-diary-2026-05-10.md"), "# Already indexed 10\n")

      pendingResponses = [
        "Analysis for May 11.",
        sourceSummaryBlock("2026-05-11"),
        "Analysis for May 12.",
        sourceSummaryBlock("2026-05-12"),
      ]

      const status = await runKnowYouIngest({
        projectPath: tmp.path,
        provider: "openai",
        model: "test-model",
        skipIndexed: true,
      })

      expect(status.status).toBe("succeeded")
      expect(status.sourcesProcessed).toBe(2)
      expect(status.sourcesTotal).toBe(2)
      expect(streamedPrompts.join("\n")).not.toContain("knowyou-diary-2026-05-10.md")
      expect(streamedPrompts.join("\n")).toContain("knowyou-diary-2026-05-11.md")
      expect(streamedPrompts.join("\n")).toContain("knowyou-diary-2026-05-12.md")
    } finally {
      await tmp.cleanup()
    }
  })

  it("rejects manifest source paths that resolve outside raw/sources", async () => {
    const tmp = await createTempProject("knowyou-headless-manifest-unsafe")
    try {
      await fs.mkdir(path.join(tmp.path, "raw/sources"), { recursive: true })
      await fs.mkdir(path.join(tmp.path, ".knowyou"), { recursive: true })
      await fs.mkdir(path.join(tmp.path, "wiki"), { recursive: true })
      await writeFileRaw(path.join(tmp.path, "purpose.md"), "# Purpose\n\nBuild My Wiki.")
      await writeFileRaw(path.join(tmp.path, "wiki/index.md"), "# My Wiki Index\n")
      await writeFileRaw(path.join(tmp.path, "wiki/overview.md"), "# Overview\n")
      const manifestPath = path.join(tmp.path, ".knowyou/ingest-manifest.json")
      await writeFileRaw(
        manifestPath,
        JSON.stringify({
          sources: [
            {
              sourcePath: "raw/sources/../../wiki/index.md",
              folderContext: "Unsafe",
            },
          ],
        }),
      )

      await expect(
        runKnowYouIngest({
          projectPath: tmp.path,
          provider: "openai",
          model: "test-model",
          manifestPath,
        }),
      ).rejects.toThrow("Manifest sourcePath must stay inside raw/sources")
    } finally {
      await tmp.cleanup()
    }
  })

  it("rejects manifest source symlinks that target files outside raw/sources", async () => {
    const tmp = await createTempProject("knowyou-headless-manifest-symlink")
    try {
      await fs.mkdir(path.join(tmp.path, "raw/sources"), { recursive: true })
      await fs.mkdir(path.join(tmp.path, ".knowyou"), { recursive: true })
      await fs.mkdir(path.join(tmp.path, "wiki"), { recursive: true })
      await writeFileRaw(path.join(tmp.path, "purpose.md"), "# Purpose\n\nBuild My Wiki.")
      await writeFileRaw(path.join(tmp.path, "wiki/index.md"), "# My Wiki Index\n")
      await writeFileRaw(path.join(tmp.path, "wiki/overview.md"), "# Overview\n")
      await writeFileRaw(path.join(tmp.path, "secret.md"), "# Secret\n\nThis file is outside raw sources.")
      await fs.symlink(path.join(tmp.path, "secret.md"), path.join(tmp.path, "raw/sources/link.md"))
      const manifestPath = path.join(tmp.path, ".knowyou/ingest-manifest.json")
      await writeFileRaw(
        manifestPath,
        JSON.stringify({
          sources: [
            {
              sourcePath: "raw/sources/link.md",
              folderContext: "Unsafe symlink",
            },
          ],
        }),
      )

      pendingResponses = [
        "Analysis for symlink.",
        sourceSummaryBlock("link"),
      ]

      await expect(
        runKnowYouIngest({
          projectPath: tmp.path,
          provider: "openai",
          model: "test-model",
          manifestPath,
        }),
      ).rejects.toThrow("Manifest sourcePath must stay inside raw/sources")
    } finally {
      await tmp.cleanup()
    }
  })

  it("rejects malformed top-level manifest JSON", async () => {
    const tmp = await createTempProject("knowyou-headless-manifest-null")
    try {
      await fs.mkdir(path.join(tmp.path, "raw/sources"), { recursive: true })
      await fs.mkdir(path.join(tmp.path, ".knowyou"), { recursive: true })
      await fs.mkdir(path.join(tmp.path, "wiki"), { recursive: true })
      await writeFileRaw(path.join(tmp.path, "purpose.md"), "# Purpose\n\nBuild My Wiki.")
      await writeFileRaw(path.join(tmp.path, "wiki/index.md"), "# My Wiki Index\n")
      await writeFileRaw(path.join(tmp.path, "wiki/overview.md"), "# Overview\n")
      const manifestPath = path.join(tmp.path, ".knowyou/ingest-manifest.json")
      await writeFileRaw(manifestPath, "null")

      await expect(
        runKnowYouIngest({
          projectPath: tmp.path,
          provider: "openai",
          model: "test-model",
          manifestPath,
        }),
      ).rejects.toThrow("Malformed ingest manifest")
    } finally {
      await tmp.cleanup()
    }
  })

  it("rejects duplicate manifest source paths", async () => {
    const tmp = await createTempProject("knowyou-headless-manifest-duplicate")
    try {
      await fs.mkdir(path.join(tmp.path, "raw/sources"), { recursive: true })
      await fs.mkdir(path.join(tmp.path, ".knowyou"), { recursive: true })
      await fs.mkdir(path.join(tmp.path, "wiki"), { recursive: true })
      await writeFileRaw(path.join(tmp.path, "purpose.md"), "# Purpose\n\nBuild My Wiki.")
      await writeFileRaw(path.join(tmp.path, "wiki/index.md"), "# My Wiki Index\n")
      await writeFileRaw(path.join(tmp.path, "wiki/overview.md"), "# Overview\n")
      await writeFileRaw(path.join(tmp.path, "raw/sources/duplicate.md"), "# Duplicate\n")
      const manifestPath = path.join(tmp.path, ".knowyou/ingest-manifest.json")
      await writeFileRaw(
        manifestPath,
        JSON.stringify({
          sources: [
            { sourcePath: "raw/sources/duplicate.md", folderContext: "First" },
            { sourcePath: "raw/sources/duplicate.md", folderContext: "Second" },
          ],
        }),
      )

      pendingResponses = [
        "Analysis for duplicate.",
        sourceSummaryBlock("duplicate"),
      ]

      await expect(
        runKnowYouIngest({
          projectPath: tmp.path,
          provider: "openai",
          model: "test-model",
          manifestPath,
        }),
      ).rejects.toThrow("Duplicate manifest sourcePath")
    } finally {
      await tmp.cleanup()
    }
  })

  it("accepts --manifest through the CLI", async () => {
    const tmp = await createTempProject("knowyou-headless-manifest-cli")
    const stdoutWrite = vi.spyOn(process.stdout, "write").mockImplementation(() => true)
    const stderrWrite = vi.spyOn(process.stderr, "write").mockImplementation(() => true)
    const originalExitCode = process.exitCode
    process.exitCode = undefined
    try {
      await fs.mkdir(path.join(tmp.path, "raw/sources/My Diary"), { recursive: true })
      await fs.mkdir(path.join(tmp.path, ".knowyou"), { recursive: true })
      await fs.mkdir(path.join(tmp.path, "wiki"), { recursive: true })
      await writeFileRaw(path.join(tmp.path, "purpose.md"), "# Purpose\n\nBuild My Wiki.")
      await writeFileRaw(path.join(tmp.path, "wiki/index.md"), "# My Wiki Index\n")
      await writeFileRaw(path.join(tmp.path, "wiki/overview.md"), "# Overview\n")
      await writeFileRaw(
        path.join(tmp.path, "raw/sources/My Diary/knowyou-diary-2026-05-28.md"),
        "# 2026-05-28\n\nCLI manifest source.",
      )
      await writeFileRaw(path.join(tmp.path, "raw/sources/skip-me.md"), "# Skip me\n")
      const manifestPath = path.join(tmp.path, ".knowyou/ingest-manifest.json")
      await writeFileRaw(
        manifestPath,
        JSON.stringify({
          sources: [
            {
              sourcePath: "raw/sources/My Diary/knowyou-diary-2026-05-28.md",
              folderContext: "My Diary > CLI",
            },
          ],
        }),
      )

      pendingResponses = [
        "Analysis for May 28.",
        sourceSummaryBlock("2026-05-28"),
      ]

      await runKnowYouIngestCli([
        "--project",
        tmp.path,
        "--provider",
        "openai",
        "--model",
        "test-model",
        "--manifest",
        manifestPath,
      ])

      expect(process.exitCode).toBeUndefined()
      expect(stdoutWrite).toHaveBeenCalledWith(expect.stringContaining('"sourcesTotal":1'))
      expect(streamedPrompts.join("\n\n")).toContain("**Folder context:** My Diary > CLI")
      expect(streamedPrompts.join("\n\n")).not.toContain("skip-me.md")
    } finally {
      process.exitCode = originalExitCode
      stdoutWrite.mockRestore()
      stderrWrite.mockRestore()
      await tmp.cleanup()
    }
  })

  it("can continue after one source fails and report the failed source", async () => {
    const tmp = await createTempProject("knowyou-headless-continue-on-error")
    try {
      await fs.mkdir(path.join(tmp.path, "raw/sources"), { recursive: true })
      await fs.mkdir(path.join(tmp.path, "wiki"), { recursive: true })
      await writeFileRaw(path.join(tmp.path, "wiki/index.md"), "# My Wiki Index\n")
      await writeFileRaw(path.join(tmp.path, "wiki/overview.md"), "# Overview\n")
      await writeFileRaw(path.join(tmp.path, "raw/sources/knowyou-diary-2026-05-10.md"), "# 2026-05-10\n\nBad source.")
      await writeFileRaw(path.join(tmp.path, "raw/sources/knowyou-diary-2026-05-11.md"), "# 2026-05-11\n\nGood source.")

      pendingResponses = [
        new Error("analysis timeout"),
        "Analysis for May 11.",
        sourceSummaryBlock("2026-05-11"),
      ]

      const status = await runKnowYouIngest({
        projectPath: tmp.path,
        provider: "openai",
        model: "test-model",
        continueOnError: true,
      })

      expect(status.status).toBe("failed")
      expect(status.sourcesProcessed).toBe(1)
      expect(status.sourcesTotal).toBe(2)
      expect(status.failedSources).toEqual([
        {
          source: "knowyou-diary-2026-05-10.md",
          message: "analysis timeout",
        },
      ])
      expect(await fileExists(path.join(tmp.path, "wiki/sources/knowyou-diary-2026-05-11.md"))).toBe(true)
    } finally {
      await tmp.cleanup()
    }
  })

  it("does not inject custom My Wiki schema into native llm_wiki prompts", async () => {
    const tmp = await createTempProject("knowyou-headless-schema-ignored")
    try {
      await fs.mkdir(path.join(tmp.path, "raw/sources"), { recursive: true })
      await fs.mkdir(path.join(tmp.path, "wiki"), { recursive: true })
      await writeFileRaw(path.join(tmp.path, "schema.md"), "# My Wiki Schema\n\nRelationships should go to wiki/relationships.")
      await writeFileRaw(path.join(tmp.path, "purpose.md"), "# Project Purpose\n\nBuild My Wiki.")
      await writeFileRaw(path.join(tmp.path, "wiki/index.md"), "# My Wiki Index\n")
      await writeFileRaw(path.join(tmp.path, "wiki/overview.md"), "# Overview\n")
      await writeFileRaw(
        path.join(tmp.path, "mywiki.schema.json"),
        JSON.stringify({
          id: "custom",
          displayName: "Custom My Wiki",
          categories: [
            {
              id: "relationships",
              displayName: "Relationships",
              singularName: "Relationship",
              directory: "wiki/relationships",
              frontmatterTypes: ["relationship"],
              extractionGuidance: "Extract important relationships between people, projects, and organizations.",
              detailSections: ["Summary"],
            },
          ],
          views: [],
        }),
      )
      await writeFileRaw(
        path.join(tmp.path, "raw/sources/knowyou-diary-2026-05-15.md"),
        "# 2026-05-15\n\n黄山把联想平台归属问题和 My Wiki 改版中的知识整理需求连接起来。",
      )

      pendingResponses = [
        "来源包含黄山、联想和 My Wiki 之间的关系线索。",
        [
          "---FILE: wiki/entities/huang-shan.md---",
          "---",
          "type: entity",
          "title: Huang Shan",
          "sources: [knowyou-diary-2026-05-15.md]",
          "related: [lenovo, my-wiki]",
          "---",
          "",
          "# Huang Shan",
          "",
          "## Summary",
          "",
          "黄山把联想平台归属问题和 My Wiki 改版中的知识整理需求连接起来。",
          "---END FILE---",
        ].join("\n"),
      ]

      await runKnowYouIngest({
        projectPath: tmp.path,
        provider: "openai",
        model: "test-model",
      })

      const promptText = streamedPrompts.join("\n\n")
      expect(await fileExists(path.join(tmp.path, "schema.md"))).toBe(false)
      expect(await fileExists(path.join(tmp.path, "purpose.md"))).toBe(false)
      expect(await fileExists(path.join(tmp.path, "mywiki.schema.json"))).toBe(false)
      expect(promptText).not.toContain("Relationships should go to wiki/relationships")
      expect(promptText).not.toContain("Project Purpose")
      expect(promptText).not.toContain("My Wiki Schema")
      expect(await fileExists(path.join(tmp.path, "wiki/entities/huang-shan.md"))).toBe(true)
    } finally {
      await tmp.cleanup()
    }
  })

  it("removes stale schema and purpose prompt files instead of rewriting them", async () => {
    const tmp = await createTempProject("knowyou-headless-remove-schema")
    try {
      await fs.mkdir(path.join(tmp.path, "raw/sources"), { recursive: true })
      await fs.mkdir(path.join(tmp.path, "wiki"), { recursive: true })
      await writeFileRaw(
        path.join(tmp.path, "schema.md"),
        [
          "# Schema",
          "",
          "## entity | wiki/entities/",
          "Use this for named entities.",
          "",
          "## concept | wiki/concepts/",
          "Use this for concepts.",
        ].join("\n"),
      )
      await writeFileRaw(path.join(tmp.path, "purpose.md"), "# Purpose\n\nBuild My Wiki.")
      await writeFileRaw(path.join(tmp.path, "mywiki.schema.json"), "{}")
      await writeFileRaw(path.join(tmp.path, "wiki/index.md"), "# My Wiki Index\n")
      await writeFileRaw(path.join(tmp.path, "wiki/overview.md"), "# Overview\n")
      await writeFileRaw(
        path.join(tmp.path, "raw/sources/knowyou-diary-2026-05-16.md"),
        "# 2026-05-16\n\nMet Huang Shan about Lenovo platform ownership.",
      )

      pendingResponses = [
        "黄山是日记中出现的人物，和联想平台归属有关。",
        [
          "---FILE: wiki/entities/huang-shan.md---",
          "---",
          "type: entity",
          "title: Huang Shan",
          "sources: [knowyou-diary-2026-05-16.md]",
          "---",
          "",
          "# Huang Shan",
          "",
          "## Summary",
          "",
          "黄山在日记中作为联想平台联系人出现，讨论平台归属和协作边界。",
          "---END FILE---",
        ].join("\n"),
      ]

      await runKnowYouIngest({
        projectPath: tmp.path,
        provider: "openai",
        model: "test-model",
      })

      expect(await fileExists(path.join(tmp.path, "schema.md"))).toBe(false)
      expect(await fileExists(path.join(tmp.path, "purpose.md"))).toBe(false)
      expect(await fileExists(path.join(tmp.path, "mywiki.schema.json"))).toBe(false)
    } finally {
      await tmp.cleanup()
    }
  })

  it("keeps source-language auto detection for KnowYou output", async () => {
    const tmp = await createTempProject("knowyou-headless-language")
    try {
      await fs.mkdir(path.join(tmp.path, "raw/sources"), { recursive: true })
      await fs.mkdir(path.join(tmp.path, "wiki"), { recursive: true })
      await writeFileRaw(path.join(tmp.path, "wiki/index.md"), "# My Wiki Index\n")
      await writeFileRaw(path.join(tmp.path, "wiki/overview.md"), "# Overview\n")
      await writeFileRaw(
        path.join(tmp.path, "raw/sources/knowyou-diary-2026-05-17.md"),
        "# 2026-05-17\n\nAdam discussed an AI Builder rollout.",
      )

      pendingResponses = [
        "Adam 是日记中出现的人物，和 AI Builder 推进有关。",
        [
          "---FILE: wiki/entities/adam.md---",
          "---",
          "type: entity",
          "title: Adam",
          "sources: [knowyou-diary-2026-05-17.md]",
          "---",
          "",
          "# Adam",
          "",
          "## Summary",
          "",
          "Adam 在日记中被提到，关联 AI Builder 的推进和落地讨论。",
          "---END FILE---",
        ].join("\n"),
      ]

      await runKnowYouIngest({
        projectPath: tmp.path,
        provider: "openai",
        model: "test-model",
      })

      expect(useWikiStore.getState().outputLanguage).toBe("auto")
      const promptText = streamedPrompts.join("\n\n")
      expect(promptText).toContain("SOURCE LANGUAGE MODE: English")
      expect(promptText).toContain("Preserve proper nouns")
      expect(promptText).toContain("translations or explanations as aliases")
      expect(promptText).not.toContain("person, project, organization, or other")
      expect(promptText).not.toContain("MANDATORY OUTPUT LANGUAGE: Chinese")
      expect(promptText).not.toContain("standard Chinese transliteration")
    } finally {
      await tmp.cleanup()
    }
  })
})

function sourceSummaryBlock(day: string): string {
  return [
    `---FILE: wiki/sources/knowyou-diary-${day}.md---`,
    "---",
    "type: source",
    `title: KnowYou Diary ${day}`,
    `sources: [knowyou-diary-${day}.md]`,
    "tags: [knowyou, diary]",
    "related: []",
    "---",
    "",
    `# KnowYou Diary ${day}`,
    "",
    "## Summary",
    "",
    `Source summary for ${day}.`,
    "---END FILE---",
  ].join("\n")
}
