import fs from "node:fs/promises"
import path from "node:path"
import { autoIngest } from "@/lib/ingest"
import { useActivityStore } from "@/stores/activity-store"
import { useChatStore } from "@/stores/chat-store"
import { useReviewStore } from "@/stores/review-store"
import { useWikiStore, type LlmConfig } from "@/stores/wiki-store"

interface IngestOptions {
  projectPath: string
  provider?: LlmConfig["provider"]
  model?: string
  maxSources?: number
}

interface IngestStatus {
  status: "running" | "succeeded" | "failed"
  message: string
  updatedAt: string
  sourcesProcessed: number
  sourcesTotal: number
  filesWritten: string[]
}

const outputContractMarker = "<!-- KNOWYOU_MY_WIKI_OUTPUT_CONTRACT -->"

interface MyWikiSchemaCategory {
  id: string
  displayName: string
  singularName?: string
  directory: string
  frontmatterTypes: string[]
  extractionGuidance: string
}

interface MyWikiSchemaFile {
  categories?: MyWikiSchemaCategory[]
}

const defaultMyWikiCategories: MyWikiSchemaCategory[] = [
  {
    id: "people",
    displayName: "People",
    directory: "wiki/people",
    frontmatterTypes: ["person"],
    extractionGuidance: "Real people repeatedly mentioned in journals.",
  },
  {
    id: "organizations",
    displayName: "Organizations",
    directory: "wiki/organizations",
    frontmatterTypes: ["organization", "company", "team"],
    extractionGuidance: "Companies, teams, communities, institutions, and product organizations.",
  },
  {
    id: "projects",
    displayName: "Projects",
    directory: "wiki/projects",
    frontmatterTypes: ["project"],
    extractionGuidance: "Named efforts, products, workstreams, plans, or initiatives.",
  },
  {
    id: "events",
    displayName: "Events",
    directory: "wiki/events",
    frontmatterTypes: ["event"],
    extractionGuidance: "Time-bound meetings, launches, interviews, deadlines, or concrete happenings.",
  },
  {
    id: "topics",
    displayName: "Topics",
    directory: "wiki/topics",
    frontmatterTypes: ["topic"],
    extractionGuidance: "Recurring subjects, questions, interests, or areas of attention.",
  },
  {
    id: "decisions",
    displayName: "Decisions",
    directory: "wiki/decisions",
    frontmatterTypes: ["decision"],
    extractionGuidance: "Explicit choices, trade-offs, commitments, and policy decisions.",
  },
  {
    id: "preferences",
    displayName: "Patterns",
    directory: "wiki/preferences",
    frontmatterTypes: ["preference"],
    extractionGuidance: "Stable user patterns, working style, communication habits, or explicit long-term constraints.",
  },
  {
    id: "follow-ups",
    displayName: "Follow-ups",
    directory: "wiki/follow-ups",
    frontmatterTypes: ["follow-up"],
    extractionGuidance: "Unresolved items that need later action or review.",
  },
  {
    id: "summaries",
    displayName: "Summaries",
    directory: "wiki/summaries",
    frontmatterTypes: ["summary", "overview"],
    extractionGuidance: "Readable summaries across sources.",
  },
  {
    id: "sources",
    displayName: "Sources",
    directory: "wiki/sources",
    frontmatterTypes: ["source", "knowyou-diary"],
    extractionGuidance: "Source-summary pages for original journal files.",
  },
]

function normalizeDirectory(directory: string): string {
  const normalized = directory.trim().replace(/\\/g, "/").replace(/\/+$/, "")
  return normalized || "wiki/misc"
}

async function loadMyWikiCategories(projectPath: string): Promise<MyWikiSchemaCategory[]> {
  try {
    const raw = await fs.readFile(path.join(projectPath, "mywiki.schema.json"), "utf-8")
    const parsed = JSON.parse(raw) as MyWikiSchemaFile
    const categories = (parsed.categories ?? []).filter((category) =>
      category.displayName &&
      category.directory &&
      Array.isArray(category.frontmatterTypes) &&
      category.frontmatterTypes.length > 0
    )
    return categories.length > 0 ? categories : defaultMyWikiCategories
  } catch {
    return defaultMyWikiCategories
  }
}

function buildMyWikiOutputContract(categories: MyWikiSchemaCategory[]): string {
  const rows = categories.map((category) => {
    const directory = normalizeDirectory(category.directory)
    const types = category.frontmatterTypes.map((type) => `\`${type}\``).join(", ")
    return `| ${category.displayName} | \`${directory}\` | ${types} | ${category.extractionGuidance} |`
  })
  const categoryNames = categories.map((category) => category.displayName).join(", ")

  return `${outputContractMarker}

## My Wiki Output Contract

When this project is generated from KnowYou journals, the wiki must use the categories from \`mywiki.schema.json\`:

| Category | Directory | Frontmatter types | Use |
| --- | --- | --- | --- |
${rows.join("\n")}

Hard rules:

- Do not write \`wiki/entities/\`, \`wiki/concepts/\`, or generic ontology folders.
- Do not call user-facing categories "entities" or "concepts".
- Prefer a small number of high-signal pages over many low-confidence pages.
- Every generated page must include clear prose summary, source dates, aliases when useful, and related pages.
- If unsure where something belongs, use the configured categories (${categoryNames}) instead of inventing a new category.
`
}

