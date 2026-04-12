# Spec: Source Logo Top 100 Coverage

**Date:** 2026-04-12  
**Branch:** feat/source-logo-top-100  
**Status:** Draft

---

## Problem

The reader already shows source logos in the right-side source detail panel, but the curated asset set is too small for real desktop history. Many common global apps still fall back to the generic icon, especially across browsers, collaboration tools, design tools, AI products, and developer tools.

This makes the source panel slower to scan and visually inconsistent once a day includes many different apps.

## Goals

1. Expand branded source coverage to at least 100 curated apps.
2. Prioritize global, high-frequency desktop apps that are likely to appear in notifications or clipboard history.
3. Make brand resolution scalable enough that adding more apps does not require maintaining a giant `switch`.
4. Keep unknown apps safe by falling back to the generic icon.

## Non-Goals

- runtime lookup of installed application icons
- replacing source text labels with logos only
- remote asset fetching at render time
- exhaustive coverage for every possible app name

## Design

### 1. Table-Driven Brand Resolver

The source brand resolver should move to a curated entry table.

Each entry provides:

- stable asset name
- known aliases
- normalized brand identity used in tests and rendering

This keeps the resolver deterministic and easy to extend as coverage grows past dozens of brands.

### 2. Curated Global Coverage

The bundled logo catalog should focus on high-frequency global products across these categories:

- browsers
- office and productivity
- collaboration and communication
- design and content tools
- AI products
- developer tools
- common macOS system apps already visible in desktop history

### 3. Asset Strategy

All logos remain local bundled assets under `Assets.xcassets`.

This preserves:

- no runtime dependency on installed apps
- consistent rendering across machines
- stable test and screenshot output

### 4. Failure Mode

If a source app does not match a curated alias:

- continue rendering the source card
- show the generic fallback icon
- never fail or leave the leading visual slot empty

## Validation

Focused tests must verify:

- browser and Finder mappings
- office and programming app mappings
- high-frequency global notification app mappings
- the expanded top-global coverage set

Build validation must confirm the asset-catalog expansion still compiles into the macOS target.
