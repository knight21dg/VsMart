// POST /api/auth/profile — set the customer's name (and optional email).
//
// Used twice: once right after a first OTP sign-in to capture a name, and again
// from the account page when the customer edits their details.

import { isSameOrigin, jsonError, jsonOk, readJson } from "../../../lib/route-utils";
import { authedFetch } from "../../../lib/session";
import type { ApiUser } from "../../../lib/types";

export const dynamic = "force-dynamic";

const EMAIL_RE = /^[^\s@]+@[^\s@]+\.[^\s@]{2,}$/;

export async function POST(req: Request) {
  if (!isSameOrigin(req)) return jsonError("Request blocked.", 403);

  const body = await readJson(req);
  const name = String(body?.name ?? "").trim();
  const email = String(body?.email ?? "").trim();

  if (name.length < 2 || name.length > 120) {
    return jsonError("Enter your full name.", 400, {
      fields: { name: ["Enter your full name."] },
    });
  }
  if (email && !EMAIL_RE.test(email)) {
    return jsonError("Enter a valid email address.", 400, {
      fields: { email: ["Enter a valid email address."] },
    });
  }

  const res = await authedFetch<ApiUser>("/auth/register", {
    method: "POST",
    body: { name, email },
  });

  if (!res.ok || !res.data) {
    return jsonError(res.message, res.status === 0 ? 502 : res.status || 400, {
      code: res.code,
      fields: res.fields,
    });
  }

  return jsonOk({ user: res.data });
}
