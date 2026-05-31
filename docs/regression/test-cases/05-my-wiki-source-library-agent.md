# 05 - My Wiki, Source Library, And Agent Setup

## Goal

Protect My Wiki as the governed knowledge layer: users should open My Wiki, search/browse entries, manage included sources, update the wiki, review duplicate suggestions, and access agent setup without exposing raw diary files.

## Environment

- Type: `app-clean`
- Data: seeded diary files, source catalog records, at least one imported document, and a small My Wiki project fixture
- Isolation: My Wiki project, Source Library state, and agent setup previews must live inside the regression profile; automated runs must not modify real agent config files

## Steps

1. Launch KnowYou with completed onboarding.
2. Open `My Wiki` from the sidebar.
3. Verify the My Wiki index and detail panes are visible.
4. Search for a seeded project, person, or topic.
5. Select a visible entry.
6. Verify detail sections show summary, aliases/mentions/related items/sources when fixture data exists.
7. Open `Manage Sources`.
8. Verify My Diary and imported sources appear with included/excluded states.
9. Toggle a non-critical fixture source out and back in.
10. Trigger `Update My Wiki` in deterministic mode, or verify the action is reachable in quick mode.
11. If duplicate suggestions are seeded, open duplicate review and choose cancel/not duplicates.
12. Open `Use My Wiki in Agents`.
13. Verify client choices such as Codex, Claude Code, Cursor, Gemini CLI, and OpenClaw are shown.
14. Verify setup status explains project root and app readiness.

## Assertions

- `My Wiki`, `Other Source`, and `My Diary` keep the same global window frame and toolbar.
- My Wiki consumes governed source catalog state, not raw unrestricted diary exposure.
- Source Library persists included/excluded choice in the regression profile.
- Updating My Wiki reports progress and failure clearly.
- Duplicate review is reachable but does not merge without explicit user action.
- Agent setup presents local, read-only context access and does not require sending raw wiki data elsewhere.
- Automated pre-push must not modify the user's real Codex/Claude/Cursor/Gemini/OpenClaw config.

## Automation

- Level: `pre-push` for open/search/source-library/agent-sheet reachability
- Level: `nightly` for actual My Wiki update and duplicate suggestion fixtures
- Codex Skill case id: `my-wiki-source-library-agent`
- Use Codex GUI / ComputerUser for My Wiki navigation, source management, duplicate review, and agent setup reachability.

## Update Triggers

- My Wiki navigation changes
- Source Library states or source catalog schema changes
- llm_wiki ingest integration changes
- Duplicate review behavior changes
- Agent setup clients, config format, or safety copy changes
