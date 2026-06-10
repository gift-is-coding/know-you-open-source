import type { NetworkingContentItem } from "./types";

const authorPriority: Record<NetworkingContentItem["authorType"], number> = {
  human: 0,
  ai: 1
};

export function formatContentAttribution(item: NetworkingContentItem): string {
  const base = `${item.person.displayName} · ${item.profile.label}`;
  return item.authorType === "ai" ? `${base} · AI` : base;
}

export function sortDiscussionItems(items: NetworkingContentItem[]): NetworkingContentItem[] {
  return [...items].sort((left, right) => {
    const authorDelta = authorPriority[left.authorType] - authorPriority[right.authorType];
    if (authorDelta !== 0) {
      return authorDelta;
    }

    return Date.parse(right.createdAt) - Date.parse(left.createdAt);
  });
}
