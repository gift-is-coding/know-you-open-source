import type { LlmConfig } from "@/stores/wiki-store"
import type { ChatMessage, ContentBlock, RequestOverrides } from "@/lib/llm-providers"
import type { StreamCallbacks } from "@/lib/llm-client"

export interface BridgeResponse {
  type: "llm.response" | "llm.error"
  id: string
  content?: string
  code?: string
  message?: string
}

export interface KnowYouBridgeTransport {
  write(line: string): void
  waitForResponse(id: string, signal?: AbortSignal): Promise<BridgeResponse>
}

export interface KnowYouBridgeStreams {
  stdin: NodeJS.ReadableStream
  stdout: NodeJS.WritableStream
}

interface PendingResponse {
  resolve: (response: BridgeResponse) => void
  reject: (error: Error) => void
}

let sequence = 0
let sharedProcessTransport: KnowYouBridgeTransport | undefined

function nextRequestId(): string {
  sequence += 1
  return `req-${sequence}`
}

function stringifyContent(content: string | ContentBlock[]): string {
  if (typeof content === "string") return content
  return content
    .map((block) => (block.type === "text" ? block.text : "[image omitted]"))
    .join("")
}

function bridgeMessages(messages: ChatMessage[]): Array<{ role: ChatMessage["role"]; content: string }> {
  return messages.map((message) => ({
    role: message.role,
    content: stringifyContent(message.content),
  }))
}

function abortError(): Error {
  const err = new Error("KnowYou bridge request was cancelled.")
  err.name = "AbortError"
  return err
}

function coerceError(err: unknown): Error {
  return err instanceof Error ? err : new Error(String(err))
}

function parseBridgeResponse(line: string): BridgeResponse | undefined {
  const trimmed = line.trim()
  if (!trimmed) return undefined

  const parsed = JSON.parse(trimmed) as Record<string, unknown>
  if (
    (parsed.type !== "llm.response" && parsed.type !== "llm.error") ||
    typeof parsed.id !== "string"
  ) {
    return undefined
  }

  return {
    type: parsed.type,
    id: parsed.id,
    content: typeof parsed.content === "string" ? parsed.content : undefined,
    code: typeof parsed.code === "string" ? parsed.code : undefined,
    message: typeof parsed.message === "string" ? parsed.message : undefined,
  }
}

export function createKnowYouBridgeTransport(streams: KnowYouBridgeStreams): KnowYouBridgeTransport {
  const pending = new Map<string, PendingResponse>()
  const received = new Map<string, BridgeResponse>()
  let lineBuffer = ""
  let listening = false

  const rejectAll = (error: Error) => {
    for (const entry of pending.values()) {
      entry.reject(error)
    }
    pending.clear()
  }

  const handleLine = (line: string) => {
    let response: BridgeResponse | undefined
    try {
      response = parseBridgeResponse(line)
    } catch (err) {
      rejectAll(new Error(`Malformed KnowYou bridge response: ${coerceError(err).message}`))
      return
    }

    if (!response) return

    const entry = pending.get(response.id)
    if (!entry) {
      received.set(response.id, response)
      return
    }
    pending.delete(response.id)
    entry.resolve(response)
  }

  const onData = (chunk: string | Buffer) => {
    lineBuffer += typeof chunk === "string" ? chunk : chunk.toString("utf-8")
    const lines = lineBuffer.split("\n")
    lineBuffer = lines.pop() ?? ""
    for (const line of lines) {
      handleLine(line)
    }
  }

  const ensureListening = () => {
    if (listening) return
    listening = true
    streams.stdin.on("data", onData)
    streams.stdin.on("error", (err) => {
      rejectAll(coerceError(err))
    })
    streams.stdin.on("end", () => {
      rejectAll(new Error("KnowYou bridge stdin ended before a response arrived."))
    })
  }

  return {
    write(line: string) {
      streams.stdout.write(line)
    },

    waitForResponse(id: string, signal?: AbortSignal): Promise<BridgeResponse> {
      ensureListening()

      const existing = received.get(id)
      if (existing) {
        received.delete(id)
        return Promise.resolve(existing)
      }

      if (signal?.aborted) {
        return Promise.reject(abortError())
      }

      return new Promise((resolve, reject) => {
        const cleanup = () => {
          pending.delete(id)
          signal?.removeEventListener("abort", onAbort)
        }
        const onAbort = () => {
          cleanup()
          reject(abortError())
        }
        const entry: PendingResponse = {
          resolve: (response) => {
            cleanup()
            resolve(response)
          },
          reject: (error) => {
            cleanup()
            reject(error)
          },
        }
        pending.set(id, entry)
        signal?.addEventListener("abort", onAbort, { once: true })
      })
    },
  }
}

export function processBridgeTransport(): KnowYouBridgeTransport {
  if (sharedProcessTransport) return sharedProcessTransport
  if (
    typeof process === "undefined" ||
    !process.stdin ||
    !process.stdout
  ) {
    throw new Error("KnowYou bridge transport requires process stdin/stdout.")
  }
  sharedProcessTransport = createKnowYouBridgeTransport({
    stdin: process.stdin,
    stdout: process.stdout,
  })
  return sharedProcessTransport
}

export async function streamKnowYouBridge(
  _config: LlmConfig,
  messages: ChatMessage[],
  callbacks: StreamCallbacks,
  signal?: AbortSignal,
  requestOverrides?: RequestOverrides,
  transport?: KnowYouBridgeTransport,
): Promise<void> {
  if (signal?.aborted) {
    callbacks.onDone()
    return
  }

  const id = nextRequestId()
  const request = {
    type: "llm.request",
    id,
    messages: bridgeMessages(messages),
    temperature: requestOverrides?.temperature,
    max_tokens: requestOverrides?.max_tokens,
    reasoning: requestOverrides?.reasoning,
  }

  try {
    const activeTransport = transport ?? processBridgeTransport()
    activeTransport.write(`${JSON.stringify(request)}\n`)
    const response = await activeTransport.waitForResponse(id, signal)
    if (response.type === "llm.error") {
      callbacks.onError(
        new Error(response.message ?? response.code ?? "KnowYou Diary Engine failed."),
      )
      return
    }
    callbacks.onToken(response.content ?? "")
    callbacks.onDone()
  } catch (err) {
    if (signal?.aborted || (err instanceof Error && err.name === "AbortError")) {
      callbacks.onDone()
      return
    }
    callbacks.onError(coerceError(err))
  }
}
