import { describe, it, expect, beforeEach } from "vitest"
import { buildAnalysisPrompt, buildGenerationPrompt } from "./ingest"
import { useWikiStore } from "@/stores/wiki-store"

beforeEach(() => {
  useWikiStore.getState().setOutputLanguage("auto")
})

describe("buildAnalysisPrompt language directive", () => {
  it("injects the user's explicit language setting", () => {
    useWikiStore.getState().setOutputLanguage("Chinese")
    const prompt = buildAnalysisPrompt("purpose", "index", "english source content")
    expect(prompt).toContain("MANDATORY OUTPUT LANGUAGE: Chinese")
  })

  it("uses user setting even when source is in a different language", () => {
    useWikiStore.getState().setOutputLanguage("Japanese")
    const prompt = buildAnalysisPrompt("", "", "这段内容是中文")
    expect(prompt).toContain("MANDATORY OUTPUT LANGUAGE: Japanese")
    expect(prompt).not.toContain("OUTPUT LANGUAGE: Chinese")
  })

  it("auto mode falls back to detecting source content language", () => {
    useWikiStore.getState().setOutputLanguage("auto")
    const prompt = buildAnalysisPrompt("", "", "これは日本語の文章です")
    expect(prompt).toContain("MANDATORY OUTPUT LANGUAGE: Japanese")
  })

  it("auto mode with empty source defaults to English", () => {
    useWikiStore.getState().setOutputLanguage("auto")
    const prompt = buildAnalysisPrompt("", "", "")
    expect(prompt).toContain("MANDATORY OUTPUT LANGUAGE: English")
  })

  it("contains structural analysis sections", () => {
    const prompt = buildAnalysisPrompt("", "", "")
    expect(prompt).toContain("## Key Entities")
    expect(prompt).toContain("## Key Concepts")
    expect(prompt).toContain("## Main Arguments & Findings")
    expect(prompt).toContain("## Recommendations")
  })
})

describe("buildGenerationPrompt language directive", () => {
  it("injects the user's explicit language setting", () => {
    useWikiStore.getState().setOutputLanguage("Chinese")
    const prompt = buildGenerationPrompt("schema", "purpose", "index", "source.pdf")
    expect(prompt).toContain("MANDATORY OUTPUT LANGUAGE: Chinese")
  })

  it("honors Vietnamese setting", () => {
    useWikiStore.getState().setOutputLanguage("Vietnamese")
    const prompt = buildGenerationPrompt("", "", "", "file.pdf")
    expect(prompt).toContain("MANDATORY OUTPUT LANGUAGE: Vietnamese")
  })

  it("auto mode detects from source content", () => {
    useWikiStore.getState().setOutputLanguage("auto")
    const prompt = buildGenerationPrompt("", "", "", "file.pdf", undefined, "这是中文源文档内容")
    expect(prompt).toContain("MANDATORY OUTPUT LANGUAGE: Chinese")
  })

  it("includes the source filename in output instructions", () => {
    const prompt = buildGenerationPrompt("", "", "", "my-paper.pdf")
    expect(prompt).toContain("my-paper.pdf")
  })

  it("uses My Wiki category directories instead of generic entity/concept pages when KnowYou contract is present", () => {
    const prompt = buildGenerationPrompt(
      [
        "<!-- KNOWYOU_MY_WIKI_OUTPUT_CONTRACT -->",
        "## My Wiki Output Contract",
        "| Category | Directory | Frontmatter types | Use |",
        "| --- | --- | --- | --- |",
        "| People | `wiki/people` | `person` | Real people. |",
        "| Projects | `wiki/projects` | `project` | Named efforts. |",
        "| Events | `wiki/events` | `event` | Bounded happenings. |",
        "| Topics | `wiki/topics` | `topic` | Recurring subjects. |",
        "| Preferences | `wiki/preferences` | `preference` | Stable preferences. |",
        "| Follow-ups | `wiki/follow-ups` | `follow-up` | Unresolved items. |",
      ].join("\n"),
      "purpose",
      "index",
      "knowyou-diary-2026-05-15.md",
    )

    expect(prompt).toContain("Pages for People in wiki/people/")
    expect(prompt).toContain("Pages for Projects in wiki/projects/")
    expect(prompt).toContain("Pages for Events in wiki/events/")
    expect(prompt).toContain("Pages for Topics in wiki/topics/")
    expect(prompt).toContain("Pages for Preferences in wiki/preferences/")
    expect(prompt).toContain("Pages for Follow-ups in wiki/follow-ups/")
    expect(prompt).toContain("Do NOT create `wiki/people/codex.md`")
    expect(prompt).not.toContain("Entity pages in wiki/entities/")
    expect(prompt).not.toContain("Concept pages in wiki/concepts/")
  })

  it("builds My Wiki generation targets from schema categories instead of hardcoded Swift categories", () => {
    const prompt = buildGenerationPrompt(
      [
        "<!-- KNOWYOU_MY_WIKI_OUTPUT_CONTRACT -->",
        "## My Wiki Output Contract",
        "| Category | Directory | Frontmatter types | Use |",
        "| --- | --- | --- | --- |",
        "| Relationships | `wiki/relationships` | `relationship` | Important relationships between entities. |",
      ].join("\n"),
      "purpose",
      "index",
      "knowyou-diary-2026-05-15.md",
    )

    expect(prompt).toContain("Pages for Relationships in wiki/relationships/")
    expect(prompt).toContain("one of: source | relationship")
    expect(prompt).not.toContain("People pages in wiki/people/")
    expect(prompt).not.toContain("Project pages in wiki/projects/")
    expect(prompt).not.toContain("Topic pages in wiki/themes/")
    expect(prompt).not.toContain("Follow-up pages in wiki/open-loops/")
  })

  it("respects user setting regardless of source content language", () => {
    useWikiStore.getState().setOutputLanguage("English")
    const prompt = buildGenerationPrompt("", "", "", "x.pdf", undefined, "私は日本語の文章を書きます")
    expect(prompt).toContain("MANDATORY OUTPUT LANGUAGE: English")
    expect(prompt).not.toContain("OUTPUT LANGUAGE: Japanese")
  })
})

describe("analysis + generation prompt consistency", () => {
  // Both stages MUST declare the same target language — otherwise the wiki
  // files generated in stage 2 may disagree with the analysis from stage 1.
  it("both stages declare the same language for a given setting", () => {
    useWikiStore.getState().setOutputLanguage("Korean")
    const analysis = buildAnalysisPrompt("", "", "")
    const generation = buildGenerationPrompt("", "", "", "f.pdf")
    expect(analysis).toContain("MANDATORY OUTPUT LANGUAGE: Korean")
    expect(generation).toContain("MANDATORY OUTPUT LANGUAGE: Korean")
  })

  it("both stages in auto mode agree on detected language from source", () => {
    useWikiStore.getState().setOutputLanguage("auto")
    const korean = "이것은 한국어 문장입니다"
    const analysis = buildAnalysisPrompt("", "", korean)
    const generation = buildGenerationPrompt("", "", "", "f.pdf", undefined, korean)
    expect(analysis).toContain("MANDATORY OUTPUT LANGUAGE: Korean")
    expect(generation).toContain("MANDATORY OUTPUT LANGUAGE: Korean")
  })
})
