#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source_dir="${KNOWYOU_REAL_DIARY_SOURCE_DIR:-$repo_root/ThirdParty/llm_wiki/src/headless/fixtures/knowyou-real-diary}"
tmp_root="$(mktemp -d "${TMPDIR:-/tmp}/knowyou-mywiki-real-diary.XXXXXX")"
trap 'rm -rf "$tmp_root"' EXIT

project="$tmp_root/KnowYouContext"
mkdir -p "$project/raw/sources"

source_files=()
while IFS= read -r source_file; do
  source_files+=("$source_file")
done < <(find "$source_dir" -maxdepth 1 -type f -name '2026-*.md' | sort | tail -n 3)

if [[ "${#source_files[@]}" -lt 3 ]]; then
  echo "Expected at least 3 diary markdown files in: $source_dir" >&2
  exit 1
fi

source_names=()
for source_file in "${source_files[@]}"; do
  cp "$source_file" "$project/raw/sources/"
  source_names+=("$(basename "$source_file")")
done

"$repo_root/scripts/build-mywiki-runner.sh"
runner="$repo_root/build/MyWikiRunner"

cat >"$tmp_root/diary-engine-harness.mjs" <<'JS'
import { spawn } from "node:child_process"
import readline from "node:readline"

const [nodePath, runnerScript, projectPath, ...sourceNames] = process.argv.slice(2)

function sourceNameFrom(messages) {
  const transcript = messages.map((message) => message.content ?? "").join("\n")
  for (const sourceName of sourceNames) {
    if (transcript.includes(sourceName)) {
      return sourceName
    }
  }
  return sourceNames[0] ?? "2026-06-01.md"
}

function analysisFor(sourceName) {
  return [
    `Analysis for ${sourceName}.`,
    "Key entities: KnowYou.",
    "Key concepts: bundled MyWikiRunner, Diary Engine reuse, source library inclusion, real diary verification.",
    "Recommendations: create traceable source, entity, and concept pages.",
  ].join("\n")
}

function fileBlocksFor(sourceName) {
  const title = sourceName.replace(/\.md$/, "")
  return [
    `---FILE: wiki/sources/${sourceName}---`,
    "---",
    "type: source",
    `title: ${title}`,
    "created: 2026-06-08",
    "updated: 2026-06-08",
    "tags: [real-diary, mywiki]",
    "related: [knowyou, diary-engine-mywiki-verification]",
    `sources: [${sourceName}]`,
    "---",
    "",
    `# ${title}`,
    "",
    "This real Diary source is processed through the bundled MyWiki runner and Diary Engine bridge.",
    "---END FILE---",
    "",
    "---FILE: wiki/entities/knowyou.md---",
    "---",
    "type: entity",
    "title: KnowYou",
    "created: 2026-06-08",
    "updated: 2026-06-08",
    "tags: [app, local-first]",
    "related: [diary-engine-mywiki-verification]",
    `sources: [${sourceName}]`,
    "---",
    "",
    "# KnowYou",
    "",
    "KnowYou owns the MyWiki feature and runs ontology generation through its bundled runner.",
    "---END FILE---",
    "",
    "---FILE: wiki/concepts/diary-engine-mywiki-verification.md---",
    "---",
    "type: concept",
    "title: Diary Engine MyWiki Verification",
    "created: 2026-06-08",
    "updated: 2026-06-08",
    "tags: [diary-engine, mywiki, packaging]",
    "related: [knowyou]",
    `sources: [${sourceName}]`,
    "---",
    "",
    "# Diary Engine MyWiki Verification",
    "",
    "MyWiki generation should reuse KnowYou's configured Diary Engine bridge while the runtime runner remains bundled inside the app.",
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

node "$tmp_root/diary-engine-harness.mjs" "$runner/node" "$runner/mywiki-runner.js" "$project" "${source_names[@]}"

for source_name in "${source_names[@]}"; do
  test -f "$project/wiki/sources/$source_name"
  rg -n "sources: \\[$source_name\\]" "$project/wiki/sources/$source_name"
done
test -f "$project/wiki/entities/knowyou.md"
test -f "$project/wiki/concepts/diary-engine-mywiki-verification.md"
rg -n "KnowYou" "$project/wiki/entities/knowyou.md"
rg -n "Diary Engine MyWiki Verification" "$project/wiki/concepts/diary-engine-mywiki-verification.md"
rg -n '"status": "succeeded"' "$project/.llm-wiki/last-ingest-status.json"
rg -n '"sourcesProcessed": 3' "$project/.llm-wiki/last-ingest-status.json"
echo "real diary MyWiki ontology verification passed for: ${source_names[*]}"
