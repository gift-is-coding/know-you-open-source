import { NextResponse, type NextRequest } from "next/server";
import { isNetworkingE2EStoreEnabled } from "@/src/lib/networking/e2e-store";
import { defaultNetworkingPlatformID, isNetworkingPlatformID } from "@/src/lib/networking/platforms";
import { hasSupabaseEnv } from "@/src/lib/supabase/env";
import { createClient } from "@/src/lib/supabase/server";

export async function POST(request: NextRequest) {
  const body = (await request.json().catch(() => ({}))) as {
    communityID?: string;
    profileID?: string;
  };
  const communityID = isNetworkingPlatformID(body.communityID ?? "") ? body.communityID! : defaultNetworkingPlatformID;

  if (!body.profileID) {
    return NextResponse.json({ error: "profileID is required" }, { status: 400 });
  }

  if (isNetworkingE2EStoreEnabled()) {
    return NextResponse.json({
      membership: {
        communityID,
        profileID: body.profileID,
        status: "active"
      }
    });
  }

  if (!hasSupabaseEnv()) {
    return NextResponse.json({
      membership: {
        communityID,
        profileID: body.profileID,
        status: "active"
      }
    });
  }

  const supabase = await createClient();
  const {
    data: { user }
  } = await supabase.auth.getUser();
  if (!user) {
    return NextResponse.json({ error: "sign-in required" }, { status: 401 });
  }

  const { data: person, error: personError } = await supabase.from("people").select("id").eq("user_id", user.id).single();
  if (personError || !person) {
    return NextResponse.json({ error: "profile owner not found" }, { status: 404 });
  }

  const { data, error } = await supabase
    .from("community_memberships")
    .upsert(
      {
        community_id: communityID,
        person_id: person.id,
        profile_id: body.profileID,
        status: "active"
      },
      { onConflict: "community_id,profile_id" }
    )
    .select("id, community_id, profile_id, status")
    .single();

  if (error) {
    return NextResponse.json({ error: error.message }, { status: 400 });
  }

  return NextResponse.json({ membership: data });
}
