#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
fixture_dir="$repo_root/ThirdParty/llm_wiki/src/headless/fixtures/knowyou-real-diary"
tmp_root="$(mktemp -d "${TMPDIR:-/tmp}/knowyou-mywiki-real-diary.XXXXXX")"
trap 'rm -rf "$tmp_root"' EXIT

project="$tmp_root/KnowYouContext"
mkdir -p "$project/raw/sources"
cp "$fixture_dir"/*.md "$project/raw/sources/"

"$repo_root/scripts/build-mywiki-runner.sh"
runner="$repo_root/build/MyWikiRunner"

cat >"$tmp_root/diary-engine-harness.mjs" <<'JS'
import { spawn } from "node:child_process"
import readline from "node:readline"

const [nodePath, runnerScript, projectPath] = process.argv.slice(2)

function sourceNameFrom(messages) {
  const transcript = messages.map((message) => message.content ?? "").join("\n")
  for (const sourceName of ["2026-06-01.md", "2026-06-02.md", "2026-06-03.md"]) {
    if (transcript.includes(sourceName)) {
      return sourceName
    }
  }
  return "2026-06-01.md"
}

function analysisFor(sourceName) {
  return [
    `Analysis for ${sourceName}.`,
    "Key entities: KnowYou.",
    "Key concepts: bundled MyWikiRunner, Diary Engine reuse, source library inclusion.",
    "Recommendations: create traceable source, entity, and concept pages.",
  ].join("\n")
}

function fileBlocksFor(sourceName) {
  if (sourceName === "2026-06-02.md") {
    return [
      "---FILE: wiki/sources/2026-06-02.md---",
      "---",
      "type: source",
      "title: 2026-06-02",
      "created: 2026-06-04",
      "updated: 2026-06-04",
      "tags: [diary-engine, mywiki]",
      "related: [diary-engine-reuse]",
      "sources: [2026-06-02.md]",
      "---",
      "",
      "# 2026-06-02",
      "",
      "This diary source records testing Diary Engine configuration and the product rule that MyWiki should reuse the same Diary Engine.",
      "---END FILE---",
      "",
      "---FILE: wiki/concepts/diary-engine-reuse.md---",
      "---",
      "type: concept",
      "title: Diary Engine Reuse",
      "created: 2026-06-04",
      "updated: 2026-06-04",
      "tags: [diary-engine, product-architecture]",
      "related: [knowyou]",
      "sources: [2026-06-02.md]",
      "---",
      "",
      "# Diary Engine Reuse",
      "",
      "MyWiki generation should use the same configured Diary Engine instead of asking users for a second API key.",
      "---END FILE---",
    ].join("\n")
  }

  if (sourceName === "2026-06-03.md") {
    return [
      "---FILE: wiki/sources/2026-06-03.md---",
      "---",
      "type: source",
      "title: 2026-06-03",
      "created: 2026-06-04",
      "updated: 2026-06-04",
      "tags: [release, packaging]",
      "related: [bundled-mywiki-runner]",
      "sources: [2026-06-03.md]",
      "---",
      "",
      "# 2026-06-03",
      "",
      "This diary source connects DMG layout work with the bundled MyWikiRunner and the removal of the extra LLM Wiki app.",
      "---END FILE---",
      "",
      "---FILE: wiki/concepts/bundled-mywiki-runner.md---",
      "---",
      "type: concept",
      "title: Bundled MyWikiRunner",
      "created: 2026-06-04",
      "updated: 2026-06-04",
      "tags: [packaging, local-first]",
      "related: [knowyou]",
      "sources: [2026-06-03.md]",
      "---",
      "",
      "# Bundled MyWikiRunner",
      "",
      "A bundled runner keeps Node and the headless llm_wiki pipeline inside KnowYou.app so ordinary users do not need npm.",
      "---END FILE---",
    ].join("\n")
  }

  return [
    "---FILE: wiki/sources/2026-06-01.md---",
    "---",
    "type: source",
    "title: 2026-06-01",
    "created: 2026-06-04",
    "updated: 2026-06-04",
    "tags: [source-library, mywiki]",
    "related: [knowyou, source-library-inclusion]",
    "sources: [2026-06-01.md]",
    "---",
    "",
    "# 2026-06-01",
    "",
    "This diary source describes KnowYou MyWiki source library work and the requirement that ordinary users should not need npm.",
    "---END FILE---",
    "",
    "---FILE: wiki/entities/knowyou.md---",
    "---",
    "type: entity",
    "title: KnowYou",
    "created: 2026-06-04",
    "updated: 2026-06-04",
    "tags: [app, local-first]",
    "related: [bundled-mywiki-runner, diary-engine-reuse]",
    "sources: [2026-06-01.md]",
    "---",
    "",
    "# KnowYou",
    "",
    "KnowYou is the app whose MyWiki feature is being simplified into an internal capability.",
    "---END FILE---",
    "",
    "---FILE: wiki/concepts/source-library-inclusion.md---",
    "---",
    "type: concept",
    "title: Source Library Inclusion",
    "created: 2026-06-04",
    "updated: 2026-06-04",
    "tags: [source-library, ingestion]",
    "related: [knowyou]",
    "sources: [2026-06-01.md]",
    "---",
    "",
    "# Source Library Inclusion",
    "",
    "Update My Wiki should process only included sources from the source library catalog.",
    "---END FILE---",
  ].join("\n")
}

function responseFor(message) {
  const sourceName = sourceNameFrom(message.messages ?? [])
  const transcript = (message.messages ?? []).map((entry) => entry.content ?? "").join("\n")
  if (transcript.includes("generate wiki files") || transcript.includes("---FILE:")) {
    return fileBlocksFor(sourceName)
  }
  return analysisFor(sourceName)
}

const child = spawn(nodePath, [
  runnerScript,
  "--project",
  projectPath,
  "--provider",
  "knowyou-bridge",
  "--max-sources",
  "3",
], {
  stdio: ["pipe", "pipe", "inherit"],
})

const rl = readline.createInterface({ input: child.stdout })
rl.on("line", (line) => {
  let msg
  try {
    msg = JSON.parse(line)
  } catch {
    process.stdout.write(`${line}\n`)
    return
  }

  if (msg.type === "llm.request") {
    child.stdin.write(`${JSON.stringify({
      type: "llm.response",
      id: msg.id,
      content: responseFor(msg),
    })}\n`)
    return
  }

  if (typeof msg.status === "string" && typeof msg.sourcesProcessed === "number") {
    process.stdout.write(`${line}\n`)
    child.stdin.end()
    rl.close()
    return
  }

  process.stdout.write(`${line}\n`)
})

const status = await new Promise((resolve) => {
  child.on("exit", (code) => resolve(code ?? 1))
})
process.exitCode = status
JS

node "$tmp_root/diary-engine-harness.mjs" "$runner/node" "$runner/mywiki-runner.js" "$project"

test -f "$project/wiki/sources/2026-06-01.md"
test -f "$project/wiki/entities/knowyou.md"
test -f "$project/wiki/concepts/bundled-mywiki-runner.md"
rg -n "sources: \\[2026-06-01.md\\]" "$project/wiki/entities/knowyou.md"
rg -n "sources: \\[2026-06-03.md\\]" "$project/wiki/concepts/bundled-mywiki-runner.md"
rg -n '"status": "succeeded"' "$project/.llm-wiki/last-ingest-status.json"
echo "real diary MyWiki ontology verification passed"
