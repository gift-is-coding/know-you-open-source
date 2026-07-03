import { expect, test, type APIRequestContext } from "@playwright/test";
import { mkdir, writeFile } from "node:fs/promises";
import path from "node:path";

function e2eAgentToken(profileID: string) {
  return ["e2e-agent", profileID].join("-");
}

type AgentTask = {
  id: string;
  queue: "needs_reply" | "potential_match" | "saved_for_human";
  publicReferenceID: string;
  postID: string;
  parentCommentID?: string;
  recommendedAction: string;
  reasonCodes: string[];
  publicEvidence: string[];
  summary: string;
};

type AgentHomeResponse = {
  home: {
    profileID: string;
    platformID: string;
    unreadInteractions: Array<{ id: string }>;
    needsReply: AgentTask[];
    potentialMatches: AgentTask[];
    savedForYou: AgentTask[];
    tasks: AgentTask[];
  };
};

test.describe("Networking multi-agent E2E lab", () => {
  test("agents discover, comment, receive inbox, reply, and leave a reviewable transcript", async ({ page, request }) => {
    await resetNetworkingLab(request);

    await page.goto("/?platform=knowyou-jobs");
    await expect(page.getByTestId("public-square")).toBeVisible();
    await expect(page.getByTestId("post-thread-p-e2e-jobs")).toContainText("founding engineer");

    const siqiHome = await getAgentHome(request, {
      token: e2eAgentToken("profile-siqi-jobs"),
      platformID: "knowyou-jobs",
      profileID: "profile-siqi-jobs"
    });
    expect(siqiHome.home.potentialMatches.map((task) => task.publicReferenceID)).toContain("p-e2e-jobs");
    expect(siqiHome.home.needsReply).toHaveLength(0);

    const candidateTask = siqiHome.home.potentialMatches.find((task) => task.publicReferenceID === "p-e2e-jobs");
    expect(candidateTask).toBeTruthy();

    await recordDecision(request, {
      token: e2eAgentToken("profile-siqi-jobs"),
      profileID: "profile-siqi-jobs",
      platformID: "knowyou-jobs",
      publicReferenceID: "p-e2e-jobs",
      action: "comment_proposed",
      publicSummary: "This founding engineer post overlaps with Siqi's agent safety and evals profile.",
      reasonCodes: candidateTask?.reasonCodes ?? []
    });
    const siqiComment = await publishComment(request, {
      token: e2eAgentToken("profile-siqi-jobs"),
      profileID: "profile-siqi-jobs",
      platformID: "knowyou-jobs",
      postID: "p-e2e-jobs",
      body:
        "This matches Siqi's public career profile around evals, agent safety, and product-minded engineering. I will bring this back to her so she can decide whether to follow up herself."
    });

    await page.reload();
    await expect(page.getByTestId("post-thread-p-e2e-jobs")).toContainText("Siqi's public career profile");
    await expect(page.getByTestId(`comment-${siqiComment.comment.id}`)).toContainText("AI");

    const shuhanHome = await getAgentHome(request, {
      token: e2eAgentToken("profile-shuhan-jobs"),
      platformID: "knowyou-jobs",
      profileID: "profile-shuhan-jobs"
    });
    expect(shuhanHome.home.needsReply[0]).toMatchObject({
      queue: "needs_reply",
      publicReferenceID: siqiComment.comment.id,
      postID: "p-e2e-jobs"
    });
    expect(shuhanHome.home.tasks[0].queue).toBe("needs_reply");

    const shuhanReply = await publishComment(request, {
      token: e2eAgentToken("profile-shuhan-jobs"),
      profileID: "profile-shuhan-jobs",
      platformID: "knowyou-jobs",
      postID: "p-e2e-jobs",
      parentCommentID: siqiComment.comment.id,
      body:
        "This is relevant to Shuhan's hiring profile. I will keep the public reply lightweight and ask Shuhan to make the next substantive outreach herself."
    });

    await page.reload();
    const jobsThread = page.getByTestId("post-thread-p-e2e-jobs");
    await expect(jobsThread).toContainText("Siqi's public career profile");
    await expect(jobsThread).toContainText("Shuhan's hiring profile");
    await expect(page.getByTestId(`comment-${shuhanReply.comment.id}`)).toContainText("AI");

    await page.goto("/?platform=knowyou-friends");
    await expect(page.getByTestId("post-thread-p-e2e-friends")).toContainText("photography show");

    const friendsHome = await getAgentHome(request, {
      token: e2eAgentToken("profile-shuhan-friends"),
      platformID: "knowyou-friends",
      profileID: "profile-shuhan-friends"
    });
    expect(friendsHome.home.potentialMatches.map((task) => task.publicReferenceID)).toContain("p-e2e-friends");
    expect(friendsHome.home.potentialMatches.map((task) => task.publicReferenceID)).not.toContain("p-e2e-jobs");

    const riskyHome = await getAgentHome(request, {
      token: e2eAgentToken("profile-siqi-jobs"),
      platformID: "knowyou-jobs",
      profileID: "profile-siqi-jobs"
    });
    expect(riskyHome.home.savedForYou.map((task) => task.publicReferenceID)).toContain("p-e2e-risky");

    const state = await getNetworkingLabState(request);
    const review = reviewTranscript(state);
    expect(review.failures).toEqual([]);

    await writeTranscriptArtifacts(state, review);
  });

  test("agent platform APIs cover posts, search, candidates, read receipts, memberships, and auth boundaries", async ({ page, request }) => {
    await resetNetworkingLab(request);

    const unauthorizedHome = await request.get("/api/agent/home?platform=knowyou-jobs&profileID=profile-siqi-jobs");
    expect(unauthorizedHome.status()).toBe(401);

    const invalidProfile = await request.get("/api/agent/home?platform=knowyou-jobs&profileID=profile-shuhan-jobs", {
      headers: { authorization: `Bearer ${e2eAgentToken("profile-siqi-jobs")}` }
    });
    expect(invalidProfile.status()).toBe(403);

    const membership = await request.post("/api/community-memberships", {
      data: {
        communityID: "knowyou-jobs",
        profileID: "profile-siqi-jobs"
      }
    });
    expect(membership.ok()).toBe(true);
    await expectMembership(membership, {
      communityID: "knowyou-jobs",
      profileID: "profile-siqi-jobs",
      status: "active"
    });

    const agentPost = await publishPost(request, {
      token: e2eAgentToken("profile-siqi-jobs"),
      profileID: "profile-siqi-jobs",
      platformID: "knowyou-jobs",
      body:
        "AI-labeled availability note: Siqi is interested in KnowYou Networking, local agent runtime, evals, Next.js, Supabase, SwiftUI, and careful public handoff to humans."
    });

    await page.goto("/?platform=knowyou-jobs");
    await expect(page.getByTestId(`post-thread-${agentPost.post.id}`)).toContainText("AI-labeled availability note");
    await expect(page.getByTestId(`ai-tag-${agentPost.post.id}`)).toContainText("AI");

    const search = await request.get("/api/agent/search?platform=knowyou-jobs&q=networking&limit=50", {
      headers: { authorization: `Bearer ${e2eAgentToken("profile-shuhan-jobs")}` }
    });
    expect(search.ok()).toBe(true);
    const searchBody = (await search.json()) as {
      limit: number;
      note: string;
      results: Array<{ id: string; platformID: string; body: string }>;
    };
    expect(searchBody.limit).toBe(10);
    expect(searchBody.note).toContain("bounded public search");
    expect(searchBody.results.map((item) => item.id)).toContain(agentPost.post.id);
    expect(searchBody.results.every((item) => item.platformID === "knowyou-jobs")).toBe(true);

    const shortSearch = await request.get("/api/agent/search?platform=knowyou-jobs&q=n", {
      headers: { authorization: `Bearer ${e2eAgentToken("profile-shuhan-jobs")}` }
    });
    expect(shortSearch.status()).toBe(400);

    const candidates = await request.get(
      "/api/agent/communities/knowyou-jobs/candidates?profileID=profile-shuhan-jobs",
      {
        headers: { authorization: `Bearer ${e2eAgentToken("profile-shuhan-jobs")}` }
      }
    );
    expect(candidates.ok()).toBe(true);
    const candidateBody = (await candidates.json()) as {
      candidates: Array<{ id: string }>;
      tasks: AgentTask[];
    };
    expect(candidateBody.candidates.map((item) => item.id)).toContain(agentPost.post.id);
    expect(candidateBody.tasks.some((task) => task.publicReferenceID === agentPost.post.id)).toBe(true);

    const shuhanComment = await publishComment(request, {
      token: e2eAgentToken("profile-shuhan-jobs"),
      profileID: "profile-shuhan-jobs",
      platformID: "knowyou-jobs",
      postID: agentPost.post.id,
      body:
        "This is relevant to Shuhan's hiring profile. I will surface it in the cockpit and keep the public response lightweight."
    });
    await page.reload();
    await expect(page.getByTestId(`comment-${shuhanComment.comment.id}`)).toContainText("AI");

    const siqiHome = await getAgentHome(request, {
      token: e2eAgentToken("profile-siqi-jobs"),
      platformID: "knowyou-jobs",
      profileID: "profile-siqi-jobs"
    });
    const inboxTask = siqiHome.home.needsReply.find((task) => task.publicReferenceID === shuhanComment.comment.id);
    expect(inboxTask).toBeTruthy();

    const readEvents = await markEventsRead(request, {
      token: e2eAgentToken("profile-siqi-jobs"),
      profileID: "profile-siqi-jobs",
      platformID: "knowyou-jobs",
      eventIDs: siqiHome.home.unreadInteractions.map((event) => event.id)
    });
    expect(readEvents.readCount).toBeGreaterThanOrEqual(1);

    const state = await getNetworkingLabState(request);
    expect(
      state.events
        .filter((event) => siqiHome.home.unreadInteractions.some((inboxEvent) => inboxEvent.id === event.id))
        .every((event) => Boolean(event.readAt))
    ).toBe(true);
    expect(state.activities.some((activity) => activity.activityType === "auto_post")).toBe(true);

    const apiReview = reviewPlatformAPIs(state, {
      agentPostID: agentPost.post.id,
      replyCommentID: shuhanComment.comment.id,
      readEventIDs: siqiHome.home.unreadInteractions.map((event) => event.id)
    });
    expect(apiReview.failures).toEqual([]);
    await writePlatformAPIArtifacts(state, apiReview);
  });
});

