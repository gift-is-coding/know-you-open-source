# My Wiki Source Catalog Design

## Summary

My Wiki needs a durable source selection layer between KnowYou's available documents and llm_wiki's ingest pipeline. Today the Source Library is mostly an import basket: files copied into `raw/sources` are available to ingest, and indexed state is inferred from matching pages under `wiki/sources`.

The new Source Catalog turns this into a governed document catalog. It lists KnowYou diaries and external source documents in their natural hierarchy, lets the user persistently include or exclude sources from My Wiki, and only processes included sources that are new or changed.

## Goals

- Show a My Wiki source catalog that includes KnowYou diary Markdown and external source documents.
- Preserve source hierarchy. A source root can contain folders and nested files, and the UI must not flatten that structure away.
- Persist the user's `included in My Wiki` choice for each source.
- Include new diary sources by default, while still allowing the user to exclude any diary.
- Leave new external sources excluded by default until the user includes them.
- Mark processing state clearly: not included, pending, indexed, changed, excluded indexed, failed.
- Skip already indexed sources when content has not changed, even when they remain included.
- Never delete old wiki output merely because a source is excluded.
- Pass directory context to llm_wiki so nested sources keep useful provenance.

## Non Goals

- Do not build automatic cleanup of entity or concept pages when a source is excluded.
- Do not edit external source files from the My Wiki catalog.
- Do not replace the existing Other Source connector management page.
- Do not require cloud APIs for this feature. The catalog works from already scanned local document metadata.
- Do not silently ingest every external source just because it appears in the catalog.

## Product Model

All available documents are candidates. Included documents are My Wiki sources. Changed included documents are pending re-processing.

Each source has two related but separate states:

- Inclusion state: whether the user has granted My Wiki permission to use the source.
- Processing state: whether the source needs ingest based on prior success and content hash.

The long-term default rules are:

- New diary source: included by default.
- Existing diary source: preserve the user's previous include or exclude choice.
- New external source: not included by default.
- Existing external source: preserve the user's previous include or exclude choice.
- Excluding a previously indexed source does not delete `wiki/sources` or derived entity/concept pages.
- Including a previously indexed unchanged source does not force re-processing.

## Catalog Hierarchy

The Source Catalog must mirror the hierarchy users already see outside My Wiki.

Top-level roots include:

- My Diary
- Local Folder connector instances
- Obsidian connector instances
- Feishu Docs connector instances
- Notion connector instances
- Google Drive connector instances
- Manually imported My Wiki source folders

Each root can contain folders and files. Local Folder, Obsidian, Google Drive, and manually imported source folders must preserve their nested paths. Feishu and Notion should preserve their available document tree when metadata can represent it; otherwise they may start as grouped document lists under the connector root.

Directory rows are selectable control nodes:

- Including a directory includes visible descendant files by default.
- Excluding a directory excludes visible descendant files by default.
- A child file can override the directory default.
- A directory shows a mixed state when descendants are partly included.
- Bulk actions operate on the current filtered visible tree, not on hidden rows.

The catalog should retain relative paths such as `Projects/AI/notes.md`. Those paths are used both for display and as folder context for ingest.

## UI Behavior

The existing My Wiki `Source Library` sheet becomes a catalog manager instead of a pure file import sheet.

The main layout should support:

- A hierarchical source tree or outline.
- Search by title, filename, path, and connector name.
- Filters for source root, source type, and processing state.
- A row checkbox for inclusion.
- Directory rows with tri-state inclusion.
- Counts for all, included, pending, changed, and failed sources.
- Bulk actions for include visible, exclude visible, and invert visible.
- Open source and open generated source summary actions where available.

Each source file row shows:

- Title or file name.
- Relative path.
- Source root or connector name.
- Last source update time when available.
- Inclusion checkbox.
- Processing badge.
- Optional generated summary link.

Processing badges:

- `Not included`: candidate document, not used by My Wiki.
- `Pending`: included but never successfully indexed.
- `Indexed`: included and indexed with matching hash.
- `Changed`: included and content changed since the last successful index.
- `Excluded, indexed`: currently excluded but has previous My Wiki output.
- `Failed`: last processing attempt failed.

## Data Model

Add a My Wiki-specific source catalog state separate from the external source connector config. It can live in the My Wiki project folder so the selection travels with the project:

`<projectRoot>/.knowyou/source-catalog.json`

The persisted state records user choices and processing checkpoints. It should not duplicate full document content.

Suggested fields per source identity:

