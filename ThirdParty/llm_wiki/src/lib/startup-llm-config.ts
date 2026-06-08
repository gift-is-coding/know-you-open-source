import type { LlmConfig } from "@/stores/wiki-store"

export function activePresetForStartup(
  savedConfig: LlmConfig | null,
  savedActivePreset: string | null,
): string | null {
  if (!savedActivePreset) return null
  if (savedConfig?.provider === "knowyou-bridge") return null
  return savedActivePreset
}