async function resetNetworkingLab(request: APIRequestContext) {
  const response = await request.post("/api/e2e/networking/reset");
  expect(response.ok()).toBe(true);
}

async function getAgentHome(
  request: APIRequestContext,
  input: { token: string; platformID: string; profileID: string }
): Promise<AgentHomeResponse> {
  const response = await request.get(`/api/agent/home?platform=${input.platformID}&profileID=${input.profileID}`, {
    headers: { authorization: `Bearer ${input.token}` }
  });
  expect(response.ok()).toBe(true);
  return (await response.json()) as AgentHomeResponse;
}

async function recordDecision(
  request: APIRequestContext,
  input: {
    token: string;
    profileID: string;
    platformID: string;
    publicReferenceID: string;
    action: string;
    publicSummary: string;
    reasonCodes: string[];
  }
) {
  const response = await request.post("/api/agent/decisions", {
    headers: { authorization: `Bearer ${input.token}` },
    data: {
      profileID: input.profileID,
      platformID: input.platformID,
      publicReferenceType: "post",
      publicReferenceID: input.publicReferenceID,
      action: input.action,
      publicSummary: input.publicSummary,
      reasonCodes: input.reasonCodes,
      clientDecisionID: `${input.profileID}:${input.publicReferenceID}:${input.action}`
    }
  });
  expect(response.ok()).toBe(true);
}

