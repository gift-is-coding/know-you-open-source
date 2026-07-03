import { NextResponse, type NextRequest } from "next/server";
import { buildAgentHome, runAgentHeartbeat, type NetworkingAgentRecommendedAction } from "./agent-home";
import {
  buildNetworkingE2EAgentHome,
  createNetworkingE2EAgentComment,
  createNetworkingE2EAgentPost,
  getNetworkingE2EItems,
  isNetworkingE2EStoreEnabled,
  markNetworkingE2EEventsRead,
  readNetworkingE2EState,
  recordNetworkingE2EDecision
} from "./e2e-store";
import { getLocalDemoNetwork } from "./local-demo-state";
import { defaultNetworkingPlatformID, isNetworkingPlatformID } from "./platforms";
import { hasSupabaseEnv } from "@/src/lib/supabase/env";
import { createClient } from "@/src/lib/supabase/server";

export function getAgentBearerToken(request: NextRequest) {
  const value = request.headers.get("authorization") ?? "";
  const match = value.match(/^Bearer\s+(.+)$/i);
  return match?.[1]?.trim() ?? "";
}

export function unauthorizedAgentResponse() {
  return NextResponse.json({ error: "agent bearer token required" }, { status: 401 });
}

export function unsupportedSupabaseAgentReadResponse() {
  return NextResponse.json(
    {
      error: "agent read RPC is not configured",
      detail: "This endpoint is fully available in local demo mode. Supabase write endpoints use token-validated RPC."
    },
    { status: 501 }
  );
}

export function localAgentContext(platformID = defaultNetworkingPlatformID) {
  const network = getLocalDemoNetwork();
  const normalizedPlatformID = isNetworkingPlatformID(platformID) ? platformID : defaultNetworkingPlatformID;
  const membership = network.memberships.find((item) => item.communityID === normalizedPlatformID && item.status === "active") ?? network.memberships[0];
  const person = network.people.find((item) => item.id === membership.personID) ?? network.people[0];
  const profile = network.profiles.find((item) => item.id === membership.profileID) ?? network.profiles[0];

  return { network, membership, person, profile };
}

export async function getAgentHomeResponse(request: NextRequest) {
  const token = getAgentBearerToken(request);
  if (!token) {
    return unauthorizedAgentResponse();
  }

  const platformID = request.nextUrl.searchParams.get("platform") ?? defaultNetworkingPlatformID;
  const profileID = request.nextUrl.searchParams.get("profileID") ?? undefined;
  if (isNetworkingE2EStoreEnabled()) {
    try {
      const home = buildNetworkingE2EAgentHome({ token, platformID, profileID });
      return NextResponse.json({ home });
    } catch (error) {
      return NextResponse.json({ error: error instanceof Error ? error.message : "agent home failed" }, { status: 403 });
    }
  }

  if (hasSupabaseEnv()) {
    const supabase = await createClient();
    const { data, error } = await supabase.rpc("networking_agent_home", {
      p_token: token,
      p_platform_id: platformID
    });
    if (error) {
      return NextResponse.json({ error: error.message }, { status: 400 });
    }
    return NextResponse.json({ home: data });
  }

  const { network, membership, person, profile } = localAgentContext(platformID);
  const home = buildAgentHome({
    now: new Date(),
    person,
    profile,
    membership,
    items: network.items,
    events: network.events,
    recentActivities: network.activities
  });

  return NextResponse.json({ home });
}