- `sourceID`: stable identity derived from source kind, connector instance, remote ID, or diary day key.
- `sourceKind`: diary, external-document, manual-file.
- `connectorInstanceID`: optional.
- `connectorID`: optional.
- `displayTitle`.
- `relativePath`.
- `sourcePath`: absolute source path when local.
- `sourceURL`: optional remote URL.
- `contentHash`.
- `remoteUpdatedAt`: optional.
- `included`.
- `includedDefault`: diary or external default used when first discovered.
- `lastIndexedHash`: optional.
- `lastIndexedAt`: optional.
- `lastIngestError`: optional.
- `rawSourcePath`: project-relative path under `raw/sources` when materialized.
- `wikiSummaryPath`: project-relative path under `wiki/sources` when known.

Directory inclusion can be represented either as explicit directory records or derived from child records. The implementation should keep enough state to support directory-level include/exclude and child overrides without losing user intent when new files appear under an included directory.

## Source Identity

Stable identity matters more than filename.

- Diary source identity: `diary:<dayKey>`.
- Imported knowledge document identity: existing `ImportedKnowledgeDocument.id`.
- Manual source file identity: project-relative raw source path or a stable path hash.

When materializing files into `raw/sources`, filenames must avoid collisions while preserving enough path context to trace back to the source. A nested file such as `Projects/AI/notes.md` may materialize to a deterministic path under `raw/sources/Projects/AI/notes.md` instead of flattening to `notes.md`.

## Pipeline Behavior

`Update My Wiki` changes from "sync diaries, then ingest recent raw sources" to:

1. Refresh the catalog from diary files, imported knowledge document rows, and manual My Wiki sources.
2. Apply default inclusion only to newly discovered sources.
3. Preserve existing user choices.
4. Materialize included sources into `raw/sources` with stable hierarchical paths.
5. Build an ingest plan containing only included sources whose `contentHash` differs from `lastIndexedHash`, or whose summary is missing.
6. Run llm_wiki only for planned sources.
7. On success, update `lastIndexedHash`, `lastIndexedAt`, `wikiSummaryPath`, and clear prior error.
8. On failure, record `lastIngestError` without changing the prior successful checkpoint.

The headless llm_wiki runner should accept an explicit source list or manifest. It should not decide the eligible source set by scanning every Markdown file under `raw/sources`.

The manifest should include folder context for each source so llm_wiki can preserve provenance:

- `sourcePath`: project-relative raw source path.
- `sourceID`: stable source identity.
- `displayTitle`.
- `folderContext`: relative folder path or connector tree path.
- `sourceKind`.

## Exclusion Semantics

Exclusion means "do not use this source in future My Wiki processing." It does not mean "delete generated knowledge."

If a source is excluded after prior indexing:

- Keep `wiki/sources/<summary>.md`.
- Keep entity and concept pages that may have been generated from it.
- Show the row as `Excluded, indexed`.
- Exclude it from future ingest plans.

If the user later includes it again:

- If the content hash still matches `lastIndexedHash`, show `Indexed` and skip re-processing.
- If the content hash differs, show `Changed` and process it on the next update.

## Error Handling

Catalog refresh should degrade per source root. One broken connector or missing folder should not hide diaries or other connectors.

The UI should show source-root errors near the affected root. File-level ingest errors should stay attached to source rows so the user can retry after fixing the source or prompt.

If catalog state cannot be decoded, KnowYou should preserve the unreadable file as a backup and rebuild defaults, rather than deleting the user's project data.

## Privacy And Safety

External sources remain opt-in for My Wiki. Showing a source in the catalog does not grant LLM processing permission. The include checkbox is the permission boundary.

The materialization step must not write back to external source files. It only writes into the My Wiki project folder.

Path handling must prevent traversal outside the project when writing `raw/sources`, reading `wiki/sources`, or passing source paths to the MCP bridge.

## Testing Strategy

Focused tests should cover:

- New diary sources default included.
- Existing diary include/exclude choices are preserved.
- New external sources default excluded.
- Included unchanged sources are skipped after successful indexing.
- Changed included sources enter the ingest plan.
- Excluded indexed sources keep prior summary paths but are omitted from ingest.
- Nested source paths are preserved in catalog rows and materialized raw source paths.
- Directory include/exclude applies to descendants and supports child overrides.
- Mixed directory state is reported when descendants differ.
- llm_wiki headless ingest accepts an explicit manifest and does not scan all raw sources when a manifest is provided.
- Failed per-source ingest records an error without overwriting the last successful checkpoint.

Full verification before completion must include the targeted Swift tests, targeted llm_wiki tests, then the repository-required Xcode test and build commands.

## Acceptance Criteria

- Opening Source Library shows a persistent hierarchical catalog, not only copied raw files.
- My Diary files appear included by default and can be unchecked.
- External source files appear unchecked by default and can be included.
- Folder rows support include, exclude, and mixed descendant state.
- Update My Wiki processes only included pending or changed sources.
- Previously indexed unchanged sources are not reprocessed.
- Excluding an indexed source does not delete old wiki output.
- Nested source folder context is preserved through materialization and ingest.