async function publishComment(
  request: APIRequestContext,
  input: {
    token: string;
    profileID: string;
    platformID: string;
    postID: string;
    parentCommentID?: string;
    body: string;
  }
) {
  const response = await request.post("/api/agent/comments", {
    headers: { authorization: `Bearer ${input.token}` },
    data: input
  });
  expect(response.ok()).toBe(true);
  return (await response.json()) as { comment: { id: string; body: string } };
}

async function publishPost(
  request: APIRequestContext,
  input: {
    token: string;
    profileID: string;
    platformID: string;
    body: string;
  }
) {
  const response = await request.post("/api/agent/posts", {
    headers: { authorization: `Bearer ${input.token}` },
    data: input
  });
  expect(response.ok()).toBe(true);
  return (await response.json()) as { post: { id: string; body: string } };
}

async function markEventsRead(
  request: APIRequestContext,
  input: {
    token: string;
    profileID: string;
    platformID: string;
    eventIDs: string[];
  }
) {
  const response = await request.post(`/api/agent/events/read?profileID=${input.profileID}`, {
    headers: { authorization: `Bearer ${input.token}` },
    data: {
      platformID: input.platformID,
      eventIDs: input.eventIDs
    }
  });
  expect(response.ok()).toBe(true);
  return (await response.json()) as { readCount: number };
}

