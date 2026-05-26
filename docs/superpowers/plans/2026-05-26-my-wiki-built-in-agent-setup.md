# My Wiki Built-in Agent Setup Plan

## Steps

1. Add focused failing tests for bundled Skill frontmatter and all built-in
   agent installers.
2. Extend `MyWikiAgentClient` with Claude Code and OpenClaw, plus automatic
   install and companion Skill capability flags.
3. Generalize `MyWikiAgentConfigurationInstaller` from Codex-only to per-client
   config paths, JSON merging, backup creation, setup status, and Skill copying.
4. Update `MyWikiAgentConnectionSheet` so the selected built-in agent can be
   installed with `Add My Wiki`; keep Generic MCP as manual copy setup.
5. Add frontmatter to `.agents/skills/my-wiki-context/SKILL.md`.
6. Use the native `KnowYou --my-wiki-mcp --project-root <path>` server in all
   generated configs so users never need Node, npm, or a first-run dependency
   download.
7. Update requirements, architecture, and Superpower docs.
8. Run focused Swift tests, native MCP smoke tests, full macOS tests/build, and
   whitespace checks.

## Gemini CLI Follow-up

Local and official documentation checks found:

- Gemini CLI executable: `/opt/homebrew/bin/gemini`
- User MCP config: `~/.gemini/settings.json`
- MCP server key: top-level `mcpServers`
- User Skill install destination: `~/.gemini/skills/my-wiki-context`
- Gemini CLI also supports `gemini mcp add --scope user ...` and
  `gemini skills install <local-path> --scope user --consent`, but KnowYou uses
  direct JSON merge and Skill copy so setup can be tested without shelling out
  to a user-installed CLI.

## Verification Commands

- `xcodebuild test -scheme KnowYou -destination 'platform=macOS' -only-testing:KnowYouTests/MyWikiAgentConfigurationTests -only-testing:KnowYouTests/KnowledgeOntologyPanelTests/testDetailMoreMenuIncludesAgentContextAction`
- `xcodebuild test -scheme KnowYou -destination 'platform=macOS' -only-testing:KnowYouTests/MyWikiContextPackCommandTests`
- `xcodebuild test -scheme KnowYou -destination 'platform=macOS'`
- `xcodebuild build -scheme KnowYou -destination 'platform=macOS'`
- `git diff --check`
