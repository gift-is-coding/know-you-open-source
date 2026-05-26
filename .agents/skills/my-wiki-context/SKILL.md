---
name: my-wiki-context
description: Use when an agent needs private KnowYou My Wiki context before answering a question, planning a task, or making a recommendation.
---

# My Wiki Context

Use this skill when an agent needs private KnowYou My Wiki context before answering a question, planning a task, or making a recommendation. The caller may provide a paragraph of background rather than keywords.

## Workflow

1. Call the `knowyou-my-wiki` MCP tool `my_wiki_context` before answering when the task may depend on the user's prior notes, wiki concepts, source summaries, projects, or personal knowledge.
2. Pass the full task/background paragraph as `background`. Do not reduce it to only one keyword unless the user explicitly gives a keyword-only search.
3. Start with `maxItems: 6` and `characterBudget: 6000`. Increase only when the first context pack is too thin.
4. Use `queryPlan.terms`, `queryPlan.phrases`, `items[*].matchedTerms`, and `items[*].score` to judge whether the retrieved context is actually relevant.
5. Cite returned pages using `items[*].citation.relativePath` when you use the information.
6. If an item is highly relevant but the excerpt is too short, call `my_wiki_read_page` with that item's `citation.relativePath`.

## Boundaries

- Treat My Wiki output as private local context, not public web evidence.
- Do not ask the MCP server to write or edit wiki content.
- Do not read arbitrary paths. Only use relative paths returned by `my_wiki_context`.
- If `items` is empty or matched terms look weak, say that My Wiki did not provide strong context and continue with that limitation.

## Example

Background:

```text
I am answering whether an AIDC project should prefer HVDC distribution and liquid cooling. I need the user's existing My Wiki context, not generic web search.
```

Call:

```json
{
  "background": "I am answering whether an AIDC project should prefer HVDC distribution and liquid cooling. I need the user's existing My Wiki context, not generic web search.",
  "maxItems": 6,
  "characterBudget": 6000
}
```
