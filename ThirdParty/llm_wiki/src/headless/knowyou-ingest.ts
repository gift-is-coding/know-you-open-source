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
  apiKey?: string
  customEndpoint?: string
  ollamaUrl?: string
  apiMode?: LlmConfig["apiMode"]
  maxSources?: number
  manifestPath?: string
  skipIndexed?: boolean
  continueOnError?: boolean
}

interface IngestStatus {
  status: "running" | "succeeded" | "failed"
  message: string
  updatedAt: string
  sourcesProcessed: number
  sourcesTotal: number
  filesWritten: string[]
  failedSources?: IngestFailure[]
}

interface IngestFailure {
  source: string
  message: string
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

const knowYouPromptContextFiles = [
  "schema.md",
  "purpose.md",
  "mywiki.schema.json",
]

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
    } else if (arg === "--api-key" && next) {
      options.apiKey = next
      index += 1
    } else if (arg === "--custom-endpoint" && next) {
      options.customEndpoint = next
      index += 1
    } else if (arg === "--ollama-url" && next) {
      options.ollamaUrl = next
      index += 1
    } else if (arg === "--api-mode" && next) {
      if (next !== "chat_completions" && next !== "anthropic_messages") {
        throw new Error(`Unsupported --api-mode value: ${next}`)
      }
      options.apiMode = next
      index += 1
    } else if (arg === "--max-sources" && next) {
      options.maxSources = Number(next)
      index += 1
    } else if (arg === "--manifest" && next) {
      options.manifestPath = next
      index += 1
    } else if (arg === "--skip-indexed") {
      options.skipIndexed = true
    } else if (arg === "--continue-on-error") {
      options.continueOnError = true
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

async function listSources(projectPath: string, maxSources?: number, skipIndexed = false): Promise<string[]> {
  const sourceDir = path.join(projectPath, "raw", "sources")
  const entries = await fs.readdir(sourceDir, { withFileTypes: true })
  let sources = entries
    .filter((entry) => entry.isFile() && entry.name.toLowerCase().endsWith(".md"))
    .map((entry) => path.join(sourceDir, entry.name).replace(/\\/g, "/"))
    .sort()
  if (skipIndexed) {
    const pending: string[] = []
    for (const sourcePath of sources) {
      if (!(await fileExists(sourceSummaryPath(projectPath, sourcePath)))) {
        pending.push(sourcePath)
      }
    }
    sources = pending
  }
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

async function removeKnowYouPromptContext(projectPath: string): Promise<void> {
  await Promise.all(
    knowYouPromptContextFiles.map((fileName) =>
      fs.rm(path.join(projectPath, fileName), { force: true }),
    ),
  )
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
  const provider = options.provider ?? "codex-cli"
  return {
    provider,
    apiKey: options.apiKey ?? process.env.KNOWYOU_MYWIKI_LLM_API_KEY ?? "",
    model: options.model ?? "gpt-5.5",
    ollamaUrl: options.ollamaUrl ?? "http://localhost:11434",
    customEndpoint: options.customEndpoint ?? "",
    maxContextSize: 128000,
    apiMode: options.apiMode,
  }
}

export async function runKnowYouIngest(options: IngestOptions): Promise<IngestStatus> {
  const projectPath = path.resolve(options.projectPath).replace(/\\/g, "/")
  const llmConfig = llmConfigFor(options)
  resetStores(projectPath, llmConfig)
  await removeKnowYouPromptContext(projectPath)

  const manifestSources = options.manifestPath
    ? await loadManifestSourceMap(projectPath, options.manifestPath)
    : undefined
  const sources: SourceToIngest[] = manifestSources
    ? [...manifestSources.entries()].map(([fullPath, manifestSource]) => ({ fullPath, manifestSource }))
    : (await listSources(projectPath, options.maxSources, options.skipIndexed)).map((fullPath) => ({ fullPath }))
  if (sources.length === 0) {
    throw new Error("No Markdown sources found in raw/sources.")
  }

  const filesWritten = new Set<string>()
  const failedSources: IngestFailure[] = []
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
    try {
      const written = await autoIngest(
        projectPath,
        source.fullPath,
        llmConfig,
        undefined,
        source.manifestSource?.folderContext,
      )
      written.forEach((filePath) => filesWritten.add(filePath))
      processed += 1
    } catch (err) {
      if (!options.continueOnError) {
        throw err
      }
      failedSources.push({
        source: path.basename(source.fullPath),
        message: err instanceof Error ? err.message : String(err),
      })
    }
    await writeStatus(projectPath, {
      status: "running",
      message: failedSources.length > 0
        ? `Ingested ${processed}/${sources.length} source file(s); ${failedSources.length} failed.`
        : `Ingested ${processed}/${sources.length} source file(s).`,
      updatedAt: new Date().toISOString(),
      sourcesProcessed: processed,
      sourcesTotal: sources.length,
      filesWritten: [...filesWritten].sort(),
      failedSources: failedSources.length > 0 ? [...failedSources] : undefined,
    })
  }

  const status: IngestStatus = {
    status: failedSources.length > 0 ? "failed" : "succeeded",
    message: failedSources.length > 0
      ? `Ingested ${processed} source file(s) into My Wiki; ${failedSources.length} failed.`
      : `Ingested ${processed} source file(s) into My Wiki.`,
    updatedAt: new Date().toISOString(),
    sourcesProcessed: processed,
    sourcesTotal: sources.length,
    filesWritten: [...filesWritten].sort(),
    failedSources: failedSources.length > 0 ? [...failedSources] : undefined,
  }
  await writeStatus(projectPath, status)
  return status
}

export async function runKnowYouIngestCli(argv: string[]): Promise<void> {
  const options = parseArgs(argv)
  try {
    const status = await runKnowYouIngest(options)
    process.stdout.write(`${JSON.stringify(status)}\n`)
    if (status.status === "failed") {
      process.exitCode = 1
    }
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
