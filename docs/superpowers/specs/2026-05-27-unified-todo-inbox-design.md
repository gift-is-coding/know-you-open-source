# Unified Todo Inbox Design

## Summary

KnowYou's current to-do output lives inside each generated daily diary as a Markdown task list. That makes to-dos easy to read in context, but hard to trust as an actual task system: every day can produce fresh items, there is no single inbox, and there is no stable completed state.

This feature adds a native Todo inbox. Daily diary to-do sections become candidate extraction surfaces; the app-level inbox becomes the source of truth for open and completed task state. The inbox is backed by a first-class Markdown document in the user's Vault so the task list remains portable and inspectable outside the app.

## Product Decisions

- Add a first-class `Todo` entry in the left sidebar, parallel to `My Diary`.
- Auto-promote only high-confidence, concrete, actionable, non-duplicate items.
- Keep low-confidence or broad suggestions in the diary only, with a manual `Add to Todo` action.
- Auto-completion only marks existing to-dos complete when later diary/source evidence clearly proves the work was done.
- Do not execute external actions such as sending messages, creating calendar events, or editing files.
- Do not bulk-import historical diary tasks.
- Allow direct manual entry from the Todo page, in addition to diary candidate promotion.
- Persist unified Todo state in `Vault/Todo.md`; SQLite `todo_items` is retained as migration/compatibility storage, not the canonical user-facing backing document.

## Data Model

`UnifiedTodoItem` is persisted in `Vault/Todo.md` as Markdown task rows with hidden `knowyou:todo` metadata comments. The model contains:

- stable `id`
- normalized `title`
- `status`: `open` or `completed`
- `sourceDayKey`
- `sourceEventIDs`
- `createdAt`
- optional `completedAt`
- optional `completionEvidenceEventIDs`
- `promotionKind`: `auto` or `manual`
- optional `completionKind`: `manual` or `evidence-sweep`

Completed items remain persisted and are displayed below open items. On first launch after this change, if `Todo.md` does not exist but old `todo_items` rows exist in SQLite, KnowYou seeds `Todo.md` from SQLite once.

## Behavior

During diary generation:

1. The diary prompt asks for at most three concrete, evidence-backed, still-open candidate to-dos.
2. `TodoReconciler` compares diary candidates with existing open and completed todo items.
3. High-confidence `create` decisions are inserted automatically.
4. Duplicate or already-completed candidates are ignored.
5. Unclear candidates remain visible in the diary and can be manually added.
6. `TodoCompletionSweep` compares new daily evidence with open todo items and completes only items with clear completion proof.

If no verified LLM engine is available or the semantic step fails, automatic promotion/completion is skipped. Manual add and manual complete remain available.

Automatic updates happen after successful diary generation/refresh, when opening the Todo page, and immediately after manual add/complete actions. External edits to `Todo.md` are read on the next Todo refresh/open; v1.1 does not add a continuous file watcher.

## UI

- The left sidebar has a `Todo` root row with a badge for open item count.
- The Todo page shows open items first and completed items at the bottom.
- The Todo page includes a direct text field for manually adding a task.
- Each item shows title, source day, promotion/completion metadata, and source evidence count.
- Daily task-list rows show `Add to Todo` for candidates not already tracked and `In Todo` for matched items.

## Acceptance Criteria

- Newly generated noisy diary to-dos do not flood the Todo inbox.
- A clear high-confidence task is auto-promoted once and not duplicated on later refreshes.
- A low-confidence candidate can be manually promoted from the diary.
- A user can type a task directly into the Todo page and it appears in `Todo.md`.
- Later evidence can conservatively auto-complete an open item and records evidence IDs.
- Completed items remain visible at the bottom of the Todo page.
- Existing daily diary generation and source-linked story behavior continue to work.

## Non-Goals

- No historical backfill of existing diary Markdown task lists.
- No external task execution.
- No sync to Apple Reminders, Things, Calendar, Jira, or external systems in v1.
- No continuous file watching of `Todo.md` in v1.1.
