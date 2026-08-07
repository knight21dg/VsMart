// POST /api/auth/otp/send — texts a login code to an Indian mobile number.
//
// Thin proxy over the API's `/auth/otp/send` (throttled there at 5/min per IP,
// which is why the caller's address is forwarded). The response deliberately
// carries no hint about whether the number already has an account: an account
// is created on first successful verification.

import { backendFetch, clientIp } from "../../../../lib/backend";
import { normalizeIndianMobile } from "../../../../lib/phone";
import { isSameOrigin, jsonError, jsonOk, readJson } from "../../../../lib/route-utils";

export const dynamic = "force-dynamic";

export async function POST(req: Request) {
  if (!isSameOrigin(req)) return jsonError("Request blocked.", 403);

  const body = await readJson(req);
  const phone = normalizeIndianMobile(String(body?.phone ?? ""));
  if (!phone) {
    return jsonError("Enter a valid 10-digit mobile number.", 400, {
      code: "INVALID_PHONE",
    });
  }

  const res = await backendFetch<{ verification_id: string }>("/auth/otp/send", {
    method: "POST",
    body: { phone },
    forwardedFor: clientIp(req),
  });

  if (!res.ok || !res.data?.verification_id) {
    return jsonError(res.message, res.status === 0 ? 502 : res.status, {
      code: res.code,
    });
  }

  // The normalised number goes back to the client so the verify step sends
  // exactly what the OTP was issued against.
  return jsonOk({ verificationId: res.data.verification_id, phone });
}
