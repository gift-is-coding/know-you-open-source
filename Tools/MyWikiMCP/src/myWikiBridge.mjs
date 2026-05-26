import { spawn } from "node:child_process";
import { EventEmitter } from "node:events";
import { homedir } from "node:os";
import path from "node:path";
import { readFile } from "node:fs/promises";

export const DEFAULT_MAX_ITEMS = 8;
export const DEFAULT_CHARACTER_BUDGET = 6000;
export const MAX_BACKGROUND_CHARACTERS = 20000;
export const MAX_CONTEXT_ITEMS = 20;
export const MAX_CHARACTER_BUDGET = 20000;

export function defaultProjectRoot(env = process.env) {
  return env.KNOWYOU_MY_WIKI_PROJECT
    ?? path.join(homedir(), "Library", "Application Support", "KnowYou", "KnowledgeOntology", "KnowYouContext");
}

export function resolveKnowYouCommand(env = process.env) {
  const configured = env.KNOWYOU_APP ?? env.KNOWYOU_BINARY;
  if (!configured || configured.trim() === "") {
    return "KnowYou";
  }

  if (configured.endsWith(".app")) {
    return path.join(configured, "Contents", "MacOS", "KnowYou");
  }

  return configured;
}

export function normalizeContextOptions(options, env = process.env) {
  const background = String(options.background ?? "").trim();
  if (background.length === 0) {
    throw new Error("background is required");
  }
  if (background.length > MAX_BACKGROUND_CHARACTERS) {
    throw new Error(`background must be ${MAX_BACKGROUND_CHARACTERS} characters or fewer`);
  }

  const maxItems = normalizeInteger(options.maxItems, DEFAULT_MAX_ITEMS, 1, MAX_CONTEXT_ITEMS, "maxItems");
  const characterBudget = normalizeInteger(
    options.characterBudget,
    DEFAULT_CHARACTER_BUDGET,
    200,
    MAX_CHARACTER_BUDGET,
    "characterBudget",
  );

  return {
    background,
    projectRoot: path.resolve(String(options.projectRoot ?? defaultProjectRoot(env))),
    maxItems,
    characterBudget,
  };
}

export function buildContextArgs(options) {
  return [
    "--my-wiki-context",
    "--project-root",
    options.projectRoot,
    "--background",
    options.background,
    "--max-items",
    String(options.maxItems),
    "--character-budget",
    String(options.characterBudget),
  ];
}

export async function runKnowYouContext(options, env = process.env, spawnImpl = spawn) {
  const normalized = normalizeContextOptions(options, env);
  const command = resolveKnowYouCommand(env);
  const args = buildContextArgs(normalized);
  const { stdout, stderr, code } = await runProcess(command, args, spawnImpl);

  if (code !== 0) {
    throw new Error(`KnowYou context command failed with code ${code}: ${stderr.trim()}`);
  }

  try {
    return JSON.parse(stdout);
  } catch (error) {
    throw new Error(`KnowYou context command returned invalid JSON: ${error.message}`);
  }
}

export async function readWikiPage({ relativePath, projectRoot }, env = process.env) {
  const resolved = resolvePagePath(relativePath, projectRoot ?? defaultProjectRoot(env));
  const text = await readFile(resolved.absolutePath, "utf8");
  return {
    relativePath: resolved.relativePath,
    absolutePath: resolved.absolutePath,
    text,
  };
}

export function resolvePagePath(relativePath, projectRoot) {
  const requested = String(relativePath ?? "").trim();
  if (requested.length === 0) {
    throw new Error("relativePath is required");
  }
  if (path.isAbsolute(requested)) {
    throw new Error("relativePath must not be absolute");
  }
  if (requested.endsWith(".md") === false) {
    throw new Error("relativePath must point to a markdown file");
  }

  const root = path.resolve(String(projectRoot));
  const absolutePath = path.resolve(root, requested);
  const relative = path.relative(root, absolutePath);
  if (relative.startsWith("..") || path.isAbsolute(relative)) {
    throw new Error("relativePath must stay inside projectRoot");
  }

  return {
    relativePath: relative.replaceAll(path.sep, "/"),
    absolutePath,
  };
}

function normalizeInteger(value, defaultValue, min, max, name) {
  if (value === undefined || value === null || value === "") {
    return defaultValue;
  }

  const parsed = Number(value);
  if (Number.isInteger(parsed) === false || parsed < min || parsed > max) {
    throw new Error(`${name} must be an integer between ${min} and ${max}`);
  }
  return parsed;
}

function runProcess(command, args, spawnImpl) {
  return new Promise((resolve, reject) => {
    const child = spawnImpl(command, args, { stdio: ["ignore", "pipe", "pipe"] });
    let stdout = "";
    let stderr = "";

    if (child instanceof EventEmitter === false) {
      reject(new Error("spawn implementation did not return an EventEmitter"));
      return;
    }

    child.stdout?.setEncoding?.("utf8");
    child.stderr?.setEncoding?.("utf8");
    child.stdout?.on("data", chunk => { stdout += chunk; });
    child.stderr?.on("data", chunk => { stderr += chunk; });
    child.on("error", reject);
    child.on("close", code => {
      resolve({ stdout, stderr, code: code ?? 1 });
    });
  });
}
