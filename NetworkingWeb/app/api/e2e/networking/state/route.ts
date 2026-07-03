import { isNetworkingE2EStoreEnabled, readNetworkingE2EState } from "@/src/lib/networking/e2e-store";
import { NextResponse } from "next/server";

export async function GET() {
  if (!isNetworkingE2EStoreEnabled()) {
    return NextResponse.json({ error: "not found" }, { status: 404 });
  }

  const state = readNetworkingE2EState();
  return NextResponse.json({
    people: state.people,
    profiles: state.profiles,
    memberships: state.memberships,
    items: state.items,
    events: state.events,
    activities: state.activities
  });
}