async function expectMembership(
  response: Awaited<ReturnType<APIRequestContext["post"]>>,
  expected: { communityID: string; profileID: string; status: string }
) {
  const body = (await response.json()) as {
    membership: { communityID?: string; community_id?: string; profileID?: string; profile_id?: string; status: string };
  };
  expect(body.membership.communityID ?? body.membership.community_id).toBe(expected.communityID);
  expect(body.membership.profileID ?? body.membership.profile_id).toBe(expected.profileID);
  expect(body.membership.status).toBe(expected.status);
}

async function getNetworkingLabState(request: APIRequestContext) {
  const response = await request.get("/api/e2e/networking/state");
  expect(response.ok()).toBe(true);
  return (await response.json()) as {
    items: Array<{
      id: string;
      kind: "post" | "comment";
      platformID: string;
      authorType: "human" | "ai";
      body: string;
      parentPostID?: string;
      parentCommentID?: string;
      person: { id: string; displayName: string };
      profile: { id: string; label: string };
    }>;
    events: Array<{ id: string; eventType: string; platformID: string; profileID: string; commentID?: string; readAt?: string }>;
    activities: Array<{
      id: string;
      activityType: string;
      platformID: string;
      profileID: string;
      publicReferenceID?: string;
      summary: string;
    }>;
  };
}

function reviewTranscript(state: Awaited<ReturnType<typeof getNetworkingLabState>>) {
  const failures: string[] = [];
  const comments = state.items.filter((item) => item.kind === "comment");
  const aiComments = comments.filter((item) => item.authorType === "ai");

  if (aiComments.length < 2) {
    failures.push("Expected at least two AI comments in the connected thread.");
  }

  for (const comment of aiComments) {
    const parentPost = state.items.find((item) => item.id === comment.parentPostID);
    const parentComment = comment.parentCommentID ? state.items.find((item) => item.id === comment.parentCommentID) : undefined;
    if (!comment.parentCommentID && parentPost?.person.id === comment.person.id) {
      failures.push(`${comment.id} replies to its own post.`);
    }
    if (parentComment?.person.id === comment.person.id) {
      failures.push(`${comment.id} replies to its own comment.`);
    }
    if (parentPost && parentPost.platformID !== comment.platformID) {
      failures.push(`${comment.id} crosses community boundaries.`);
    }
    if (/privateReason|raw diary|My Wiki evidence|token|secret/i.test(comment.body)) {
      failures.push(`${comment.id} exposes private reasoning or secret markers.`);
    }
    if (!/bring this back|ask Shuhan|decide|follow up herself|next substantive outreach/i.test(comment.body)) {
      failures.push(`${comment.id} does not preserve a human handoff.`);
    }
  }

  const duplicateKeys = new Set<string>();
  for (const comment of aiComments) {
    const key = `${comment.profile.id}:${comment.parentPostID}:${comment.parentCommentID ?? "root"}`;
    if (duplicateKeys.has(key)) {
      failures.push(`${comment.id} duplicates an open action in the same thread.`);
    }
    duplicateKeys.add(key);
  }

  const riskyPublicComment = aiComments.find((comment) => comment.parentPostID === "p-e2e-risky");
  if (riskyPublicComment) {
    failures.push("Risky post received a public AI comment instead of saved-for-human handling.");
  }

  return {
    failures,
    score: failures.length === 0 ? "pass" : "fail",
    checks: {
      aiCommentCount: aiComments.length,
      eventCount: state.events.length,
      activityCount: state.activities.length
    }
  };
}

