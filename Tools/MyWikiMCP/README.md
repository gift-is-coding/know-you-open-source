# KnowYou My Wiki MCP

Local stdio MCP server that exposes KnowYou My Wiki as a cited context provider for agents.

## Tools

- `my_wiki_context`: accepts a natural-language background paragraph and returns a compact JSON context pack with `queryPlan`, ranked `items`, `matchedTerms`, and `citations`.
- `my_wiki_read_page`: reads a markdown page by the citation `relativePath`; traversal outside `projectRoot` is rejected.

## Setup

```bash
cd Tools/MyWikiMCP
npm install
```

Example MCP config:

```json
{
  "mcpServers": {
    "knowyou-my-wiki": {
      "command": "node",
      "args": ["/absolute/path/to/know-you/Tools/MyWikiMCP/src/server.mjs"],
      "env": {
        "KNOWYOU_APP": "/absolute/path/to/KnowYou.app",
        "KNOWYOU_MY_WIKI_PROJECT": "/absolute/path/to/your/KnowYouContext"
      }
    }
  }
}
```

`KNOWYOU_APP` can also be `KNOWYOU_BINARY` pointing directly at `KnowYou.app/Contents/MacOS/KnowYou`.

## UAT

```bash
cd Tools/MyWikiMCP
npm test
```

Then call `my_wiki_context` with a paragraph such as:

```text
I am answering an agent question about whether an AIDC project should use HVDC distribution and liquid cooling. Find the most relevant My Wiki context.
```
