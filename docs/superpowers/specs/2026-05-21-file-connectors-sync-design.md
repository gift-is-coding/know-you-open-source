# File Connectors Sync Design

## Summary

KnowYou will add a new Knowledge Imports capability that synchronizes external documents into a local KnowYou-owned cache. The first implementation target is a local-first connector platform with real connectors for Obsidian/local folders plus API-backed connectors for Feishu, Notion, and Google Drive.

This is intentionally separate from the existing Sync Memory feature. Sync Memory remains a one-way export path for KnowYou daily diary Markdown into Obsidian and OpenClaw. Knowledge Imports is the opposite direction: external documents are imported into KnowYou's local knowledge store for future reading, search, and agent context.

## Goals

- Add a connector category for external knowledge sources.
- Import external files into local storage rather than relying on live dynamic links.
- Normalize imported documents to Markdown or Markdown-like text plus metadata.
- Support manual sync and daily scheduled sync.
- Track remote identity, local content hash, sync cursor, and deletion state.
- Avoid sync loops with existing Obsidian daily diary export.
- Keep the first version extensible enough for future connectors without forcing full two-way sync.

## Non-Goals

- Do not build bidirectional editing or conflict resolution in the first version.
- Do not write edited KnowYou knowledge content back to Feishu, Notion, Google Drive, Obsidian, or local folders.
- Do not replace the current daily diary `.story.json` and `.md` pipeline.
- Do not import the existing KnowYou daily memory export directory back into the knowledge store by default.
- Do not require cloud availability for reading already imported content.

## Product Model

The current `Sync Memory` surface should be split conceptually into two categories:

- `Daily Memory Export`
  - Existing behavior.
  - Copies KnowYou-generated `YYYY-MM-DD.md` diary files to external memory targets.
  - First-class targets remain Obsidian and OpenClaw.
  - Direction is KnowYou to external tool.

- `Knowledge Imports`
  - New behavior.
  - Pulls documents from external tools into a local KnowYou cache.
  - First-class connectors are Obsidian, local folder, Feishu, Notion, and Google Drive.
  - Direction is external tool to KnowYou.

The UI can still present these under one broader "Connectors" or "Sources" area, but the data model and sync engine must keep export and import channels separate.

## First Connector Set

### Obsidian

Obsidian import scans one or more vault roots for Markdown files. It should preserve folder-relative paths in metadata, normalize file contents as Markdown, and record file modification time and content hash.

By default, Obsidian import must skip the existing KnowYou export directory:

`<vault>/KnowYou/Daily Memories/`

It must also skip files marked as KnowYou daily memory exports using frontmatter or a sidecar origin marker.

### Local Folder

Local folder import scans user-selected directories. First version should support Markdown and plain text. PDF, docx, and rich document parsing can be represented as planned extensions unless implementation scope later explicitly includes them.

The local folder connector is useful for iCloud Drive, Dropbox, OneDrive, project documentation folders, and exported note archives without adding provider-specific API work.

### Feishu

Feishu import should use an API-backed connector boundary with stored credentials, remote document identity, and incremental sync state. First implementation should normalize Feishu docs to Markdown-like text when possible and fall back to plain text while preserving source URL and remote metadata.

The design should not hardcode a single Feishu workspace assumption. The connector config should be able to represent account/workspace identity.

### Notion

Notion import should support user-configured token or OAuth-backed access, a list of selected pages/databases, and recursive page content export to Markdown-like text.

Notion block IDs and page IDs should be stored as remote stable IDs. Last-edited timestamps should be used as a cheap change detector, with content hash as the final dedupe boundary.

### Google Drive

Google Drive import should support selected folders or files. Google Docs should be exported to Markdown-like text or plain text fallback. Native `.md` and `.txt` files should retain their original content. Metadata should include Drive file ID, web URL, mime type, modified time, and parent path when available.

## Local Storage

Imported content is stored under Application Support, owned by KnowYou:

`Application Support/KnowYou/KnowledgeSources/<connector>/<source-id>/...`

Each imported document should have a stable local record:

- `content.md`
- `metadata.json`

The local file layout is an implementation detail for portability and inspection. SQLite remains the primary index for listing, dedupe, sync state, and future retrieval.

Suggested metadata fields:

- `connectorID`
- `accountID` or `workspaceID`
- `sourceID`
- `remoteID`
- `remoteURL`
- `sourcePath`
- `title`
- `mimeType`
- `contentHash`
- `remoteUpdatedAt`
- `firstImportedAt`
- `lastSyncedAt`
- `deletedAt`
- `normalizationVersion`
- `originKind`

## SQLite Index

Add a knowledge import index separate from daily diary tables. The index should support:

