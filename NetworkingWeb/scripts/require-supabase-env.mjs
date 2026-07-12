import { existsSync, readFileSync } from "node:fs";

const mode = process.argv[2];
const productionProjectHost = "jevgtiamxlkucjqpbekn.supabase.co";

if (mode !== "production" && mode !== "development") {
  fail("usage: require-supabase-env.mjs <production|development>");
}

const fileEnv = process.env.NETWORKING_IGNORE_ENV_LOCAL !== "1" && existsSync(".env.local")
  ? parseEnv(readFileSync(".env.local", "utf8"))
  : {};
const value = (name) => process.env[name] ?? fileEnv[name];
const supabaseURL = value("NEXT_PUBLIC_SUPABASE_URL");
const publishableKey = value("NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY") ?? value("NEXT_PUBLIC_SUPABASE_ANON_KEY");

if (!supabaseURL) fail("NEXT_PUBLIC_SUPABASE_URL is required");
if (!publishableKey) fail("NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY is required");

let host;
try {
  host = new URL(supabaseURL).host;
} catch {
  fail("NEXT_PUBLIC_SUPABASE_URL must be a valid URL");
}

if (mode === "development" && host === productionProjectHost && process.env.ALLOW_PRODUCTION_SUPABASE_FOR_LOCAL_DEV !== "1") {
  fail("refusing production Supabase for local development; configure a dev project or set ALLOW_PRODUCTION_SUPABASE_FOR_LOCAL_DEV=1 for an explicit one-off override");
}

process.stdout.write(`Supabase ${mode} preflight passed for ${host}\n`);

function parseEnv(source) {
  return Object.fromEntries(source.split(/\r?\n/).flatMap((line) => {
    const trimmed = line.trim();
    if (!trimmed || trimmed.startsWith("#")) return [];
    const separator = trimmed.indexOf("=");
    if (separator < 1) return [];
    const key = trimmed.slice(0, separator).trim();
    const raw = trimmed.slice(separator + 1).trim();
    return [[key, raw.replace(/^(['"])(.*)\1$/, "$2")]];
  }));
}

function fail(message) {
  process.stderr.write(`Networking Supabase preflight failed: ${message}\n`);
  process.exit(1);
}
