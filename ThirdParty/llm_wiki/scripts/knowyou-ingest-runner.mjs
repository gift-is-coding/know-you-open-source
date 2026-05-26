import path from "node:path"
import { fileURLToPath } from "node:url"
import { createServer } from "vite"

const __dirname = path.dirname(fileURLToPath(import.meta.url))
const root = path.resolve(__dirname, "..")

const server = await createServer({
  root,
  logLevel: "error",
  appType: "custom",
  resolve: {
    alias: [
      {
        find: "@/commands/fs",
        replacement: path.resolve(root, "src/headless/node-fs.ts"),
      },
      {
        find: "@tauri-apps/api/core",
        replacement: path.resolve(root, "src/headless/tauri-core.ts"),
      },
      {
        find: "@tauri-apps/api/event",
        replacement: path.resolve(root, "src/headless/tauri-event.ts"),
      },
      {
        find: "@",
        replacement: path.resolve(root, "src"),
      },
    ],
  },
  server: {
    middlewareMode: true,
    hmr: false,
  },
})

try {
  const mod = await server.ssrLoadModule("/src/headless/knowyou-ingest.ts")
  await mod.runKnowYouIngestCli(process.argv.slice(2))
} finally {
  await server.close()
}
