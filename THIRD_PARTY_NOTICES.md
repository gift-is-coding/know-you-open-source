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

The repository contains prebuilt PDFium libraries for macOS, Linux, and Windows under `ThirdParty/llm_wiki/src-tauri/pdfium`. They come from the MIT-licensed [`bblanchon/pdfium-binaries`](https://github.com/bblanchon/pdfium-binaries) distribution and contain PDFium and its transitive native dependencies under their respective licenses.

The exact upstream release, binary and archive SHA-256 digests, reproduction instructions, distributor license, and bundled dependency notices are recorded in `ThirdParty/llm_wiki/src-tauri/pdfium/README.md`, `SHA256SUMS`, `LICENSE`, and `licenses/`.

The existing files span three weekly upstream releases. This is now documented and verifiable, but maintainers should converge all platforms on one pinned release during the next PDFium update.

## Swift packages

The checked-in `Package.resolved` currently pins these Swift Package Manager dependencies:

- [GRDB.swift 7.10.0](https://github.com/groue/GRDB.swift), MIT License
- [Sparkle 2.9.2](https://github.com/sparkle-project/Sparkle), permissive license plus the third-party notices included in Sparkle's `LICENSE`

Release artifacts or a generated software bill of materials must preserve their license texts and notices.

## JavaScript and Rust packages

`NetworkingWeb`, `ThirdParty/llm_wiki`, and `Tools/MyWikiMCP` use lock files for package resolution. Their transitive licenses are not reproduced in this file. A release process should generate and archive an SBOM/license report from the exact lock files used to build the artifact.
