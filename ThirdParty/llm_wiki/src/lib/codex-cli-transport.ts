/**
 * Codex CLI subprocess transport.
 *
 * Rust-side counterpart: src-tauri/src/commands/codex_cli.rs. The Rust
 * command spawns `codex exec --skip-git-repo-check --ephemeral` and asks
 * it to write the final assistant message to a temp file. Codex CLI is
 * not treated as an autonomous coding agent here; LLM Wiki only uses it
 * as a local text model authenticated by the user's existing ~/.codex
 * login.
 */

import { invoke } from "@tauri-apps/api/core"
import type { LlmConfig } from "@/stores/wiki-store"
import type { ChatMessage, ContentBlock, RequestOverrides } from "./llm-providers"
import type { StreamCallbacks } from "./llm-client"

function stringifyContent(content: string | ContentBlock[]): string {
  if (typeof content === "string") return content
  return content.map((block) => (block.type === "text" ? block.text : "[image omitted]")).join("")
}

function buildCodexPrompt(messages: ChatMessage[]): string {
  const system = messages
    .filter((m) => m.role === "system")
    .map((m) => stringifyContent(m.content).trim())
    .filter(Boolean)
    .join("\n\n")

  const turns = messages
    .filter((m) => m.role !== "system")
    .map((m) => `${m.role.toUpperCase()}:\n${stringifyContent(m.content).trim()}`)
    .join("\n\n")

  return [system ? `SYSTEM:\n${system}` : "", turns].filter(Boolean).join("\n\n")
}

export async function streamCodexCli(
  config: LlmConfig,
  messages: ChatMessage[],
  callbacks: StreamCallbacks,
  signal?: AbortSignal,
  overrides?: RequestOverrides,
): Promise<void> {
  const { onToken, onDone, onError } = callbacks

  if (import.meta.env?.DEV && overrides) {
    for (const key of ["temperature", "top_p", "top_k", "max_tokens", "stop"] as const) {
      if (overrides[key] !== undefined) {
        // eslint-disable-next-line no-console
        console.warn(`[codex-cli] ignoring unsupported override "${key}": CLI has no equivalent flag`)
      }
    }
  }

  if (signal?.aborted) {
    onDone()
    return
  }

  const abortPromise = new Promise<"aborted">((resolve) => {
    signal?.addEventListener("abort", () => resolve("aborted"), { once: true })
  })

  try {
    const prompt = buildCodexPrompt(messages)
    const resultPromise = invoke<string>("codex_cli_complete", {
      model: config.model,
      prompt,
    })
    const result = await Promise.race([resultPromise, abortPromise])
    if (result === "aborted") {
      onDone()
      return
    }
    if (result.trim().length > 0) onToken(result)
    onDone()
  } catch (err) {
    const message = err instanceof Error ? err.message : String(err)
    if (/not found|No such file|executable file not found/i.test(message)) {
      onError(new Error(
        "Codex CLI not found. Install or open the Codex desktop app so the local `codex` binary is available.",
      ))
    } else {
      onError(err instanceof Error ? err : new Error(message))
    }
  }
}
