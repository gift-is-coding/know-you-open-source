import path from "node:path"
import { defineConfig } from "vite"

export default defineConfig({
  ssr: {
    noExternal: true,
  },
  resolve: {
    alias: {
      "@": path.resolve(__dirname, "./src"),
      "@/commands/fs": path.resolve(__dirname, "src/headless/node-fs.ts"),
      "@tauri-apps/api/core": path.resolve(__dirname, "src/headless/tauri-core.ts"),
      "@tauri-apps/api/event": path.resolve(__dirname, "src/headless/tauri-event.ts"),
      "@tauri-apps/plugin-store": path.resolve(__dirname, "src/headless/tauri-store.ts"),
    },
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