export async function getAgentCandidatesResponse(request: NextRequest, communityID: string) {
  const token = getAgentBearerToken(request);
  if (!token) {
    return unauthorizedAgentResponse();
  }

  if (isNetworkingE2EStoreEnabled()) {
    try {
      const home = buildNetworkingE2EAgentHome({
        token,
        platformID: communityID,
        profileID: request.nextUrl.searchParams.get("profileID") ?? undefined
      });
      return NextResponse.json({ candidates: home.candidatePosts, tasks: home.tasks });
    } catch (error) {
      return NextResponse.json({ error: error instanceof Error ? error.message : "agent candidates failed" }, { status: 403 });
    }
  }

  if (hasSupabaseEnv()) {
    const since = request.nextUrl.searchParams.get("since");
    const limit = Number(request.nextUrl.searchParams.get("limit") ?? "20");
    const supabase = await createClient();
    const { data, error } = await supabase.rpc("networking_agent_home", {
      p_token: token,
      p_platform_id: communityID
    });
    if (error) {
      return NextResponse.json({ error: error.message }, { status: 400 });
    }

    const candidates = Array.isArray(data?.candidatePosts) ? data.candidatePosts : [];
    const filteredCandidates = since
      ? candidates.filter((candidate: { createdAt?: string }) => !candidate.createdAt || candidate.createdAt > since)
      : candidates;

    return NextResponse.json({
      candidates: filteredCandidates.slice(0, Number.isFinite(limit) ? Math.max(1, Math.min(limit, 50)) : 20),
      tasks: Array.isArray(data?.tasks) ? data.tasks : []
    });
  }

  const { network, membership, person, profile } = localAgentContext(communityID);
  const home = buildAgentHome({
    now: new Date(),
    person,
    profile,
    membership,
    items: network.items,
    events: network.events,
    recentActivities: network.activities
  });

  return NextResponse.json({ candidates: home.candidatePosts, tasks: home.tasks });
}

export async function createAgentCommentResponse(request: NextRequest) {
  const token = getAgentBearerToken(request);
  if (!token) {
    return unauthorizedAgentResponse();
  }

  const body = (await request.json().catch(() => ({}))) as {
    postID?: string;
    parentCommentID?: string | null;
    profileID?: string;
    platformID?: string;
    body?: string;
    clientDecisionID?: string;
  };

  if (!body.postID || !body.profileID || !body.platformID || !body.body) {
    return NextResponse.json({ error: "postID, profileID, platformID, and body are required" }, { status: 400 });
  }

  if (isNetworkingE2EStoreEnabled()) {
    try {
      const result = createNetworkingE2EAgentComment({
        token,
        profileID: body.profileID,
        platformID: body.platformID,
        postID: body.postID,
        parentCommentID: body.parentCommentID ?? null,
        body: body.body,
        clientDecisionID: body.clientDecisionID
      });
      return NextResponse.json({
        comment: result.comment,
        activities: [result.activity],
        events: readNetworkingE2EState().events
      });
    } catch (error) {
      return NextResponse.json({ error: error instanceof Error ? error.message : "agent comment failed" }, { status: 403 });
    }
  }

  if (!hasSupabaseEnv()) {
    const { network, membership, person, profile } = localAgentContext(body.platformID);
    const result = runAgentHeartbeat({
      now: new Date(),
      person,
      profile,
      membership,
      items: network.items,
      events: network.events,
      recentActivities: network.activities
    });
    const comment = result.items.find((item) => item.authorType === "ai" && item.parentPostID === body.postID);
    return NextResponse.json({ comment, activities: result.activities, events: result.events });
  }

  const supabase = await createClient();
  const { data, error } = await supabase.rpc("networking_agent_create_comment", {
    p_token: token,
    p_target_post_id: body.postID,
    p_parent_comment_id: body.parentCommentID ?? null,
    p_target_profile_id: body.profileID,
    p_platform_id: body.platformID,
    p_body: body.body,
    p_client_decision_id: body.clientDecisionID ?? `${body.profileID}:${body.postID}:${body.parentCommentID ?? "root"}`
  });

  if (error) {
    return NextResponse.json({ error: error.message }, { status: 400 });
  }

  return NextResponse.json({ commentID: data });
}

