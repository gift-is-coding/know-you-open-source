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
    } else if (arg === "--max-sources" && next) {
      options.maxSources = Number(next)
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
  await removeKnowYouPromptContext(projectPath)

  const sources = await listSources(projectPath, options.maxSources, options.skipIndexed)
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
  for (const sourcePath of sources) {
    try {
      const written = await autoIngest(projectPath, sourcePath, llmConfig)
      written.forEach((filePath) => filesWritten.add(filePath))
      processed += 1
    } catch (err) {
      if (!options.continueOnError) {
        throw err
      }
      failedSources.push({
        source: path.basename(sourcePath),
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
