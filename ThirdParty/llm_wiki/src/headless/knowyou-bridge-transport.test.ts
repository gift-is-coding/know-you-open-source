import { PassThrough } from "node:stream"
import { describe, expect, it, vi } from "vitest"
import {
  createKnowYouBridgeTransport,
  streamKnowYouBridge,
} from "./knowyou-bridge-transport"

describe("KnowYou bridge transport", () => {
  it("sends llm.request JSONL and streams the returned content", async () => {
    const writes: string[] = []
    const transport = {
      write: vi.fn((line: string) => writes.push(line)),
      waitForResponse: vi.fn(async (id: string) => ({
        type: "llm.response" as const,
        id,
        content: "Generated ontology",
      })),
    }
    const tokens: string[] = []
    const onDone = vi.fn()

    await streamKnowYouBridge(
      {
        provider: "knowyou-bridge",
        apiKey: "",
        model: "diary-engine",
        ollamaUrl: "",
        customEndpoint: "",
        maxContextSize: 128000,
      },
      [{ role: "user", content: "Diary text" }],
      {
        onToken: (token) => tokens.push(token),
        onDone,
        onError: (error) => {
          throw error
        },
      },
      undefined,
      { temperature: 0.2, max_tokens: 8192, reasoning: { mode: "off" } },
      transport,
    )

    const request = JSON.parse(writes[0]) as Record<string, unknown>
    expect(request).toMatchObject({
      type: "llm.request",
      messages: [{ role: "user", content: "Diary text" }],
      temperature: 0.2,
      max_tokens: 8192,
      reasoning: { mode: "off" },
    })
    expect(typeof request.id).toBe("string")
    expect(request).not.toHaveProperty("apiKey")
    expect(transport.waitForResponse).toHaveBeenCalledWith(request.id, undefined)
    expect(tokens.join("")).toBe("Generated ontology")
    expect(onDone).toHaveBeenCalledOnce()
  })

  it("surfaces llm.error responses without marking the stream done", async () => {
    const onError = vi.fn()
    const onDone = vi.fn()

    await streamKnowYouBridge(
      {
        provider: "knowyou-bridge",
        apiKey: "",
        model: "diary-engine",
        ollamaUrl: "",
        customEndpoint: "",
        maxContextSize: 128000,
      },
      [{ role: "user", content: "Diary text" }],
      {
        onToken: vi.fn(),
        onDone,
        onError,
      },
      undefined,
      undefined,
      {
        write: vi.fn(),
        waitForResponse: vi.fn(async (id: string) => ({
          type: "llm.error" as const,
          id,
          code: "auth_failed",
          message: "Diary Engine authentication failed.",
        })),
      },
    )

    expect(onError).toHaveBeenCalledWith(
      expect.objectContaining({
        message: expect.stringContaining("Diary Engine authentication failed."),
      }),
    )
    expect(onDone).not.toHaveBeenCalled()
  })

  it("matches process JSONL responses by request id", async () => {
    const stdin = new PassThrough()
    const stdout = new PassThrough()
    const transport = createKnowYouBridgeTransport({ stdin, stdout })

    transport.write("{\"type\":\"llm.request\",\"id\":\"req-a\"}\n")
    expect(stdout.read()?.toString()).toBe("{\"type\":\"llm.request\",\"id\":\"req-a\"}\n")

    const first = transport.waitForResponse("req-a")
    const second = transport.waitForResponse("req-b")

    stdin.write("{\"type\":\"llm.response\",\"id\":\"req-b\",\"content\":\"second\"}\n")
    stdin.write("{\"type\":\"llm.response\",\"id\":\"req-a\",\"content\":\"first\"}\n")

    await expect(first).resolves.toMatchObject({ id: "req-a", content: "first" })
    await expect(second).resolves.toMatchObject({ id: "req-b", content: "second" })
  })
})