export async function createAgentPostResponse(request: NextRequest) {
  const token = getAgentBearerToken(request);
  if (!token) {
    return unauthorizedAgentResponse();
  }

  const body = (await request.json().catch(() => ({}))) as {
    profileID?: string;
    platformID?: string;
    body?: string;
  };

  if (!body.profileID || !body.platformID || !body.body) {
    return NextResponse.json({ error: "profileID, platformID, and body are required" }, { status: 400 });
  }

  if (isNetworkingE2EStoreEnabled()) {
    try {
      const result = createNetworkingE2EAgentPost({
        token,
        profileID: body.profileID,
        platformID: body.platformID,
        body: body.body
      });
      return NextResponse.json({ post: result.post, activities: [result.activity] });
    } catch (error) {
      return NextResponse.json({ error: error instanceof Error ? error.message : "agent post failed" }, { status: 403 });
    }
  }

  if (!hasSupabaseEnv()) {
    return NextResponse.json({ error: "local demo does not auto-create agent posts in V1" }, { status: 405 });
  }

  const supabase = await createClient();
  const { data, error } = await supabase.rpc("networking_agent_create_post", {
    p_token: token,
    p_target_profile_id: body.profileID,
    p_platform_id: body.platformID,
    p_body: body.body
  });

  if (error) {
    return NextResponse.json({ error: error.message }, { status: 400 });
  }

  return NextResponse.json({ postID: data });
}

export async function recordAgentDecisionResponse(request: NextRequest) {
  const token = getAgentBearerToken(request);
  if (!token) {
    return unauthorizedAgentResponse();
  }

  const body = (await request.json().catch(() => ({}))) as {
    profileID?: string;
    platformID?: string;
    publicReferenceType?: "post" | "comment";
    publicReferenceID?: string;
    action?: NetworkingAgentRecommendedAction;
    publicSummary?: string;
    reasonCodes?: string[];
    clientDecisionID?: string;
  };

  if (!body.profileID || !body.platformID || !body.publicReferenceType || !body.publicReferenceID || !body.action) {
    return NextResponse.json(
      { error: "profileID, platformID, publicReferenceType, publicReferenceID, and action are required" },
      { status: 400 }
    );
  }

  const allowedActions: NetworkingAgentRecommendedAction[] = [
    "skip",
    "save_for_human",
    "express_interest",
    "comment_proposed",
    "comment",
    "reply"
  ];
  if (!allowedActions.includes(body.action)) {
    return NextResponse.json({ error: "unsupported agent decision action" }, { status: 400 });
  }

  if (isNetworkingE2EStoreEnabled()) {
    try {
      const decision = recordNetworkingE2EDecision({
        token,
        profileID: body.profileID,
        platformID: body.platformID,
        publicReferenceType: body.publicReferenceType,
        publicReferenceID: body.publicReferenceID,
        action: body.action,
        publicSummary: body.publicSummary ?? "",
        reasonCodes: body.reasonCodes ?? [],
        clientDecisionID: body.clientDecisionID
      });
      return NextResponse.json({
        decision: {
          id: decision.id,
          platformID: decision.platformID,
          personID: decision.personID,
          profileID: decision.profileID,
          action: body.action,
          publicReferenceType: decision.publicReferenceType,
          publicReferenceID: decision.publicReferenceID,
          publicSummary: decision.summary,
          reasonCodes: body.reasonCodes ?? [],
          note: "E2E decision recorded; private KnowYou reasoning stays local"
        }
      });
    } catch (error) {
      return NextResponse.json({ error: error instanceof Error ? error.message : "agent decision failed" }, { status: 403 });
    }
  }

  if (!hasSupabaseEnv()) {
    const { membership, person, profile } = localAgentContext(body.platformID);
    return NextResponse.json({
      decision: {
        id: body.clientDecisionID ?? `${body.profileID}:${body.publicReferenceID}:${body.action}`,
        platformID: body.platformID,
        personID: person.id,
        profileID: profile.id,
        membershipStatus: membership.status,
        action: body.action,
        publicReferenceType: body.publicReferenceType,
        publicReferenceID: body.publicReferenceID,
        publicSummary: body.publicSummary ?? "",
        reasonCodes: body.reasonCodes ?? [],
        note: "local demo decision recorded; private KnowYou reasoning stays local"
      }
    });
  }

  const supabase = await createClient();
  const { data, error } = await supabase.rpc("networking_agent_record_decision", {
    p_token: token,
    p_target_profile_id: body.profileID,
    p_platform_id: body.platformID,
    p_public_reference_type: body.publicReferenceType,
    p_public_reference_id: body.publicReferenceID,
    p_action: body.action,
    p_public_summary: body.publicSummary ?? "",
    p_reason_codes: body.reasonCodes ?? [],
    p_client_decision_id: body.clientDecisionID ?? `${body.profileID}:${body.publicReferenceID}:${body.action}`
  });

  if (error) {
    return NextResponse.json({ error: error.message }, { status: 400 });
  }

  return NextResponse.json({ decisionID: data });
}

