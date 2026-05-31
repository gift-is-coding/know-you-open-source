# 03 - Todo Inbox

## Goal

Protect the unified Todo workflow: users should be able to review open/completed tasks, manually add a task, promote daily candidates, and complete tasks with state persisted to `Vault/Todo.md`.

## Environment

- Type: `app-clean`
- Data: seeded `Vault/Todo.md`, at least one open todo, one completed todo, one daily candidate, and one close recommendation
- Isolation: temporary profile root, UserDefaults suite, Keychain service, Vault, and SQLite; no daily app data should be read or modified

## Steps

1. Launch KnowYou with completed onboarding.
2. Open the `Todo` root from the sidebar.
3. Verify open tasks appear before completed tasks.
4. Enter a new user task in the input field.
5. Click `Add`.
6. Verify the new task appears in the open section.
7. Open a seeded diary day containing candidate todo actions.
8. Click `Add to Todo` for a candidate.
9. Return to Todo and verify the candidate is now tracked.
10. Complete one open todo.
11. Verify it moves into completed state and remains visible when completed items are expanded.
12. If a close recommendation exists, click `Keep` once and verify it disappears without completing the task.
13. If a second close recommendation exists, click `Close` and verify the task completes with evidence.

## Assertions

- `Vault/Todo.md` is the persisted source of truth.
- Manual add works even when summarizer automation is degraded.
- Candidate promotion does not create duplicate open tasks for the same semantic item.
- Completed tasks are not deleted.
- `Inbox / 待选` and `推荐关闭` states are explainable when automation cannot decide.
- A failed summarizer reconciliation must not silently create or close tasks.

## Automation

- Level: `pre-push`
- Codex Skill case id: `todo-inbox`
- Use Codex GUI / ComputerUser for Todo navigation, manual entry, candidate promotion, completion, and recommendation actions.
- Pair UI checks with file assertions against the regression profile's `Vault/Todo.md`.

## Update Triggers

- Todo Markdown schema changes
- Todo sorting, grouping, or completion behavior changes
- Candidate extraction or `Add to Todo` placement changes
- Evidence sweep or close recommendation behavior changes
