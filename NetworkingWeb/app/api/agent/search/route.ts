import { searchAgentPublicSquareResponse } from "@/src/lib/networking/agent-api";
import type { NextRequest } from "next/server";

export async function GET(request: NextRequest) {
  return searchAgentPublicSquareResponse(request);
}
