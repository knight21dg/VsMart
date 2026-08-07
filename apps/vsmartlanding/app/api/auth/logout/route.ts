// POST /api/auth/logout — end the session on this browser and revoke the
// refresh token server-side.

import { backendFetch, clientIp } from "../../../lib/backend";
import { isSameOrigin, jsonError, jsonOk } from "../../../lib/route-utils";
import { clearTokens, readTokens } from "../../../lib/session";

export const dynamic = "force-dynamic";

export async function POST(req: Request) {
  if (!isSameOrigin(req)) return jsonError("Request blocked.", 403);

  const { access, refresh } = await readTokens();

  // Best effort: the cookies go regardless, so a failed revoke can't strand the
  // customer in a half-signed-in state.
  if (access) {
    await backendFetch("/auth/logout", {
      method: "POST",
      body: { refresh },
      accessToken: access,
      forwardedFor: clientIp(req),
    });
  }

  await clearTokens();
  return jsonOk({});
}