function parseArgs(argv: string[]): IngestOptions {
  const options: IngestOptions = { projectPath: "" }
  for (let index = 0; index < argv.length; index += 1) {
    const arg = argv[index]
    const next = argv[index + 1]
    if (arg === "--project" && next) {
      options.projectPath = next
      index += 1
    } else if (arg === "--provider" && next) {
      options.provider = next as LlmConfig["provider"]
      index += 1
    } else if (arg === "--model" && next) {
      options.model = next
      index += 1
    } else if (arg === "--max-sources" && next) {
      options.maxSources = Number(next)
      index += 1
    }
  }
  if (!options.projectPath) {
    throw new Error("Missing required --project <path> argument.")
  }
  return options
}

async function writeStatus(projectPath: string, status: IngestStatus): Promise<void> {
  const dir = path.join(projectPath, ".llm-wiki")
  await fs.mkdir(dir, { recursive: true })
  await fs.writeFile(
    path.join(dir, "last-ingest-status.json"),
    `${JSON.stringify(status, null, 2)}\n`,
    "utf-8",
  )
}

async function listSources(projectPath: string, maxSources?: number): Promise<string[]> {
  const sourceDir = path.join(projectPath, "raw", "sources")
  const entries = await fs.readdir(sourceDir, { withFileTypes: true })
  const sources = entries
    .filter((entry) => entry.isFile() && entry.name.toLowerCase().endsWith(".md"))
    .map((entry) => path.join(sourceDir, entry.name).replace(/\\/g, "/"))
    .sort()
  return Number.isFinite(maxSources) && maxSources && maxSources > 0
    ? sources.slice(-maxSources)
    : sources
}

async function ensureMyWikiOutputContract(projectPath: string): Promise<void> {
  const schemaPath = path.join(projectPath, "schema.md")
  const categories = await loadMyWikiCategories(projectPath)
  let schema = ""
  try {
    schema = await fs.readFile(schemaPath, "utf-8")
  } catch {
    schema = "# My Wiki Schema\n"
  }

  const markerIndex = schema.indexOf(outputContractMarker)
  const base = markerIndex >= 0 ? schema.slice(0, markerIndex).trimEnd() : schema.trimEnd()
  await fs.writeFile(schemaPath, `${base}\n\n${buildMyWikiOutputContract(categories)}\n`, "utf-8")
}

function resetStores(projectPath: string, llmConfig: LlmConfig): void {
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
  useWikiStore.setState({
    project: {
      id: projectPath,
      name: "KnowYou My Wiki",
      path: projectPath,
      createdAt: Date.now(),
      purposeText: "",
      fileTree: [],
    },
    llmConfig,
    embeddingConfig: {
      enabled: false,
      endpoint: "",
      apiKey: "",
      model: "",
      maxChunkChars: undefined,
      overlapChunkChars: undefined,
    },
    multimodalConfig: {
      enabled: false,
      useMainLlm: true,
      provider: llmConfig.provider,
      apiKey: "",
      model: llmConfig.model,
      ollamaUrl: "",
      customEndpoint: "",
      apiMode: undefined,
      concurrency: 1,
    },
  } as Partial<ReturnType<typeof useWikiStore.getState>>)
}

function llmConfigFor(options: IngestOptions): LlmConfig {
  return {
    provider: options.provider ?? "codex-cli",
    apiKey: "",
    model: options.model ?? "gpt-5.5",
    ollamaUrl: "",
    customEndpoint: "",
    maxContextSize: 128000,
  }
}

export async function runKnowYouIngest(options: IngestOptions): Promise<IngestStatus> {
  const projectPath = path.resolve(options.projectPath).replace(/\\/g, "/")
  const llmConfig = llmConfigFor(options)
  resetStores(projectPath, llmConfig)
  await ensureMyWikiOutputContract(projectPath)

  const sources = await listSources(projectPath, options.maxSources)
  if (sources.length === 0) {
    throw new Error("No Markdown sources found in raw/sources.")
  }

  const filesWritten = new Set<string>()
  await writeStatus(projectPath, {
    status: "running",
    message: `Ingesting ${sources.length} source file(s).`,
    updatedAt: new Date().toISOString(),
    sourcesProcessed: 0,
    sourcesTotal: sources.length,
    filesWritten: [],
  })

  let processed = 0
  for (const sourcePath of sources) {
    const written = await autoIngest(projectPath, sourcePath, llmConfig)
    written.forEach((filePath) => filesWritten.add(filePath))
    processed += 1
    await writeStatus(projectPath, {
      status: "running",
      message: `Ingested ${processed}/${sources.length} source file(s).`,
      updatedAt: new Date().toISOString(),
      sourcesProcessed: processed,
      sourcesTotal: sources.length,
      filesWritten: [...filesWritten].sort(),
    })
  }

  const status: IngestStatus = {
    status: "succeeded",
    message: `Ingested ${processed} source file(s) into My Wiki.`,
    updatedAt: new Date().toISOString(),
    sourcesProcessed: processed,
    sourcesTotal: sources.length,
    filesWritten: [...filesWritten].sort(),
  }
  await writeStatus(projectPath, status)
  return status
}

export async function runKnowYouIngestCli(argv: string[]): Promise<void> {
  const options = parseArgs(argv)
  try {
    const status = await runKnowYouIngest(options)
    process.stdout.write(`${JSON.stringify(status)}\n`)
  } catch (err) {
    const projectPath = options.projectPath ? path.resolve(options.projectPath) : process.cwd()
    const message = err instanceof Error ? err.message : String(err)
    await writeStatus(projectPath, {
      status: "failed",
      message,
      updatedAt: new Date().toISOString(),
      sourcesProcessed: 0,
      sourcesTotal: 0,
      filesWritten: [],
    }).catch(() => {})
    process.stderr.write(`${message}\n`)
    process.exitCode = 1
  }
}
