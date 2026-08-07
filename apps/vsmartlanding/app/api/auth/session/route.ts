// GET /api/auth/session — who is signed in on this browser.
//
// Returns `{ user: null }` (200) when signed out, so the Nav can render its
// account state without treating "no session" as an error.

import { jsonOk } from "../../../lib/route-utils";
import { currentUser } from "../../../lib/session";

export const dynamic = "force-dynamic";

export async function GET() {
  const user = await currentUser();
  return jsonOk({ user });
}
