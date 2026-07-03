import { getAgentCandidatesResponse } from "@/src/lib/networking/agent-api";
import type { NextRequest } from "next/server";

export async function GET(request: NextRequest, { params }: { params: Promise<{ communityID: string }> }) {
  const { communityID } = await params;
  return getAgentCandidatesResponse(request, communityID);
}
