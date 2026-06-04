import type { LlmConfig, MultimodalConfig } from "@/stores/wiki-store"
import type { SettingsDraft } from "./settings-types"

export function buildSavedLlmConfig(
  current: LlmConfig,
  draft: SettingsDraft,
): LlmConfig {
  if (current.provider === "knowyou-bridge") {
    return current
  }

  return {
    provider: draft.provider,
    apiKey: draft.apiKey,
    model: draft.model,
    ollamaUrl: draft.ollamaUrl,
    customEndpoint: draft.customEndpoint,
    maxContextSize: draft.maxContextSize,
    apiMode: draft.provider === "custom" ? draft.apiMode : undefined,
    reasoning: draft.reasoning,
  }
}

export function buildSavedMultimodalConfig(
  current: MultimodalConfig,
  draft: SettingsDraft,
): MultimodalConfig {
  // Clamp at save time so a hand-edited persisted store with a
  // ridiculous concurrency value does not blow up the captioning
  // pipeline. Going wider than this usually just queues behind the
  // server's batch slot anyway.
  const concurrency = Math.max(1, Math.min(16, draft.multimodalConcurrency || 4))

  if (
    current.provider === "knowyou-bridge" &&
    (draft.multimodalUseMainLlm || isMaskedBridgeMultimodalDraft(current, draft))
  ) {
    return {
      ...current,
      enabled: draft.multimodalEnabled,
      useMainLlm: draft.multimodalUseMainLlm,
      concurrency,
    }
  }

  return {
    enabled: draft.multimodalEnabled,
    useMainLlm: draft.multimodalUseMainLlm,
    provider: draft.multimodalProvider,
    apiKey: draft.multimodalApiKey,
    model: draft.multimodalModel,
    ollamaUrl: draft.multimodalOllamaUrl,
    customEndpoint: draft.multimodalCustomEndpoint,
    apiMode: draft.multimodalProvider === "custom" ? draft.multimodalApiMode : undefined,
    concurrency,
  }
}

function isMaskedBridgeMultimodalDraft(
  current: MultimodalConfig,
  draft: SettingsDraft,
): boolean {
  return draft.multimodalProvider === "custom" &&
    draft.multimodalApiKey.trim().length === 0 &&
    draft.multimodalCustomEndpoint.trim().length === 0 &&
    draft.multimodalModel === current.model
}
