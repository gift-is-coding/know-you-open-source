# My Wiki MCP Context Architecture Design

## Goal

KnowYou should provide private, cited context to external agents through My Wiki.
The agent should not scan all KnowYou diaries, source files, or raw notes directly.
Instead, KnowYou compiles those materials into My Wiki, and My Wiki becomes the
agent-facing abstraction and index layer.

The architecture decision is:

- KnowYou/My Wiki is the MCP server provider.
- Codex, Claude Code, OpenClaw, Cursor, and similar tools are MCP hosts/clients.
- Agents connect to the KnowYou-provided MCP server and call My Wiki tools.
- A companion Skill tells agents when and how to call those MCP tools.

## Current Understanding

MCP uses a client-server architecture. The AI application is the MCP host, the
host creates an MCP client for each configured server, and the MCP server is the
program that provides context or tools. Local MCP servers normally use stdio
transport and are launched by the host process when needed. Remote MCP servers
normally use Streamable HTTP and require stronger authentication and deployment
controls.

References:

- MCP architecture overview: https://modelcontextprotocol.io/docs/learn/architecture
- MCP server concepts: https://modelcontextprotocol.io/docs/learn/server-concepts
- Local MCP servers: https://modelcontextprotocol.io/docs/develop/connect-local-servers
- Agent Skills for MCP workflows: https://modelcontextprotocol.io/docs/develop/build-with-agent-skills

This means the product should not be described as "generating MCP inside the
agent." The product should be described as "adding KnowYou My Wiki to the
agent." Under the hood, KnowYou installs the agent-side connection config, but
the server capability belongs to KnowYou.

## Architecture

```text
KnowYou raw data
  diaries / notes / chats / source documents / imported files
        |
        v
My Wiki build layer
  concepts / projects / people / companies / decisions / source summaries
        |
        v
My Wiki index layer
  lexical search + semantic search + graph links + recency + citations
        |
        v
Context Pack service
  background paragraph -> compact cited context pack
        |
        v
KnowYou My Wiki MCP server
  tools/resources exposed over local stdio MCP
        |
        v
Agent host/client
  Codex / Claude Code / OpenClaw / Cursor / Gemini CLI
        |
        v
Agent Skill
  tells the agent when to call My Wiki and how to use citations
```

The MCP server should expose My Wiki, not raw KnowYou storage. Raw files remain
internal implementation detail. My Wiki is the contract boundary.

## V1 Scope

V1 should stay local-only.

- Use local stdio MCP. The agent host starts the KnowYou MCP process when it
  needs tools.
- Do not expose a localhost HTTP API by default.
- Do not expose remote access.
- Keep MCP tools read-only.
- Keep citations in every context response.
- Install both the MCP connection and the companion Skill for supported agents.

The current implementation already approximates this flow:

```text
Agent host
  -> starts KnowYou --my-wiki-mcp --project-root <path> over stdio
  -> calls my_wiki_context(background)
  -> KnowYou reads My Wiki markdown and returns JSON context
```

This is the default V1 transport shape. `Tools/MyWikiMCP` may remain as a
developer compatibility wrapper, but the user-facing product must not require
Node, npm, `node_modules`, or a first-run dependency download. The part that
still needs architectural improvement is the retrieval layer: it should evolve
from scanning markdown files to querying a durable My Wiki index.

## MCP Interface

Keep the first MCP surface small and stable.

### Tool: `my_wiki_context`

Purpose: return a compact, cited context pack for a natural-language background
paragraph.

Input:

```json
{
  "background": "Full user question, task background, or planning context.",
  "maxItems": 6,
  "characterBudget": 6000
}
```

Output:

```json
{
  "query": "...",
  "summary": "Short synthesis when available.",
  "items": [
    {
      "title": "...",
      "pageType": "concept",
      "excerpt": "...",
      "score": 123,
      "matchedTerms": ["..."],
      "citation": {
        "relativePath": "wiki/concepts/example.md",
        "sourceKind": "wiki",
        "day": "2026-05-23"
      }
    }
  ],
  "citations": []
}
```

The background field is intentionally not named `keyword`. Agents should pass the
full context they are working from, because My Wiki should infer concepts from a
paragraph, not only exact terms.

### Tool: `my_wiki_read_page`

Purpose: read a page that was already returned as a citation.

Input:

```json
{
  "relativePath": "wiki/concepts/example.md"
}
```

Rules:

- Accept only relative markdown paths.
- Resolve only inside the configured My Wiki project root.
- Do not allow arbitrary filesystem reads.

### Future Resources

After the tool interface is stable, the server can add MCP resources for direct
My Wiki browsing:

- `mywiki://index`
- `mywiki://concept/{id}`
- `mywiki://project/{id}`
- `mywiki://decision/{id}`

Resources are useful for browsing and explicit context selection. The tool stays
the primary path for agent-initiated retrieval.

## My Wiki Index Layer

The long-term retrieval engine should not scan every markdown page for every
agent request. It should maintain a local index built from My Wiki pages.

Index entries should include:

