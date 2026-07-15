# Bundled PDFium binaries

This directory contains prebuilt PDFium libraries used by the bundled
`llm_wiki` Tauri application. They were distributed by
[`bblanchon/pdfium-binaries`](https://github.com/bblanchon/pdfium-binaries).

The files do not all come from the same weekly release. Their provenance was
reconstructed by comparing each checked-in binary's SHA-256 digest with the
corresponding official GitHub release assets:

| File | Platform | Upstream release | PDFium version |
| --- | --- | --- | --- |
| `libpdfium.so` | Linux x86_64 | `chromium/7802` | `149.0.7802.0` |
| `libpdfium-arm64.so` | Linux arm64 | `chromium/7811` | `149.0.7811.0` |
| `libpdfium.dylib` | macOS arm64 | `chromium/7789` | `149.0.7789.0` |
| `pdfium.dll` | Windows x86_64 | `chromium/7789` | `149.0.7789.0` |

`SHA256SUMS` records the checked-in binary digests. Verify the local files with:

```sh
shasum -a 256 -c SHA256SUMS
```

The matching upstream archives were also verified before this provenance
record was added:

| Archive | Release | SHA-256 |
| --- | --- | --- |
| `pdfium-linux-x64.tgz` | `chromium/7802` | `d11b735c0c559503738611744517ee07b3ef6f288345e260de7e633a9a3eef72` |
| `pdfium-linux-arm64.tgz` | `chromium/7811` | `1682079aae24d73fcfb4f1ae115dd7b661780ad31ad43c8804da2d518dc546e8` |
| `pdfium-mac-arm64.tgz` | `chromium/7789` | `3110873c852db65a4e603423671db3fc455e4c70cf3a4895b53bc4141f74111b` |
| `pdfium-win-x64.tgz` | `chromium/7789` | `5d93c5b5677bc38c5b13f5f2314fd4e0cd6c79b311797a2545644a10ce94180d` |

`LICENSE` and `licenses/` are the license materials shipped in the official
Linux x86_64 `chromium/7802` archive. The upstream package's license set was
also compared with the matching `chromium/7811` and `chromium/7789` archives.
The substantive license texts are the same; platform archives differ only in
line endings and, for one PDFium notice, comment formatting. The FreeType
notice's ISO-8859-1 copyright character is normalized to UTF-8 in this tree;
non-semantic trailing whitespace is also normalized.

For a future dependency update, replace all four binaries from one release,
refresh the license material from that release, update the digests, and run the
PDF ingestion tests on every supported platform.
