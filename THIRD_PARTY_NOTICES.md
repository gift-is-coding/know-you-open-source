# Third-Party Software

This file is an inventory aid, not a replacement for the license text shipped by each dependency. Release maintainers must verify that packaged artifacts include every notice and source-offer obligation required by their licenses.

## Bundled source

### LLM Wiki

- Upstream: [nashsu/llm_wiki](https://github.com/nashsu/llm_wiki)
- Local path: `ThirdParty/llm_wiki`
- Declared license: GNU General Public License v3.0
- License text: `ThirdParty/llm_wiki/LICENSE`

KnowYou carries and modifies this source to build the bundled MyWikiRunner. The root-project license and distribution model must be reviewed for compatibility with the GPL-3.0 obligations before a public source or binary release.

### PDFium binaries

The repository currently contains prebuilt PDFium libraries for macOS, Linux, and Windows under `ThirdParty/llm_wiki/src-tauri/pdfium`. Source comments reference the `bblanchon/pdfium-binaries` distribution, but the checked-in directory does not contain a pinned upstream version, checksums, source URL, license, or third-party notices.

This is an open-source release blocker. Before distribution, either:

1. replace the checked-in binaries with a reproducible fetch/build process that pins the source and verifies checksums; or
2. add exact provenance, version, license text, and all required notices for each binary.

## Swift packages

The checked-in `Package.resolved` currently pins these Swift Package Manager dependencies:

- [GRDB.swift 7.10.0](https://github.com/groue/GRDB.swift), MIT License
- [Sparkle 2.9.2](https://github.com/sparkle-project/Sparkle), permissive license plus the third-party notices included in Sparkle's `LICENSE`

Release artifacts or a generated software bill of materials must preserve their license texts and notices.

## JavaScript and Rust packages

`NetworkingWeb`, `ThirdParty/llm_wiki`, and `Tools/MyWikiMCP` use lock files for package resolution. Their transitive licenses are not reproduced in this file. A release process should generate and archive an SBOM/license report from the exact lock files used to build the artifact.
