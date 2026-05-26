import assert from "node:assert/strict";
import { EventEmitter } from "node:events";
import test from "node:test";
import {
  buildContextArgs,
  defaultProjectRoot,
  normalizeContextOptions,
  resolveKnowYouCommand,
  resolvePagePath,
  runKnowYouContext,
} from "../src/myWikiBridge.mjs";

test("normalizes background context options with bounded defaults", () => {
  const options = normalizeContextOptions(
    { background: "Need AIDC HVDC context" },
    { KNOWYOU_MY_WIKI_PROJECT: "/tmp/wiki" },
  );

  assert.equal(options.background, "Need AIDC HVDC context");
  assert.equal(options.projectRoot, "/tmp/wiki");
  assert.equal(options.maxItems, 8);
  assert.equal(options.characterBudget, 6000);
});

test("rejects invalid numeric budgets", () => {
  assert.throws(
    () => normalizeContextOptions({ background: "x", maxItems: 100 }),
    /maxItems must be an integer/,
  );
  assert.throws(
    () => normalizeContextOptions({ background: "x", characterBudget: 20 }),
    /characterBudget must be an integer/,
  );
});

test("builds KnowYou CLI arguments with background input", () => {
  const args = buildContextArgs({
    projectRoot: "/tmp/wiki",
    background: "A paragraph from an agent",
    maxItems: 3,
    characterBudget: 1200,
  });

  assert.deepEqual(args, [
    "--my-wiki-context",
    "--project-root",
    "/tmp/wiki",
    "--background",
    "A paragraph from an agent",
    "--max-items",
    "3",
    "--character-budget",
    "1200",
  ]);
});

test("resolves KnowYou command from app bundle or executable env", () => {
  assert.equal(
    resolveKnowYouCommand({ KNOWYOU_APP: "/Applications/KnowYou.app" }),
    "/Applications/KnowYou.app/Contents/MacOS/KnowYou",
  );
  assert.equal(
    resolveKnowYouCommand({ KNOWYOU_BINARY: "/tmp/KnowYou" }),
    "/tmp/KnowYou",
  );
});

test("default project root can be overridden through env", () => {
  assert.equal(defaultProjectRoot({ KNOWYOU_MY_WIKI_PROJECT: "/tmp/context" }), "/tmp/context");
});

test("page path resolution rejects traversal and absolute paths", () => {
  assert.equal(
    resolvePagePath("wiki/concepts/agent-context.md", "/tmp/context").relativePath,
    "wiki/concepts/agent-context.md",
  );
  assert.throws(() => resolvePagePath("../secrets.md", "/tmp/context"), /inside projectRoot/);
  assert.throws(() => resolvePagePath("/tmp/context/wiki/page.md", "/tmp/context"), /must not be absolute/);
  assert.throws(() => resolvePagePath("wiki/page.txt", "/tmp/context"), /markdown/);
});

test("runKnowYouContext parses JSON stdout from the configured executable", async () => {
  const pack = { query: "agent", items: [], citations: [] };
  const seen = {};
  const fakeSpawn = (command, args) => {
    seen.command = command;
    seen.args = args;
    const child = new EventEmitter();
    child.stdout = stream();
    child.stderr = stream();
    queueMicrotask(() => {
      child.stdout.emit("data", JSON.stringify(pack));
      child.emit("close", 0);
    });
    return child;
  };

  const result = await runKnowYouContext(
    { background: "agent context", projectRoot: "/tmp/context" },
    { KNOWYOU_BINARY: "/tmp/KnowYou" },
    fakeSpawn,
  );

  assert.deepEqual(result, pack);
  assert.equal(seen.command, "/tmp/KnowYou");
  assert.ok(seen.args.includes("--background"));
});

function stream() {
  const emitter = new EventEmitter();
  emitter.setEncoding = () => {};
  return emitter;
}