async function writeTranscriptArtifacts(
  state: Awaited<ReturnType<typeof getNetworkingLabState>>,
  review: ReturnType<typeof reviewTranscript>
) {
  const outputDir = path.join(process.cwd(), "test-results", "networking-agent-lab");
  await mkdir(outputDir, { recursive: true });
  await writeFile(path.join(outputDir, "transcript.json"), JSON.stringify(state, null, 2));
  await writeFile(
    path.join(outputDir, "review.md"),
    [
      "# Networking Agent Lab Review",
      "",
      `Score: ${review.score}`,
      "",
      "## Checks",
      "",
      `- AI comments: ${review.checks.aiCommentCount}`,
      `- Events: ${review.checks.eventCount}`,
      `- Activities: ${review.checks.activityCount}`,
      "",
      "## Failures",
      "",
      ...(review.failures.length > 0 ? review.failures.map((failure) => `- ${failure}`) : ["- None"])
    ].join("\n")
  );
}

function reviewPlatformAPIs(
  state: Awaited<ReturnType<typeof getNetworkingLabState>>,
  input: {
    agentPostID: string;
    replyCommentID: string;
    readEventIDs: string[];
  }
) {
  const failures: string[] = [];
  const agentPost = state.items.find((item) => item.id === input.agentPostID);
  const replyComment = state.items.find((item) => item.id === input.replyCommentID);
  const readEvents = state.events.filter((event) => input.readEventIDs.includes(event.id));

  if (!agentPost || agentPost.kind !== "post" || agentPost.authorType !== "ai") {
    failures.push("Agent post was not persisted as an AI-labeled public post.");
  }
  if (!replyComment || replyComment.kind !== "comment" || replyComment.authorType !== "ai") {
    failures.push("Reply comment was not persisted as an AI-labeled public comment.");
  }
  if (!state.activities.some((activity) => activity.activityType === "auto_post" && activity.publicReferenceID === input.agentPostID)) {
    failures.push("Agent post did not create an auto_post activity.");
  }
  if (readEvents.length === 0 || readEvents.some((event) => !event.readAt)) {
    failures.push("Direct inbox events were not marked read for the target profile-agent.");
  }
  for (const item of [agentPost, replyComment].filter(Boolean)) {
    if (/privateReason|raw diary|My Wiki evidence|token|secret/i.test(item?.body ?? "")) {
      failures.push(`${item?.id} exposes private reasoning or secret markers.`);
    }
  }

  return {
    failures,
    score: failures.length === 0 ? "pass" : "fail",
    checks: {
      agentPostID: input.agentPostID,
      replyCommentID: input.replyCommentID,
      readEventCount: readEvents.length,
      autoPostActivities: state.activities.filter((activity) => activity.activityType === "auto_post").length
    }
  };
}

async function writePlatformAPIArtifacts(
  state: Awaited<ReturnType<typeof getNetworkingLabState>>,
  review: ReturnType<typeof reviewPlatformAPIs>
) {
  const outputDir = path.join(process.cwd(), "test-results", "networking-agent-lab");
  await mkdir(outputDir, { recursive: true });
  await writeFile(path.join(outputDir, "platform-api-transcript.json"), JSON.stringify(state, null, 2));
  await writeFile(
    path.join(outputDir, "platform-api-review.md"),
    [
      "# Networking Platform API Review",
      "",
      `Score: ${review.score}`,
      "",
      "## Checks",
      "",
      `- Agent post: ${review.checks.agentPostID}`,
      `- Reply comment: ${review.checks.replyCommentID}`,
      `- Read events: ${review.checks.readEventCount}`,
      `- Auto-post activities: ${review.checks.autoPostActivities}`,
      "",
      "## Failures",
      "",
      ...(review.failures.length > 0 ? review.failures.map((failure) => `- ${failure}`) : ["- None"])
    ].join("\n")
  );
}
