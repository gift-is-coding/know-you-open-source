import { describe, expect, it } from "vitest";
import { readdirSync, readFileSync, statSync } from "node:fs";
import { join, relative } from "node:path";

const checkedRoots = [
  "app",
  "src/components",
  "src/lib/networking/platforms.ts",
  "src/lib/networking/supabase-data.ts",
  "src/lib/networking/agent-home.ts"
];

describe("networking web copy contract", () => {
  it("keeps the public Web UI in English", () => {
    const offenders = checkedRoots.flatMap((root) => collectSourceFiles(join(process.cwd(), root)))
      .flatMap((file) => {
        const source = readFileSync(file, "utf8");
        const lines = source.split("\n");
        return lines.flatMap((line, index) => /[\u4e00-\u9fff]/.test(line)
          ? [`${relative(process.cwd(), file)}:${index + 1}:${line.trim()}`]
          : []
        );
      });

    expect(offenders).toEqual([]);
  });
});

function collectSourceFiles(path: string): string[] {
  if (!statSync(path).isDirectory()) {
    return [path];
  }

  return readdirSync(path)
    .flatMap((entry) => collectSourceFiles(join(path, entry)))
    .filter((file) => /\.(css|tsx?|jsx?)$/.test(file));
}