export async function searchAgentPublicSquareResponse(request: NextRequest) {
  const token = getAgentBearerToken(request);
  if (!token) {
    return unauthorizedAgentResponse();
  }

  const platformID = request.nextUrl.searchParams.get("platform") ?? defaultNetworkingPlatformID;
  const query = (request.nextUrl.searchParams.get("q") ?? "").trim().toLowerCase();
  const limit = boundedSearchLimit(request.nextUrl.searchParams.get("limit"));

  if (query.length < 2) {
    return NextResponse.json({ error: "q must contain at least 2 characters for bounded public search" }, { status: 400 });
  }

  if (isNetworkingE2EStoreEnabled()) {
    const results = getNetworkingE2EItems(platformID)
      .filter((item) => [item.body, item.topic, item.profile.summary].join(" ").toLowerCase().includes(query))
      .slice(0, limit)
      .map((item) => ({
        id: item.id,
        kind: item.kind,
        platformID: item.platformID,
        authorType: item.authorType,
        body: item.body,
        profileID: item.profile.id,
        personID: item.person.id,
        createdAt: item.createdAt
      }));

    return NextResponse.json({
      results,
      limit,
      note: "bounded public search; not a full-site crawl"
    });
  }

  if (hasSupabaseEnv()) {
    return NextResponse.json(
      {
        error: "bounded public search RPC is not configured",
        detail: "Use /api/agent/home candidate queues for background agent work; search is only for explicit user-directed lookup."
      },
      { status: 501 }
    );
  }

  const { network } = localAgentContext(platformID);
  const results = network.items
    .filter((item) => item.platformID === platformID)
    .filter((item) => [item.body, item.topic, item.profile.summary].join(" ").toLowerCase().includes(query))
    .slice(0, limit)
    .map((item) => ({
      id: item.id,
      kind: item.kind,
      platformID: item.platformID,
      authorType: item.authorType,
      body: item.body,
      profileID: item.profile.id,
      personID: item.person.id,
      createdAt: item.createdAt
    }));

  return NextResponse.json({
    results,
    limit,
    note: "bounded public search; not a full-site crawl"
  });
}

export async function markAgentEventsReadResponse(request: NextRequest) {
  const token = getAgentBearerToken(request);
  if (!token) {
    return unauthorizedAgentResponse();
  }

  const body = (await request.json().catch(() => ({}))) as {
    eventIDs?: string[];
    platformID?: string;
  };

  if (!Array.isArray(body.eventIDs) || body.eventIDs.length === 0 || !body.platformID) {
    return NextResponse.json({ error: "eventIDs and platformID are required" }, { status: 400 });
  }

  if (isNetworkingE2EStoreEnabled()) {
    try {
      const readCount = markNetworkingE2EEventsRead({
        token,
        profileID: request.nextUrl.searchParams.get("profileID") ?? undefined,
        platformID: body.platformID,
        eventIDs: body.eventIDs
      });
      return NextResponse.json({ readCount });
    } catch (error) {
      return NextResponse.json({ error: error instanceof Error ? error.message : "mark events read failed" }, { status: 403 });
    }
  }

  if (hasSupabaseEnv()) {
    const supabase = await createClient();
    const { data, error } = await supabase.rpc("networking_agent_mark_events_read", {
      p_token: token,
      p_platform_id: body.platformID,
      p_event_ids: body.eventIDs
    });
    if (error) {
      return NextResponse.json({ error: error.message }, { status: 400 });
    }
    return NextResponse.json({ readCount: data });
  }

  return NextResponse.json({ readCount: body.eventIDs.length });
}

function boundedSearchLimit(value: string | null) {
  const parsed = Number(value ?? "10");
  if (!Number.isFinite(parsed)) {
    return 10;
  }
  return Math.max(1, Math.min(10, Math.floor(parsed)));
}