- Connector instances and configuration summaries.
- Imported document records.
- Remote sync cursors or page tokens.
- Per-connector last sync status.
- Tombstones for remote deletions.

Document identity should be based on connector instance plus remote stable ID when available. For local files, identity should use a bookmark/path-derived stable source ID plus relative path. Content hash should dedupe repeated content but should not replace source identity, because the same content may legitimately exist in multiple external locations.

## Sync Engine

Each import connector should conform to a common conceptual interface:

- `listChanges(since:)`
- `fetchDocument(id:)`
- `normalizeToMarkdown(document:)`
- `saveLocalSnapshot(document:)`

The first version should support:

- Manual sync now.
- Daily scheduled sync.
- Per-connector sync enable/disable.
- Per-connector last successful sync timestamp.
- Per-document content hash dedupe.
- Per-document remote update comparison.
- Tombstone marking for remote deletions.

Sync should be idempotent. Re-running sync without external changes should not rewrite local files or update user-visible status as if new content arrived.

## Loop Prevention

The existing Obsidian export path creates a loop risk: KnowYou writes daily diary Markdown into Obsidian, then Obsidian import could pull those same files back into the knowledge store.

Loop prevention is mandatory:

- Obsidian import skips `<vault>/KnowYou/Daily Memories/` by default.
- Daily Memory Export writes a frontmatter marker such as `knowyou_export: daily_memory` or a sidecar `.knowyou-origin.json`.
- Knowledge Imports skip files with KnowYou export markers.
- If a user explicitly selects the export directory as a local folder import, the connector should warn that this is a KnowYou-generated mirror and keep it disabled by default.
- Imported documents never write back to their external source in this version.

## Scheduling

Daily Memory Export and Knowledge Imports can share lower-level LaunchAgent infrastructure, but they should expose separate schedules and status:

- Daily Memory Export keeps its current `Auto Sync Daily` behavior.
- Knowledge Imports gets its own daily sync setting.
- Manual sync actions should be separate: `Export Daily Memories Now` and `Import Knowledge Now`.

This avoids a user enabling diary export and accidentally enabling API imports, or vice versa.

## Error Handling

Connector errors should be scoped to the connector instance:

- Auth expired.
- Permission denied.
- Rate limited.
- Remote unavailable.
- Local folder missing.
- Unsupported file type.
- Normalization failed.

One connector failure must not block other connectors from syncing. The UI should show last success, last failure, and number of changed documents for each connector.

## Privacy and Security

The first version imports user-selected knowledge sources into local storage. This should be explicit in onboarding or connector setup copy. Credentials and refresh tokens must use Keychain or a similarly secure local store, not UserDefaults.

Imported content should stay local. Existing summarizer or future agent features may read it only through an explicit product pathway. The import system itself should not send content to LLM providers.

The existing privacy filter for captured clipboard/notification events does not automatically apply to user-selected knowledge imports. That boundary should be called out in the UI and docs: imported documents are considered user-approved source material.

## UI Shape

First version can extend the current Sync Memory panel or replace it with a broader Connectors panel. The preferred product shape is:

- A `Connectors` entry in the secondary menu.
- Two sections:
  - `Daily Memory Export`
  - `Knowledge Imports`
- Each connector row shows:
  - Name
  - Direction
  - Status
  - Last synced time
  - Local document count
  - Configure / Sync Now / Disable actions

The UI should avoid presenting Obsidian as one ambiguous connector with two opposite behaviors. It should show `Obsidian Export` and `Obsidian Import` as separate rows or clearly separated sections.

## Testing Strategy

Focused tests should cover:

- Obsidian import skips `KnowYou/Daily Memories`.
- KnowYou export markers are ignored by import connectors.
- Local folder import normalizes Markdown and text files.
- Content hash dedupe avoids unnecessary rewrites.
- Remote ID identity allows changed content to update the same local record.
- Tombstones are recorded for deleted remote documents.
- One connector failure does not fail the whole sync run.
- Existing Sync Memory export tests continue passing.
- Config persistence keeps export and import settings separate.

API connector tests should use protocol-backed fakes rather than real network calls.

## Documentation Updates

When implemented, update:

- `docs/architecture.md`
- `docs/requirements-spec.md`

The docs must change the current product statement that KnowYou is not doing external knowledge-base sync. The updated boundary should say KnowYou supports one-way knowledge imports into local cache, but still does not support bidirectional external knowledge-base editing.

## Open Implementation Notes

- Feishu, Notion, and Google Drive auth flows may require separate implementation phases even though the connector abstraction is designed in the first version.
- Full text search and agent-context retrieval are downstream consumers, not required for the initial connector sync engine.
- PDF and rich document extraction should be added only after the Markdown/text pipeline is stable.
