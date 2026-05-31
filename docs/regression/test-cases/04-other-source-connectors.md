# 04 - Other Source And Connectors

## Goal

Protect the Add Source workflow: users should understand source choices, add local references safely, generate prompts for external platforms, scan Markdown/TXT files, and open imported source documents from the sidebar.

## Environment

- Type: `app-clean`
- Data: temporary local folder with Markdown/TXT files, temporary Obsidian-like vault, seeded prompt-backed directories for Feishu/Lark, Notion, and Google Drive
- Isolation: all fixture source directories live under the regression run folder; no real external account tokens, OAuth state, cookies, or daily app directories are used

## Steps

1. Launch KnowYou with completed onboarding.
2. Open `Other Source`.
3. Verify the page is titled as Add Source / Sources, not a Daily Memory Export panel.
4. Verify source cards exist for My Diary, Local Folder, Obsidian, Feishu Docs, Notion, and Google Drive.
5. Add a Local Folder source using a regression fixture path.
6. Trigger manual refresh/scan from the source management page.
7. Verify the source appears as a sidebar source item.
8. Expand the source root in the sidebar.
9. Click a Markdown/TXT leaf document.
10. Verify the main content opens a Markdown preview and hides YAML frontmatter.
11. Return to `Other Source`.
12. Open Feishu/Notion/Google Drive `Generate Prompt`.
13. Verify the prompt dialog defaults to daily frequency and local time 11:00.
14. Copy/create the prompt-backed source without saving tokens or auth state.

## Assertions

- Local Folder and Obsidian are reference-only; original files are not copied or modified.
- Feishu/Lark, Notion, and Google Drive do not ask KnowYou for token, OAuth secret, cookie, or bearer token.
- Prompt generation happens in a dialog, not inline under the source list.
- Daily Memory Export does not appear as an Add Source card.
- Obsidian scan skips KnowYou Daily Memories exports.
- Connector root and folders expand/collapse in the sidebar without opening duplicate indexes.
- Document leaves open Markdown preview and do not show refresh/configure controls in the reader surface.
- A failed scan for one source does not block other sources.

## Automation

- Level: `pre-push` for Local Folder, prompt dialog reachability, source tree, and Markdown preview
- Level: `nightly` for broader Obsidian and prompt-backed directory scan coverage
- Codex Skill case id: `other-source-connectors`
- Use Codex GUI / ComputerUser for source cards, prompt dialogs, source tree expansion, and Markdown preview.

## Update Triggers

- Connector list changes
- Source scan persistence changes
- Prompt format, default frequency, or default time changes
- Sidebar source tree behavior changes
- Markdown preview behavior changes
