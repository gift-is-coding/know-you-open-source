import { describe, expect, it } from "vitest"
import type { LlmConfig, MultimodalConfig } from "@/stores/wiki-store"
import type { SettingsDraft } from "./settings-types"
import {
  buildSavedLlmConfig,
  buildSavedMultimodalConfig,
} from "./settings-save-config"

function draft(overrides: Partial<SettingsDraft> = {}): SettingsDraft {
  return {
    provider: "custom",
    apiKey: "",
    model: "",
    ollamaUrl: "http://localhost:11434",
    customEndpoint: "",
    maxContextSize: 128000,
    apiMode: "chat_completions",
    reasoning: { mode: "auto" },
    embeddingEnabled: false,
    embeddingEndpoint: "",
    embeddingApiKey: "",
    embeddingModel: "",
    embeddingMaxChunkChars: undefined,
    embeddingOverlapChunkChars: undefined,
    multimodalEnabled: false,
    multimodalUseMainLlm: true,
    multimodalProvider: "custom",
    multimodalApiKey: "",
    multimodalModel: "",
    multimodalOllamaUrl: "http://localhost:11434",
    multimodalCustomEndpoint: "",
    multimodalApiMode: "chat_completions",
    multimodalConcurrency: 4,
    outputLanguage: "auto",
    maxHistoryMessages: 20,
    proxyEnabled: false,
    proxyUrl: "",
    proxyBypassLocal: true,
    uiLanguage: "en",
    ...overrides,
  }
}

describe("settings save config", () => {
  it("preserves the internal KnowYou bridge LLM provider on unrelated settings saves", () => {
    const current: LlmConfig = {
      provider: "knowyou-bridge",
      apiKey: "",
      model: "diary-engine",
      ollamaUrl: "http://localhost:11434",
      customEndpoint: "",
      maxContextSize: 128000,
      reasoning: { mode: "auto" },
    }

    const saved = buildSavedLlmConfig(current, draft({
      provider: "custom",
      model: "accidental-ui-default",
      customEndpoint: "",
    }))

    expect(saved).toEqual(current)
  })

  it("still saves normal user-facing LLM provider draft changes", () => {
    const current: LlmConfig = {
      provider: "openai",
      apiKey: "sk-old",
      model: "gpt-4o",
      ollamaUrl: "http://localhost:11434",
      customEndpoint: "",
      maxContextSize: 8192,
    }

    expect(buildSavedLlmConfig(current, draft({
      provider: "custom",
      apiKey: "sk-new",
      model: "deepseek-chat",
      customEndpoint: "https://api.deepseek.com/v1",
      maxContextSize: 64000,
      apiMode: "chat_completions",
      reasoning: { mode: "off" },
    }))).toMatchObject({
      provider: "custom",
      apiKey: "sk-new",
      model: "deepseek-chat",
      customEndpoint: "https://api.deepseek.com/v1",
      apiMode: "chat_completions",
      reasoning: { mode: "off" },
    })
  })

  it("preserves internal KnowYou bridge multimodal provider fields", () => {
    const current: MultimodalConfig = {
      enabled: false,
      useMainLlm: false,
      provider: "knowyou-bridge",
      apiKey: "",
      model: "diary-engine",
      ollamaUrl: "http://localhost:11434",
      customEndpoint: "",
      apiMode: undefined,
      concurrency: 2,
    }

    const saved = buildSavedMultimodalConfig(current, draft({
      multimodalEnabled: true,
      multimodalUseMainLlm: true,
      multimodalProvider: "custom",
      multimodalApiKey: "sk-should-not-save",
      multimodalModel: "draft-model",
      multimodalCustomEndpoint: "https://example.test/v1",
      multimodalConcurrency: 99,
    }))

    expect(saved).toMatchObject({
      enabled: true,
      useMainLlm: true,
      provider: "knowyou-bridge",
      apiKey: "",
      model: "diary-engine",
      customEndpoint: "",
      concurrency: 16,
    })
  })

  it("allows a dedicated multimodal provider to replace the internal bridge", () => {
    const current: MultimodalConfig = {
      enabled: true,
      useMainLlm: true,
      provider: "knowyou-bridge",
      apiKey: "",
      model: "diary-engine",
      ollamaUrl: "http://localhost:11434",
      customEndpoint: "",
      apiMode: undefined,
      concurrency: 4,
    }

    const saved = buildSavedMultimodalConfig(current, draft({
      multimodalEnabled: true,
      multimodalUseMainLlm: false,
      multimodalProvider: "openai",
      multimodalApiKey: "sk-vision",
      multimodalModel: "gpt-4o-mini",
      multimodalConcurrency: 2,
    }))

    expect(saved).toMatchObject({
      enabled: true,
      useMainLlm: false,
      provider: "openai",
      apiKey: "sk-vision",
      model: "gpt-4o-mini",
      concurrency: 2,
    })
  })

  it("preserves a dedicated internal bridge multimodal provider on unrelated settings saves", () => {
    const current: MultimodalConfig = {
      enabled: true,
      useMainLlm: false,
      provider: "knowyou-bridge",
      apiKey: "",
      model: "diary-engine",
      ollamaUrl: "http://localhost:11434",
      customEndpoint: "",
      apiMode: undefined,
      concurrency: 3,
    }

    const saved = buildSavedMultimodalConfig(current, draft({
      multimodalEnabled: true,
      multimodalUseMainLlm: false,
      multimodalProvider: "custom",
      multimodalApiKey: "",
      multimodalModel: "diary-engine",
      multimodalCustomEndpoint: "",
      multimodalConcurrency: 3,
    }))

    expect(saved).toEqual(current)
  })
})
