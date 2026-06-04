import path from "node:path"
import { defineConfig } from "vite"

export default defineConfig({
  ssr: {
    noExternal: true,
  },
  resolve: {
    alias: [
      { find: "@/commands/fs", replacement: path.resolve(__dirname, "src/headless/node-fs.ts") },
      { find: "@tauri-apps/api/core", replacement: path.resolve(__dirname, "src/headless/tauri-core.ts") },
      { find: "@tauri-apps/api/event", replacement: path.resolve(__dirname, "src/headless/tauri-event.ts") },
      { find: "@tauri-apps/plugin-store", replacement: path.resolve(__dirname, "src/headless/tauri-store.ts") },
      { find: "@", replacement: path.resolve(__dirname, "./src") },
    ],
  },
  build: {
    ssr: "src/headless/knowyou-ingest.ts",
    outDir: "dist-knowyou-runner",
    emptyOutDir: true,
    minify: "oxc",
    rollupOptions: {
      output: {
        entryFileNames: "mywiki-runner.js",
        format: "es",
        inlineDynamicImports: true,
      },
      external: [
        "node:fs/promises",
        "node:path",
        "node:process",
        "node:readline",
        "node:url",
      ],
    },
  },
})
