import { describe, expect, it } from "vitest";
import {
  formatContentAttribution,
  sortDiscussionItems
} from "./content-ordering";
import type { NetworkingContentItem } from "./types";

const base = {
  person: { id: "person-tianfu", displayName: "Tianfu", handle: "tianfu" },
  profile: { id: "profile-hiring", label: "Hiring", slug: "hiring" }
} satisfies Pick<NetworkingContentItem, "person" | "profile">;

describe("networking content ordering", () => {
  it("prioritizes human content before AI content inside the same discussion", () => {
    const items: NetworkingContentItem[] = [
      {
        id: "ai-comment",
        kind: "comment",
        platformID: "knowyou-jobs",
        authorType: "ai",
        body: "This candidate may fit the founding role.",
        createdAt: "2026-05-27T09:01:00.000Z",
        ...base
      },
      {
        id: "human-comment",
        kind: "comment",
        platformID: "knowyou-jobs",
        authorType: "human",
        body: "I am interested in this role.",
        createdAt: "2026-05-27T09:02:00.000Z",
        ...base
      }
    ];

    expect(sortDiscussionItems(items).map((item) => item.id)).toEqual([
      "human-comment",
      "ai-comment"
    ]);
  });

  it("marks AI content as person plus profile plus AI without marking human content", () => {
    expect(
      formatContentAttribution({
        id: "ai-post",
        kind: "post",
        platformID: "knowyou-jobs",
        authorType: "ai",
        body: "I found three relevant candidates.",
        createdAt: "2026-05-27T09:00:00.000Z",
        ...base
      })
    ).toEqual("Tianfu · Hiring · AI");

    expect(
      formatContentAttribution({
        id: "human-post",
        kind: "post",
        platformID: "knowyou-jobs",
        authorType: "human",
        body: "Hiring a full-stack engineer.",
        createdAt: "2026-05-27T09:00:00.000Z",
        ...base
      })
    ).toEqual("Tianfu · Hiring");
  });

  it("keeps post and comment bodies as free text without requiring intent fields", () => {
    const item: NetworkingContentItem = {
      id: "free-text",
      kind: "post",
      platformID: "knowyou-jobs",
      authorType: "human",
      body: "Thinking out loud: I need someone who can build context-native products with taste.",
      createdAt: "2026-05-27T09:00:00.000Z",
      ...base
    };

    expect(item.body).toContain("Thinking out loud");
    expect("intent" in item).toBe(false);
  });
});
