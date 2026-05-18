import { describe, expect, it, vi, beforeEach } from "vitest"
import fs from "node:fs/promises"
import path from "node:path"
import { createTempProject, fileExists, readFileRaw, realFs, writeFileRaw } from "@/test-helpers/fs-temp"

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
      await writeFileRaw(path.join(tmp.path, "schema.md"), "# Schema\n\nCreate people pages.")
      await writeFileRaw(path.join(tmp.path, "purpose.md"), "# Purpose\n\nBuild My Wiki.")
      await writeFileRaw(path.join(tmp.path, "wiki/index.md"), "# My Wiki Index\n")
      await writeFileRaw(path.join(tmp.path, "wiki/overview.md"), "# Overview\n")
      await writeFileRaw(
        path.join(tmp.path, "raw/sources/knowyou-diary-2026-05-14.md"),
        "# 2026-05-14\n\nMet Huang Shan about Lenovo platform ownership.",
      )

      pendingResponses = [
        "Huang Shan is a person who appears in the journal.",
        [
          "---FILE: wiki/people/huang-shan.md---",
          "---",
          "type: person",
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
          "Huang Shan appears in the journal as a Lenovo platform contact.",
          "---END FILE---",
          "---FILE: wiki/index.md---",
          "# My Wiki Index",
          "",
          "## People",
          "",
          "- [[people/huang-shan|Huang Shan]]",
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
      expect(await fileExists(path.join(tmp.path, "wiki/people/huang-shan.md"))).toBe(true)
      expect(await readFileRaw(path.join(tmp.path, "schema.md"))).toContain(
        "Do not write `wiki/entities/`, `wiki/concepts/`, or generic ontology folders.",
      )
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
        "# 2026-05-15\n\nHuang Shan connects Lenovo platform ownership to the My Wiki redesign.",
      )

      pendingResponses = [
        "The source contains a relationship between Huang Shan, Lenovo, and My Wiki.",
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
          "Huang Shan connects Lenovo platform ownership to the My Wiki redesign.",
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
      expect(schemaMarkdown).not.toContain("wiki/themes/")
      expect(schemaMarkdown).not.toContain("wiki/open-loops/")
      expect(await fileExists(path.join(tmp.path, "wiki/relationships/huang-shan-lenovo-my-wiki.md"))).toBe(true)
    } finally {
      await tmp.cleanup()
    }
  })
})
