# My Wiki Built-in Agent Setup Design

## Problem

The My Wiki agent context MVP proved that `my_wiki_context` can return relevant
wiki context, but the setup path was too Codex-specific. A copied Skill may also
be invisible to an agent loader when the source `SKILL.md` lacks standard
frontmatter.

The product behavior must not make Codex special. Built-in agents should get the
same default outcome: the agent can call KnowYou's local My Wiki MCP server, and
where the agent supports Skills, it also receives the companion Skill that tells
it when to call `my_wiki_context`.

## Architecture

KnowYou remains the MCP server provider. Agent apps remain MCP hosts/clients.
The UI action installs host-side connection config and, when supported, a
companion Skill. The default connection launches the bundled KnowYou app binary
directly with `--my-wiki-mcp --project-root <path>`; users must not need Node,
npm, `node_modules`, or a first-run dependency download.

Built-in setup targets:

- Codex: write `~/.codex/config.toml` with a managed
  `[mcp_servers.knowyou-my-wiki]` block and copy
  `~/.codex/skills/my-wiki-context`
- Claude Code: merge `knowyou-my-wiki` into `~/.claude.json` under
  `mcpServers` and copy `~/.claude/skills/my-wiki-context`
- Claude Desktop: merge `knowyou-my-wiki` into
  `~/Library/Application Support/Claude/claude_desktop_config.json` under
  `mcpServers`
- Cursor: merge `knowyou-my-wiki` into `~/.cursor/mcp.json` under
  `mcpServers` and copy `~/.cursor/skills/my-wiki-context`
- Gemini CLI: merge `knowyou-my-wiki` into `~/.gemini/settings.json` under
  `mcpServers` and copy `~/.gemini/skills/my-wiki-context`
- OpenClaw: merge `knowyou-my-wiki` into `~/.openclaw/openclaw.json` under
  `mcp.servers` and copy `~/.openclaw/skills/my-wiki-context`

Generic MCP remains a manual advanced path.

## Boundaries

- Existing unrelated agent config must be preserved.
- Existing config files must be backed up before writes.
- Re-running setup must update the My Wiki server entry without duplicating it.
- The bundled Skill must include frontmatter with `name: my-wiki-context`.
- Claude Desktop is treated as config-only unless a stable Skill location is
  introduced later.
- The UI must describe the action as adding My Wiki to an agent, not starting a
  long-running MCP process.

## Acceptance Criteria

- The setup sheet lists Codex, Claude Code, Claude Desktop, Cursor, Gemini CLI,
  OpenClaw, and Generic MCP.
- Built-in agents use automatic setup; Generic MCP uses manual copy setup.
- Codex, Claude Code, Cursor, Gemini CLI, and OpenClaw receive the companion Skill.
- `setupStatus` reports ready only when required config and required Skill are
  both present.
- Focused Swift tests cover all built-in agent config and Skill paths.
- Native MCP command tests and full macOS build/test verification pass or any existing
  unrelated blocker is recorded.
