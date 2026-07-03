import { isNetworkingE2EStoreEnabled, resetNetworkingE2EStore } from "@/src/lib/networking/e2e-store";
import { NextResponse } from "next/server";

export async function POST() {
  if (!isNetworkingE2EStoreEnabled()) {
    return NextResponse.json({ error: "not found" }, { status: 404 });
  }

  const state = resetNetworkingE2EStore();
  return NextResponse.json({
    ok: true,
    counts: {
      people: state.people.length,
      profiles: state.profiles.length,
      memberships: state.memberships.length,
      items: state.items.length
    }
  });
}
