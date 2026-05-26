# Source Document Reading Simplification Design

## Summary

Source reading uses the sidebar file tree as the only document index. Connector roots and folders expand or collapse in the sidebar; Markdown/TXT leaves open a single document preview in the main pane.

## Requirements

- Do not render a second document list in the main pane.
- Do not show `Refresh`, `Configure`, scan status, linked-source explanations, or path cards while reading a source document.
- Keep manual `Refresh` on the `Add Source` management page only.
- Opening a connector root must not auto-select the first document.
- Refreshing a source while a connector root is selected may update the sidebar tree, but must not open a document.
- Refreshing while a document is selected must keep that document selected and reload its Markdown content.
- Source document preview must render Markdown syntax as rich text and hide YAML frontmatter from the body.

## Design

`KnowledgeSourceContentView` becomes a single-purpose document preview. It receives the selected connector and selected document Markdown, strips frontmatter, and renders through the shared SwiftUI Markdown renderer. Empty state copy points users back to the left source tree.

`AppState.selectKnowledgeConnector` becomes a root selection with no document side effect: it refreshes the tree and clears selected document content. `AppState.selectKnowledgeDocument` remains the only path that loads Markdown text.

The `NavigationSplitView` detail pane remains useful for diary source references, but source pages use a blank zero-width detail pane so no extra explanation/index column appears beside source documents.
