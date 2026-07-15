# Agent Guide

This is the shortest reliable route for an AI coding agent to understand KnowYou without guessing from isolated files.

## Read order

1. [README.md](../README.md) for product scope and repository layout.
2. [AGENTS.md](../AGENTS.md) for repository execution rules.
3. [architecture.md](architecture.md) for runtime boundaries and data flow.
4. [requirements-spec.md](requirements-spec.md) for behavior that must remain true.
5. The focused tests beside the subsystem being changed.

Historical files under `docs/superpowers/` explain why earlier decisions were made, but they are not automatically current. Prefer implementation, current tests, architecture, and requirements when they disagree.

## Runtime map

| Concern | Primary code |
| --- | --- |
| App lifecycle and orchestration | `KnowYou/KnowYouApp.swift`, `KnowYou/App/AppState.swift`, `KnowYou/App/AppEnvironment.swift` |
| Capture and privacy | `KnowYou/Services/Clipboard`, `KnowYou/Services/Notifications`, `KnowYou/Services/Privacy` |
| Local persistence | `KnowYou/Services/Storage`, `KnowYou/Domain` |
| Diary generation | `KnowYou/Services/Composer`, `KnowYou/Services/Summary` |
| My Wiki | `KnowYou/Services/MyWiki`, `ThirdParty/llm_wiki` |
| Search and Todo | `KnowYou/Services/Search`, `KnowYou/Services/Todo` |
| Networking | `KnowYou/Services/Networking`, `KnowYou/UI/Networking`, `NetworkingWeb` |
| Updates and release | `KnowYou/Services/Updates`, `scripts/`, `Support/update-feed` |

## Non-negotiable boundaries

- Apply privacy filtering before captured text is persisted.
- Store API, refresh, device, and agent credentials in Keychain; never serialize plaintext secrets to repository or runtime JSON.
- Remote LLM endpoints must use HTTPS. Plain HTTP is only valid for loopback development services.
- Keep private My Wiki evidence and private matching reasons off the Networking service.
- Treat profile publication and high-risk public interaction as explicit user-controlled boundaries.
- Preserve source paths and citations when producing My Wiki context.
- Report degraded or failed semantic pipelines explicitly; do not fake successful ontology output with keyword rules.
- Never reset user onboarding, authentication, engines, Keychain, or app containers as a routine build step.

## Working method

1. Verify the exact worktree, branch, and dirty state with `git status`, `git log`, and `git worktree list`.
2. Convert the request into observable success criteria.
3. Read the focused production code and its tests.
4. Add a failing focused test for behavior changes.
5. Implement the smallest coherent fix.
6. Run targeted checks, then the full applicable verification listed in [CONTRIBUTING.md](../CONTRIBUTING.md).
7. Review `git diff` for accidental personal paths, credentials, generated files, and unrelated edits.

Do not claim completion without fresh verification output from the current worktree. If Xcode, credentials, browsers, or production services are unavailable, name the unverified gate explicitly.
