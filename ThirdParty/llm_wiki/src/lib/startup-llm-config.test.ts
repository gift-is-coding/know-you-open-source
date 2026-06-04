import { describe, expect, it } from "vitest"
import type { LlmConfig } from "@/stores/wiki-store"
import { activePresetForStartup } from "./startup-llm-config"

function config(provider: LlmConfig["provider"]): LlmConfig {
  return {
    provider,
    apiKey: provider === "openai" ? "sk-test" : "",
    model: provider === "knowyou-bridge" ? "diary-engine" : "gpt-4o",
    ollamaUrl: "http://localhost:11434",
    customEndpoint: "",
    maxContextSize: 128000,
  }
}

describe("activePresetForStartup", () => {
  it("does not let an old active preset override the internal KnowYou bridge", () => {
    expect(activePresetForStartup(config("knowyou-bridge"), "openai")).toBeNull()
  })

  it("keeps normal saved presets for user-facing providers", () => {
    expect(activePresetForStartup(config("openai"), "openai")).toBe("openai")
  })

  it("keeps the existing startup behavior when no saved LLM config exists", () => {
    expect(activePresetForStartup(null, "openai")).toBe("openai")
  })
})
