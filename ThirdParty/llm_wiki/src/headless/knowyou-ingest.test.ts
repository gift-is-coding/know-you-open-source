import { describe, expect, it, vi, beforeEach } from "vitest"
import fs from "node:fs/promises"
import path from "node:path"
import { createTempProject, fileExists, readFileRaw, realFs, writeFileRaw } from "@/test-helpers/fs-temp"
import { useWikiStore } from "@/stores/wiki-store"

vi.mock("@/commands/fs", () => realFs)

let pendingResponses: string[] = []
vi.mock("@/lib/llm-client", () => ({
  streamChat: vi.fn(async (_cfg, _messages, callbacks) => {
    const response = pendingResponses.shift() ?? ""
    callbacks.onToken(response)
    callbacks.onDone()
  }),
}))

import { runKnowYouIngest } from "./knowyou-ingest"

beforeEach(() => {
  pendingResponses = []
})

describe("KnowYou headless ingest runner", () => {
  it("reuses autoIngest to materialize wiki pages from raw journal sources", async () => {
    const tmp = await createTempProject("knowyou-headless-ingest")
    try {
      await fs.mkdir(path.join(tmp.path, "raw/sources"), { recursive: true })
      await fs.mkdir(path.join(tmp.path, "wiki"), { recursive: true })
      await writeFileRaw(path.join(tmp.path, "schema.md"), "# Schema\n\nCreate entity pages.")
      await writeFileRaw(path.join(tmp.path, "purpose.md"), "# Purpose\n\nBuild My Wiki.")
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
      expect(await readFileRaw(path.join(tmp.path, "schema.md"))).not.toContain("KNOWYOU_MY_WIKI_OUTPUT_CONTRACT")
      expect(await readFileRaw(path.join(tmp.path, "schema.md"))).not.toContain("Do not write `wiki/entities/`")
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

  it("generates the My Wiki output contract from mywiki.schema.json", async () => {
    const tmp = await createTempProject("knowyou-headless-schema-contract")
    try {
      await fs.mkdir(path.join(tmp.path, "raw/sources"), { recursive: true })
      await fs.mkdir(path.join(tmp.path, "wiki"), { recursive: true })
      await writeFileRaw(path.join(tmp.path, "schema.md"), "# Schema\n")
      await writeFileRaw(path.join(tmp.path, "purpose.md"), "# Purpose\n\nBuild My Wiki.")
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
          "---FILE: wiki/relationships/huang-shan-lenovo-my-wiki.md---",
          "---",
          "type: relationship",
          "title: Huang Shan, Lenovo, and My Wiki",
          "sources: [knowyou-diary-2026-05-15.md]",
          "related: []",
          "---",
          "",
          "# Huang Shan, Lenovo, and My Wiki",
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

      const schemaMarkdown = await readFileRaw(path.join(tmp.path, "schema.md"))
      expect(schemaMarkdown).toContain("Relationships")
      expect(schemaMarkdown).toContain("wiki/relationships")
      expect(schemaMarkdown).toContain("`relationship`")
      expect(schemaMarkdown).toContain("KNOWYOU_MY_WIKI_OUTPUT_CONTRACT")
      expect(schemaMarkdown).toContain("Do not write `wiki/entities/`")
      expect(schemaMarkdown).not.toContain("wiki/themes/")
      expect(schemaMarkdown).not.toContain("wiki/open-loops/")
      expect(await fileExists(path.join(tmp.path, "wiki/relationships/huang-shan-lenovo-my-wiki.md"))).toBe(true)
    } finally {
      await tmp.cleanup()
    }
  })

  it("replaces legacy generic ontology schema instead of appending to it", async () => {
    const tmp = await createTempProject("knowyou-headless-clean-schema")
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

      const schemaMarkdown = await readFileRaw(path.join(tmp.path, "schema.md"))
      expect(schemaMarkdown).toContain("# My Wiki Schema")
      expect(schemaMarkdown).toContain("Sources")
      expect(schemaMarkdown).toContain("Entities")
      expect(schemaMarkdown).toContain("Concepts")
      expect(schemaMarkdown).not.toContain("KNOWYOU_MY_WIKI_OUTPUT_CONTRACT")
      expect(schemaMarkdown).not.toContain("Do not write `wiki/entities/`")
      expect(schemaMarkdown).not.toContain("## entity | wiki/entities/")
      expect(schemaMarkdown).not.toContain("## concept | wiki/concepts/")
      expect(schemaMarkdown).not.toContain("Use this for named entities.")
      expect(schemaMarkdown).not.toContain("Use this for concepts.")
    } finally {
      await tmp.cleanup()
    }
  })

  it("keeps source-language auto detection for KnowYou output", async () => {
    const tmp = await createTempProject("knowyou-headless-language")
    try {
      await fs.mkdir(path.join(tmp.path, "raw/sources"), { recursive: true })
      await fs.mkdir(path.join(tmp.path, "wiki"), { recursive: true })
      await writeFileRaw(path.join(tmp.path, "schema.md"), "# Schema\n")
      await writeFileRaw(path.join(tmp.path, "purpose.md"), "# Purpose\n\nBuild My Wiki.")
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
    } finally {
      await tmp.cleanup()
    }
  })
})
