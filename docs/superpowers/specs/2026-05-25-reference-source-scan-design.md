# Reference Source Scan Design

## Summary

KnowYou treats Add Source entries as local file references. Local Folder and Obsidian Vault stay in their original folders; KnowYou only scans, indexes, and previews readable Markdown/TXT files. Prompt-backed platforms such as Feishu, Notion, and Google Drive are also local references: Codex or Cloud Code may write files into KnowYou's `ExternalSources/<platform>/` directory, and KnowYou scans that directory.

KnowYou does not copy source documents into a second local content cache for file-backed sources. It may store lightweight metadata and SQLite rows so the sidebar can show the file tree quickly.

## Product Boundaries

- Local Folder and Obsidian are linked sources, not import/sync jobs.
- Feishu, Notion, and Google Drive prompt flows only generate instructions for an external automation job.
- Remote authorization, token storage, CLI setup, downloading, and scheduled copy jobs happen outside KnowYou.
- KnowYou scans local `.md`, `.markdown`, and `.txt` files under configured source roots.
- UI copy uses Link, Scan, Refresh, and Reference wording instead of Import or Sync for Add Source document sources.
- Daily Memory Export remains a separate export capability and is not mixed into Add Source scanning.

## Data Model

Existing `ImportedKnowledgeDocument` rows remain the compatibility layer for sidebar and preview data, but file-backed documents use reference storage:

- `sourcePath`: absolute path to the original local file.
- `localContentPath`: same absolute path as `sourcePath`.
- `localMetadataPath`: KnowYou-managed metadata JSON path.
- `originKind`: local reference type such as `local-file`, `obsidian-vault`, or `feishu-local-file`.

For file-backed snapshots, KnowYou writes metadata only. It does not write a copied `content.md`.

## UI Behavior

- Add Source cards for Local Folder and Obsidian show `Linked` when configured.
- Feishu/Notion/Google Drive show `Generate Prompt` before setup, `Needs first scan` when their local directory exists but has no readable documents, and `Linked` when readable files exist.
- Existing `Sync Now` actions for Add Source become `Refresh`.
- Empty source pages explain that KnowYou reads linked local files and does not copy or modify source files.
- Sidebar roots stay flat and parallel: Add Source, My Diary, Obsidian Vault, Feishu Docs, Notion, Google Drive.

## Scan Behavior

- Manual Refresh scans enabled local file-backed sources and updates the SQLite document index.
- Launch-time scan runs once for enabled linked sources so files already written under `ExternalSources/<platform>/` appear without requiring the user to discover Refresh first.
- Scanning preserves existing Obsidian loop protection by skipping KnowYou daily export files and `knowyou_export: daily_memory` markers.
- Deleted/missing files are marked deleted from the visible index.

## Acceptance Criteria

- Linking a local folder or Obsidian source does not create copied Markdown content under `KnowledgeSources`.
- Feishu/Notion/Google Drive sources can be configured without credentials and are scanned only from their local `ExternalSources` folder.
- Clicking Refresh after files appear in an external source folder makes them visible in the sidebar and preview.
- Preview reads the original file path for file-backed documents.
- Add Source and source detail UI no longer claim documents are copied into KnowYou local storage.
