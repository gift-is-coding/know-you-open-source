# My Wiki Redesign Agent Context Migration Plan

## Steps

1. Create `codex/my-wiki-redesign-agent-context` from `codex/my-wiki-redesign`.
2. Add failing tests for:
   - `MyWikiContextPackService`
   - `MyWikiContextPackCommand`
   - `MyWikiAgentConfigurationInstaller`
   - `MyWikiAgentConnectionPresentation`
   - My Wiki detail menu policy
3. Port Agent Context code from the old agent-access branch into `Services/MyWiki` and `UI/MyWiki`.
4. Connect `Use My Wiki in Agents` to the redesigned `MyWikiPanel` header and detail `More` menu.
5. Port `Tools/MyWikiMCP` and `.agents/skills/my-wiki-context`.
6. Update `KnowYouApp` with `--my-wiki-context` headless launch mode.
7. Update architecture, requirements, and superpowers docs.
8. Verify focused Swift tests, MCP tests, build, and app launch.

## Follow-up: Built-in Agent Coverage

The original migration was too Codex-centric. The user-reported discovery issue showed two missing pieces:

1. The bundled source Skill needed standard YAML frontmatter so copied Skills are discoverable by agent loaders.
2. Built-in setup needed to install both MCP config and companion Skill for supported agents, not only Codex.

Implemented coverage:

- Codex: managed TOML block plus `~/.codex/skills/my-wiki-context`
- Claude Code: JSON `mcpServers` merge plus `~/.claude/skills/my-wiki-context`
- Claude Desktop: JSON `mcpServers` merge
- Cursor: JSON `mcpServers` merge plus `~/.cursor/skills/my-wiki-context`
- Gemini CLI: JSON `mcpServers` merge into `~/.gemini/settings.json` plus `~/.gemini/skills/my-wiki-context`
- OpenClaw: JSON `mcp.servers` merge plus `~/.openclaw/skills/my-wiki-context`
- Generic MCP: copyable manual config remains in `Advanced MCP Config`

## Verification Commands

- `xcodebuild test -scheme KnowYou -destination 'platform=macOS' -only-testing:KnowYouTests/MyWikiContextPackServiceTests -only-testing:KnowYouTests/MyWikiContextPackCommandTests -only-testing:KnowYouTests/MyWikiAgentConfigurationTests -only-testing:KnowYouTests/KnowledgeOntologyPanelTests/testDetailMoreMenuIncludesAgentContextAction`
- `npm test` from `Tools/MyWikiMCP`
- `xcodebuild build -scheme KnowYou -destination 'platform=macOS'`
- Attempt `xcodebuild test -scheme KnowYou -destination 'platform=macOS'`; if existing diary-generation tests invoke live `codex exec`, record the blocker.
