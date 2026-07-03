import { createAgentPostResponse } from "@/src/lib/networking/agent-api";
import type { NextRequest } from "next/server";

export async function POST(request: NextRequest) {
  return createAgentPostResponse(request);
}
