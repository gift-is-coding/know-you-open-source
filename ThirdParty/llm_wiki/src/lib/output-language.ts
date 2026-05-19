import { useWikiStore } from "@/stores/wiki-store"
import { detectLanguage } from "./detect-language"
import { getLanguagePromptName } from "./language-metadata"

/**
 * Get the effective output language for LLM content generation.
 *
 * If user has explicitly set an outputLanguage, use it.
 * Otherwise (auto), fall back to detecting the language from the given text.
 */
export function getOutputLanguage(fallbackText: string = ""): string {
  const configured = useWikiStore.getState().outputLanguage
  if (configured && configured !== "auto") {
    return configured
  }
  return detectLanguage(fallbackText || "English")
}

/**
 * Build a strong language directive to inject into system prompts.
 */
export function buildLanguageDirective(fallbackText: string = ""): string {
  const configured = useWikiStore.getState().outputLanguage
  const isExplicitLanguage = configured && configured !== "auto"
  const lang = isExplicitLanguage ? configured : detectLanguage(fallbackText || "English")
  const promptLang = getLanguagePromptName(lang)
  if (!isExplicitLanguage) {
    return [
      `## SOURCE LANGUAGE MODE: ${promptLang}`,
      "",
      `Write generated prose in the same primary language as the source material (${promptLang}).`,
      "Preserve proper nouns exactly as they appear in the source, including examples like Adam, Token Hub, AI OS, Codex, Claude, OpenAI, Lenovo, product names, project names, acronyms, model names, and file names.",
      "Use translations or explanations as aliases, tags, or short parenthetical clarifications only when useful.",
      "Do not rename page titles by translating proper nouns; keep the source spelling as the canonical title unless the source itself gives a better canonical name.",
      "If the source is multilingual, use the language of the relevant evidence while keeping source-specific terms intact.",
    ].join("\n")
  }
  return [
    `## ⚠️ MANDATORY OUTPUT LANGUAGE: ${promptLang}`,
    "",
    `You MUST write your entire response (including wiki page titles, content, descriptions, summaries, and any generated text) in **${promptLang}**.`,
    `The source material or wiki content may be in a different language, but this is IRRELEVANT to your output language.`,
    `Ignore the language of any source content. Generate everything in ${promptLang} only.`,
    `Proper nouns should use standard ${promptLang} transliteration when appropriate.`,
    `DO NOT use any other language. This overrides all other instructions.`,
  ].join("\n")
}

/**
 * Short reminder version — for placing right before user's current message.
 */
export function buildLanguageReminder(fallbackText: string = ""): string {
  const lang = getOutputLanguage(fallbackText)
  return `REMINDER: All output must be in ${getLanguagePromptName(lang)}. Do not use any other language.`
}
