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
  manifestPath?: string
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

interface ManifestSource {
  sourcePath: string
  sourceID?: string
  displayTitle?: string
  folderContext?: string
  sourceKind?: string
  contentHash?: string
}

interface IngestManifest {
  sources?: ManifestSource[]
}

interface SourceToIngest {
  fullPath: string
  manifestSource?: ManifestSource
}

const defaultMyWikiCategories: MyWikiSchemaCategory[] = [
  {
    id: "sources",
    displayName: "Sources",
    directory: "wiki/sources",
    frontmatterTypes: ["source", "knowyou-diary"],
    extractionGuidance: "Source summary pages for KnowYou diary materials.",
  },
  {
    id: "entities",
    displayName: "Entities",
    directory: "wiki/entities",
    frontmatterTypes: ["entity"],
    extractionGuidance: "Concrete people, organizations, tools, products, projects, and other objects; add broad filter tags such as person, project, organization, or other when useful.",
  },
  {
    id: "concepts",
    displayName: "Concepts",
    directory: "wiki/concepts",
    frontmatterTypes: ["concept"],
    extractionGuidance: "Durable topics, working patterns, preferences, decisions, open loops, questions, and long-term context.",
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
- Do not write folders outside the configured directories above, including \`wiki/comparisons/\`, \`wiki/synthesis/\`, or \`wiki/tools/\`.
- Do not call user-facing categories "entities" or "concepts".
- Prefer a small number of high-signal pages over many low-confidence pages.
- Every generated page must include clear prose summary, source dates, aliases when useful, and related pages.
- If unsure where something belongs, use the configured categories (${categoryNames}) instead of inventing a new category.
`
}

function isNativeLlmWikiSchema(categories: MyWikiSchemaCategory[]): boolean {
  const nativeDirectories = new Set(["wiki/sources", "wiki/entities", "wiki/concepts"])
  return categories.length > 0 && categories.every((category) =>
    nativeDirectories.has(normalizeDirectory(category.directory))
  )
}

function buildMyWikiSchemaMarkdown(categories: MyWikiSchemaCategory[]): string {
  const rows = categories.map((category) => {
    const directory = normalizeDirectory(category.directory)
    const types = category.frontmatterTypes.map((type) => `\`${type}\``).join(", ")
    return `| ${category.displayName} | \`${directory}\` | ${types} | ${category.extractionGuidance} |`
  })

  const sections = [
    "# My Wiki Schema",
    "",
    "Generated from `mywiki.schema.json`. Treat this file as a light project schema for KnowYou My Wiki page organization.",
    "",
    "## Categories",
    "",
    "| Category | Directory | Frontmatter types | Guidance |",
    "| --- | --- | --- | --- |",
    ...rows,
    "",
    "## Shared Rules",
    "",
    "- Use llm_wiki's native source, entity, and concept pages for relationship discovery, deduplication, summarization, search ranking, and agent context generation.",
    "- Write pages as direct wiki summaries for the reader.",
    "- Every generated page must cite sources using source filenames or source days.",
    "- Use aliases for alternate spellings and translations; use rename only for the display title.",
    "- Entity pages can use broad filter tags: `person`, `project`, `organization`, or `other`; add more specific tags after that when useful.",
    "- Use cautious wording for uncertain facts instead of turning the page body into an extraction rationale.",
    "- Do not copy secrets, API keys, tokens, passwords, or complete account identifiers.",
    "",
  ]

  if (!isNativeLlmWikiSchema(categories)) {
    sections.push(buildMyWikiOutputContract(categories).trimEnd(), "")
  }

  return sections.join("\n")
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
    } else if (arg === "--manifest" && next) {
      options.manifestPath = next
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
  if (!Number.isFinite(maxSources) || !maxSources || maxSources <= 0) {
    return sources
  }

  const newestFirst = [...sources].reverse()
  const pending: string[] = []
  const alreadyIndexed: string[] = []
  for (const sourcePath of newestFirst) {
    const indexed = await fileExists(sourceSummaryPath(projectPath, sourcePath))
    if (indexed) {
      alreadyIndexed.push(sourcePath)
    } else {
      pending.push(sourcePath)
    }
  }

  return [...pending, ...alreadyIndexed].slice(0, maxSources)
}

function normalizePathForComparison(filePath: string): string {
  return filePath.replace(/\\/g, "/")
}

async function validateManifestSourcePath(
  projectPath: string,
  sourceRootRealPath: string,
  sourcePath: unknown,
  index: number,
): Promise<string> {
  if (typeof sourcePath !== "string" || sourcePath.trim().length === 0) {
    throw new Error(`Manifest source at index ${index} must include a non-empty sourcePath string.`)
  }

  const normalizedInput = sourcePath.replace(/\\/g, "/")
  if (path.isAbsolute(normalizedInput) || path.win32.isAbsolute(normalizedInput)) {
    throw new Error(`Manifest sourcePath must be relative: ${sourcePath}`)
  }
  if (!normalizedInput.startsWith("raw/sources/")) {
    throw new Error(`Manifest sourcePath must start with raw/sources/: ${sourcePath}`)
  }

  const projectRoot = path.resolve(projectPath)
  const sourceRoot = normalizePathForComparison(path.resolve(projectRoot, "raw", "sources"))
  const resolvedPath = normalizePathForComparison(path.resolve(projectRoot, normalizedInput))
  if (resolvedPath !== sourceRoot && !resolvedPath.startsWith(`${sourceRoot}/`)) {
    throw new Error(`Manifest sourcePath must stay inside raw/sources: ${sourcePath}`)
  }

  let sourceRealPath: string
  try {
    sourceRealPath = normalizePathForComparison(await fs.realpath(resolvedPath))
  } catch (err) {
    const message = err instanceof Error ? err.message : String(err)
    throw new Error(`Manifest sourcePath file does not exist or cannot be resolved: ${sourcePath} (${message})`)
  }

  if (sourceRealPath !== sourceRootRealPath && !sourceRealPath.startsWith(`${sourceRootRealPath}/`)) {
    throw new Error(`Manifest sourcePath must stay inside raw/sources: ${sourcePath}`)
  }

  return resolvedPath
}

async function loadManifestSourceMap(projectPath: string, manifestPath: string): Promise<Map<string, ManifestSource>> {
  const resolvedManifestPath = path.isAbsolute(manifestPath)
    ? manifestPath
    : path.resolve(projectPath, manifestPath)
  let parsed: IngestManifest
  try {
    parsed = JSON.parse(await fs.readFile(resolvedManifestPath, "utf-8")) as IngestManifest
  } catch (err) {
    const message = err instanceof Error ? err.message : String(err)
    throw new Error(`Failed to read ingest manifest: ${message}`)
  }

  if (!parsed || typeof parsed !== "object" || Array.isArray(parsed) || !Array.isArray(parsed.sources)) {
    throw new Error("Malformed ingest manifest: sources must be an array.")
  }

  const sourceRootRealPath = normalizePathForComparison(
    await fs.realpath(path.resolve(projectPath, "raw", "sources")),
  )
  const sources = new Map<string, ManifestSource>()
  for (const [index, source] of parsed.sources.entries()) {
    if (!source || typeof source !== "object") {
      throw new Error(`Malformed ingest manifest: source at index ${index} must be an object.`)
    }
    const fullPath = await validateManifestSourcePath(projectPath, sourceRootRealPath, source.sourcePath, index)
    if (sources.has(fullPath)) {
      throw new Error(`Duplicate manifest sourcePath: ${source.sourcePath}`)
    }
    sources.set(fullPath, source)
  }
  return sources
}

function sourceSummaryPath(projectPath: string, sourcePath: string): string {
  const basename = path.basename(sourcePath, path.extname(sourcePath))
  return path.join(projectPath, "wiki", "sources", `${basename}.md`)
}

async function fileExists(filePath: string): Promise<boolean> {
  try {
    await fs.access(filePath)
    return true
  } catch {
    return false
  }
}

async function ensureMyWikiOutputContract(projectPath: string): Promise<void> {
  const schemaPath = path.join(projectPath, "schema.md")
  const categories = await loadMyWikiCategories(projectPath)
  await fs.writeFile(schemaPath, buildMyWikiSchemaMarkdown(categories), "utf-8")
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

  const manifestSources = options.manifestPath
    ? await loadManifestSourceMap(projectPath, options.manifestPath)
    : undefined
  const sources: SourceToIngest[] = manifestSources
    ? [...manifestSources.entries()].map(([fullPath, manifestSource]) => ({ fullPath, manifestSource }))
    : (await listSources(projectPath, options.maxSources)).map((fullPath) => ({ fullPath }))
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
  for (const source of sources) {
    const written = await autoIngest(
      projectPath,
      source.fullPath,
      llmConfig,
      undefined,
      source.manifestSource?.folderContext,
    )
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
