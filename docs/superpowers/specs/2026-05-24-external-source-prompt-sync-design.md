# External Source Prompt Sync Design

KnowYou does not own remote-platform authentication for Feishu, Notion, or Google Drive. It only generates a prompt that the user can run in Codex or Cloud Code, and then reads the local Markdown directory produced by that automation.

## Requirements

- Add Source shows one `Sources` list. It must not split unconnected sources and connected sources into separate sections.
- Add Source must not show a generic API/token form for external platforms.
- Feishu, Notion, and Google Drive setup generates a copyable prompt with schedule, time, platform, optional scope, and a KnowYou-owned local output directory.
- KnowYou may save local source metadata: platform type, display name, local directory, enabled state.
- KnowYou must not save bearer tokens, OAuth secrets, cookies, account credentials, or remote authorization state for these platforms.
- Sync reads `.md`, `.markdown`, and `.txt` files from the local output directory and imports them through the existing Knowledge Sources cache and SQLite index.
- The sidebar renders Add Source as an independent entry, not a collapsible parent.
- Connector roots expand into a path-based Markdown tree in the left sidebar; clicking a document leaf opens the Markdown preview.

## Out Of Scope

- KnowYou does not install platform CLIs.
- KnowYou does not create remote-platform OAuth flows.
- KnowYou does not parse Markdown headings into sidebar nodes in this version.
