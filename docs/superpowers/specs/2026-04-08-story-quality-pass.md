# KnowYou Story Quality Pass Spec

## Overview

The initial story-first reader implementation shipped the UI and data model, but it did not yet meet the product bar for readable daily storytelling. In fallback mode, noisy days still degrade into dozens of one-event loose fragments, which makes the day feel like a relabeled event dump.

This pass focuses on story quality rather than layout:

- keep the existing three-column reader
- keep `DailyStory` and `.story.json`
- improve fallback synthesis so noisy days collapse into a few thematic paragraphs

## Problem

The current fallback path treats many leftover events as isolated fragments. On a real workday this produces:

- too many `Loose Fragments`
- weak grouping of related signals
- too little distinction between references, verification noise, communication, and logistics

This fails the intended acceptance criterion that a noisy day should still read like a story.

## Goal

Make fallback-generated stories feel condensed and readable even when no cloud summarizer is available or structured output parsing fails.

## Requirements

### 1. Loose fragment compression

Fallback generation must not emit one paragraph per leftover event.

Instead, it should:

- group leftover events by theme
- produce a small number of loose-fragment paragraphs
- preserve source event ids for every grouped paragraph

### 2. Theme-aware grouping

Fallback logic should distinguish at least these classes:

- references and links
- verification or instrumentation noise
- logistics or life-admin fragments
- communication or coordination
- general supporting context

### 3. Story readability

Paragraphs should summarize grouped events as a narrative sentence, not just concatenate raw lines verbatim.

### 4. Stable product shape

This pass must not break:

- fixed four-section story structure
- paragraph selection in the reader
- paragraph-to-source mapping
- Markdown export

## Acceptance Criteria

- A noisy fallback day does not explode into dozens of loose-fragment paragraphs
- Verification sentinels are grouped together
- Loose reference links are grouped together
- Story output remains source-linked and deterministic