- stable page id
- title
- page type
- canonical path
- frontmatter metadata
- excerpt/chunks
- source citations
- updated timestamp
- entities and tags
- outgoing links
- incoming links
- embedding vector when available

Ranking should combine:

- lexical match for exact names and technical terms
- semantic match for natural-language background
- page type priority, with compiled wiki pages above raw sources
- recency, especially for active projects and recent decisions
- graph proximity, such as project -> concept -> person/company links
- citation confidence

The first index implementation can be local and deterministic. It can start with
SQLite/GRDB tables for page metadata and text chunks, then add embeddings and
graph edges incrementally.

## Skill Layer

The Skill is required because MCP only provides tools; it does not guarantee the
agent will choose the right tool at the right time.

The My Wiki Skill should tell agents:

- Use `my_wiki_context` when a task may depend on the user's projects,
  decisions, preferences, work history, people, companies, prior notes, meetings,
  or private/local context.
- Pass the full background or user question, not a reduced keyword.
- Start with `maxItems: 6` and `characterBudget: 6000`.
- Use citations in the answer.
- Call `my_wiki_read_page` only for cited pages that need more detail.
- If My Wiki returns weak or empty context, say that limitation explicitly.

Supported agent installation should do two operations together when the target
agent supports both operations:

1. Install the MCP connection config.
2. Install or copy the My Wiki Skill.

The user-facing action should be named like `Add My Wiki to Codex`, not `Start
MCP`.

## Agent Installation Model

KnowYou should detect supported agents and install the matching local setup.

For each supported agent, keep a detector and installer:

- detect whether the agent is present
- find the MCP config path
- find the Skill directory when supported
- write a managed MCP config block
- copy/update the My Wiki Skill
- create backups before modifying existing config
- report installed / needs restart / needs manual path / unsupported

V1 built-in automatic installers:

- Codex: `~/.codex/config.toml` plus `~/.codex/skills/my-wiki-context`
- Claude Code: `~/.claude.json` plus `~/.claude/skills/my-wiki-context`
- Claude Desktop: `~/Library/Application Support/Claude/claude_desktop_config.json`; no companion Skill directory by default
- Cursor: `~/.cursor/mcp.json` plus `~/.cursor/skills/my-wiki-context`
- Gemini CLI: `~/.gemini/settings.json` plus `~/.gemini/skills/my-wiki-context`
- OpenClaw: `~/.openclaw/openclaw.json` plus `~/.openclaw/skills/my-wiki-context`

If a path is customized or unknown, KnowYou should not guess destructively. It
should let the user choose a folder or copy the Skill/config manually.

The installer result should be user-readable and machine-testable:

```json
{
  "agent": "Codex",
  "mcpConnection": "installed",
  "skill": "installed",
  "backupCreated": true,
  "restartRequired": true,
  "manualAction": null
}
```

## Security Boundaries

V1 is local-only because My Wiki contains private context.

- No remote HTTP endpoint by default.
- No network listener by default.
- Read-only MCP tools.
- Path traversal must be blocked.
- Agent configs are local machine configs, not shareable public credentials.
- Every context item should include a citation so the agent can avoid treating
  retrieved context as unsupported memory.
- Future remote access must be a separate design with authentication, permission
  scopes, audit logs, and explicit user approval.

## Product Language

Use technical terms in advanced sections only.

Preferred user-facing wording:

- `Add My Wiki to Codex`
- `Install My Wiki for this agent`
- `My Wiki context is available`
- `Restart Codex once`
- `Ask Codex normally`

Avoid primary UI wording like:

- `Start MCP`
- `Open MCP`
- `Generate MCP in Agent`
- `stdio server`
- `TOML config`

The primary setup UI should be a short step-by-step installer. It should not
show explanatory yellow note boxes or technical architecture callouts. Those
details belong in advanced/help surfaces, not in the first-run path.

The correct mental model is:

```text
KnowYou provides My Wiki context.
The agent connects to KnowYou's local My Wiki tool.
The Skill teaches the agent when to use that tool.
```

## Migration From Current MVP

The current implementation should not be thrown away. It should be reframed and
extended.

Keep:

- native `KnowYou --my-wiki-mcp`
- `my_wiki_context`
- `my_wiki_read_page`
- `KnowYou --my-wiki-context`
- local stdio MCP
- managed Codex config block
- `.agents/skills/my-wiki-context`

Change next:

- keep user-facing setup language centered on `Add My Wiki to <Agent>`
- extend automatic install status beyond Codex to all built-in agents
- add agent detection for customized install paths
- evolve retrieval from markdown scan to a durable My Wiki index
- keep advanced MCP config as a fallback, not the main workflow

## Acceptance Criteria

- A developer can explain the architecture as "KnowYou provides a local My Wiki
  MCP server; agents connect to it."
- Agents never need to read raw KnowYou storage directly.
- `my_wiki_context` accepts a background paragraph and returns cited context.
- Supported agents get both MCP connection and Skill installation.
- Unsupported/custom agents get copyable Skill and config instructions.
- The UI does not make users reason about MCP unless they open advanced details.
- No remote or network service is introduced in V1.
