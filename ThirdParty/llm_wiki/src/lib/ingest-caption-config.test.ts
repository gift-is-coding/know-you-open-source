import { describe, expect, it } from "vitest"
import type { LlmConfig, MultimodalConfig } from "@/stores/wiki-store"
import { __test } from "./ingest"

const bridgeLlm: LlmConfig = {
  provider: "knowyou-bridge",
  apiKey: "",
  model: "diary-engine",
  ollamaUrl: "http://localhost:11434",
  customEndpoint: "",
  maxContextSize: 128000,
}

const openAiLlm: LlmConfig = {
  provider: "openai",
  apiKey: "sk-test",
  model: "gpt-4o",
  ollamaUrl: "http://localhost:11434",
  customEndpoint: "",
  maxContextSize: 128000,
}

function multimodal(overrides: Partial<MultimodalConfig> = {}): MultimodalConfig {
  return {
    enabled: true,
    useMainLlm: true,
    provider: "custom",
    apiKey: "",
    model: "",
    ollamaUrl: "http://localhost:11434",
    customEndpoint: "",
    apiMode: "chat_completions",
    concurrency: 4,
    ...overrides,
  }
}

describe("resolveCaptionConfig", () => {
  it("skips image captioning when the main LLM is the text-only KnowYou bridge", () => {
    expect(
      __test.resolveCaptionConfig(multimodal({ useMainLlm: true }), bridgeLlm),
    ).toBeNull()
  })

  it("skips image captioning when the dedicated multimodal provider is the text-only bridge", () => {
    expect(
      __test.resolveCaptionConfig(
        multimodal({
          useMainLlm: false,
          provider: "knowyou-bridge",
          model: "diary-engine",
        }),
        openAiLlm,
      ),
    ).toBeNull()
  })

  it("keeps a real dedicated vision provider for captioning", () => {
    expect(
      __test.resolveCaptionConfig(
        multimodal({
          useMainLlm: false,
          provider: "openai",
          apiKey: "sk-vision",
          model: "gpt-4o-mini",
        }),
        bridgeLlm,
      ),
    ).toMatchObject({
      provider: "openai",
      apiKey: "sk-vision",
      model: "gpt-4o-mini",
    })
  })
})
