import fs from "node:fs/promises"
import os from "node:os"
import path from "node:path"
import { spawn } from "node:child_process"

export class Resource {
  rid: number

  constructor(rid: number) {
    this.rid = rid
  }
}

function codexCandidates(): string[] {
  const fromPath = (process.env.PATH ?? "")
    .split(path.delimiter)
    .filter(Boolean)
    .map((dir) => path.join(dir, "codex"))

  return [
    ...fromPath,
    "/Applications/Codex.app/Contents/Resources/codex",
  ]
}

async function findCodex(): Promise<string | null> {
  for (const candidate of codexCandidates()) {
    try {
      await fs.access(candidate)
      return candidate
    } catch {
      // Try the next candidate.
    }
  }
  return null
}

function runProcess(
  executable: string,
  args: string[],
  input: string | undefined,
  timeoutMs: number,
): Promise<{ stdout: string; stderr: string; code: number | null }> {
  return new Promise((resolve, reject) => {
    const child = spawn(executable, args, {
      stdio: ["pipe", "pipe", "pipe"],
      env: process.env,
    })

    let stdout = ""
    let stderr = ""
    const timer = setTimeout(() => {
      child.kill("SIGTERM")
      reject(new Error(`Process timed out after ${Math.round(timeoutMs / 1000)}s`))
    }, timeoutMs)

    child.stdout.setEncoding("utf-8")
    child.stderr.setEncoding("utf-8")
    child.stdout.on("data", (chunk) => {
      stdout += String(chunk)
    })
    child.stderr.on("data", (chunk) => {
      stderr += String(chunk)
    })
    child.on("error", (err) => {
      clearTimeout(timer)
      reject(err)
    })
    child.on("close", (code) => {
      clearTimeout(timer)
      resolve({ stdout, stderr, code })
    })

    if (input !== undefined) child.stdin.write(input)
    child.stdin.end()
  })
}

async function codexCliComplete(args: Record<string, unknown>): Promise<string> {
  const codex = await findCodex()
  if (!codex) {
    throw new Error("Codex CLI not found.")
  }

  const prompt = typeof args.prompt === "string" ? args.prompt : ""
  const model = typeof args.model === "string" ? args.model.trim() : ""
  const tmpDir = await fs.mkdtemp(path.join(os.tmpdir(), "llmwiki-codex-"))
  const outputPath = path.join(tmpDir, "last-message.txt")

  const codexArgs = [
    "exec",
    "--skip-git-repo-check",
    "--ephemeral",
    "--sandbox",
    "read-only",
    "--output-last-message",
    outputPath,
  ]
  if (model.length > 0) codexArgs.push("--model", model)
  codexArgs.push("-")

  try {
    const result = await runProcess(codex, codexArgs, prompt, 30 * 60 * 1000)
    if (result.code !== 0) {
      const detail = [result.stderr.trim(), result.stdout.trim()].filter(Boolean).join("\n")
      throw new Error(detail || `Codex CLI exited with code ${result.code}`)
    }
    return fs.readFile(outputPath, "utf-8")
  } finally {
    await fs.rm(tmpDir, { recursive: true, force: true }).catch(() => {})
  }
}

export async function invoke<T>(command: string, args?: Record<string, unknown>): Promise<T> {
  switch (command) {
    case "codex_cli_detect": {
      const codex = await findCodex()
      if (!codex) return "Codex CLI not found" as T
      const result = await runProcess(codex, ["--version"], undefined, 3000)
      return (result.stdout.trim() || result.stderr.trim() || codex) as T
    }
    case "codex_cli_complete":
      return codexCliComplete(args ?? {}) as T
    case "extract_and_save_pdf_images_cmd":
    case "extract_and_save_office_images_cmd":
      return [] as T
    case "vector_upsert_chunks":
    case "vector_delete_page":
    case "vector_drop_legacy":
      return undefined as T
    case "vector_search_chunks":
      return [] as T
    case "vector_count_chunks":
    case "vector_legacy_row_count":
      return 0 as T
    default:
      throw new Error(`Unsupported headless Tauri command: ${command}`)
  }
}

export function convertFileSrc(filePath: string): string {
  return filePath
}
