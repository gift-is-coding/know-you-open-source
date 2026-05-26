# My Wiki Redesign Agent Context Migration Design

## Goal

Move the My Wiki Agent Context/MCP capability onto the `codex/my-wiki-redesign` baseline so the final app keeps the redesigned My Wiki UI, theme, schema-driven navigation, source library, duplicate review, and native LLM Wiki pipeline behavior.

## User Experience

- The user opens `My Wiki` in the redesigned panel.
- The user can click `Use My Wiki in Agents` from the My Wiki header or from the detail `More` menu.
- The default action is `Add My Wiki` for built-in agents: Codex, Claude Code, Claude Desktop, Cursor, Gemini CLI, and OpenClaw.
- Manual MCP JSON/TOML snippets remain available in `Advanced MCP Config` for generic or custom agents.
- The UI explains that KnowYou does not keep MCP running; Codex or another MCP client starts the stdio MCP process when the agent uses the tool.

## Architecture

- `MyWikiContextPackService` scans the My Wiki project `wiki/` and `raw/sources/` markdown files and returns a compact, cited context pack for a natural-language background paragraph.
- `MyWikiContextPackCommand` exposes the same capability through `KnowYou --my-wiki-context`.
- `KnowYouApp` detects the headless context command, writes JSON to stdout/stderr, and exits before bootstrapping app services.
- `Tools/MyWikiMCP` exposes `my_wiki_context` and `my_wiki_read_page` over stdio MCP.
- `MyWikiAgentConnectionSheet` writes managed setup for built-in clients: Codex uses a marked TOML block, Claude Code/Claude Desktop/Cursor/Gemini CLI use `mcpServers`, and OpenClaw uses `mcp.servers`.
- The installer copies the `my-wiki-context` Skill for built-in clients that support companion Skills: Codex, Claude Code, Cursor, Gemini CLI, and OpenClaw.

## Boundaries

- This migration must not resurrect the old `KnowledgeOntologyPanel` UI.
- It must not alter the LLM Wiki ingest contract or replace native `Sources / Entities / Concepts` behavior.
- The MCP wrapper is local-only and read-only for the configured My Wiki project.
- Codex config writes must back up existing config before editing.

## Acceptance Criteria

- New branch/worktree is based on `codex/my-wiki-redesign`.
- Focused Swift tests pass for context pack, CLI command, Codex installer, agent presentation, and My Wiki menu policy.
- MCP package tests pass.
- Built-in agent setup tests cover config writes, backups/status checks, source Skill frontmatter, and companion Skill installation for all supported built-in agents.
- `xcodebuild build -scheme KnowYou -destination 'platform=macOS'` passes.
- Launched app comes from the new worktree build and still shows redesigned My Wiki UI.
