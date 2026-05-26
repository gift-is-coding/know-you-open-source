#!/usr/bin/env node
import { McpServer } from "@modelcontextprotocol/sdk/server/mcp.js";
import { StdioServerTransport } from "@modelcontextprotocol/sdk/server/stdio.js";
import { z } from "zod";
import { readWikiPage, runKnowYouContext } from "./myWikiBridge.mjs";

const server = new McpServer({
  name: "knowyou-my-wiki",
  version: "0.1.0",
});

server.registerTool(
  "my_wiki_context",
  {
    title: "My Wiki Context",
    description: "Return compact, cited KnowYou My Wiki context for a natural-language background paragraph.",
    inputSchema: {
      background: z.string().min(1).describe("Background paragraph, task description, or question from the calling agent."),
      projectRoot: z.string().optional().describe("Optional KnowYouContext project root. Defaults to KNOWYOU_MY_WIKI_PROJECT or the local KnowYou app support path."),
      maxItems: z.number().int().min(1).max(20).optional(),
      characterBudget: z.number().int().min(200).max(20000).optional(),
    },
  },
  async input => {
    try {
      const pack = await runKnowYouContext(input);
      return {
        content: [{ type: "text", text: JSON.stringify(pack, null, 2) }],
        structuredContent: pack,
      };
    } catch (error) {
      return {
        isError: true,
        content: [{ type: "text", text: error.message }],
      };
    }
  },
);

server.registerTool(
  "my_wiki_read_page",
  {
    title: "Read My Wiki Page",
    description: "Read a markdown page returned by a My Wiki citation. Only relative paths under the configured project root are allowed.",
    inputSchema: {
      relativePath: z.string().min(1).describe("Citation relativePath returned by my_wiki_context."),
      projectRoot: z.string().optional().describe("Optional KnowYouContext project root. Defaults to KNOWYOU_MY_WIKI_PROJECT or the local KnowYou app support path."),
    },
  },
  async input => {
    try {
      const page = await readWikiPage(input);
      return {
        content: [{ type: "text", text: page.text }],
        structuredContent: {
          relativePath: page.relativePath,
          text: page.text,
        },
      };
    } catch (error) {
      return {
        isError: true,
        content: [{ type: "text", text: error.message }],
      };
    }
  },
);

const transport = new StdioServerTransport();
await server.connect(transport);
