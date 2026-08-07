// POST /api/auth/otp/verify — exchange the texted code for a session.
//
// On success the JWT pair is written to httpOnly cookies and only the user
// object is returned; tokens are never handed to page scripts.

import { backendFetch, clientIp } from "../../../../lib/backend";
import { normalizeIndianMobile } from "../../../../lib/phone";
import { isSameOrigin, jsonError, jsonOk, readJson } from "../../../../lib/route-utils";
import { writeTokens } from "../../../../lib/session";
import type { OtpVerifyResponse } from "../../../../lib/types";

export const dynamic = "force-dynamic";

export async function POST(req: Request) {
  if (!isSameOrigin(req)) return jsonError("Request blocked.", 403);

  const body = await readJson(req);
  const phone = normalizeIndianMobile(String(body?.phone ?? ""));
  const otp = String(body?.otp ?? "").trim();
  const verificationId = String(body?.verificationId ?? "").trim();

  if (!phone) return jsonError("Enter a valid 10-digit mobile number.", 400);
  if (!verificationId) {
    return jsonError("That code has expired. Please request a new one.", 400, {
      code: "OTP_EXPIRED",
    });
  }
  if (!/^\d{4,8}$/.test(otp)) {
    return jsonError("Enter the 6-digit code we texted you.", 400, {
      code: "OTP_INVALID",
    });
  }

  const res = await backendFetch<OtpVerifyResponse>("/auth/otp/verify", {
    method: "POST",
    body: { phone, otp, verification_id: verificationId },
    forwardedFor: clientIp(req),
  });

  if (!res.ok || !res.data?.access_token || !res.data.user) {
    return jsonError(res.message, res.status === 0 ? 502 : res.status || 400, {
      code: res.code,
    });
  }

  await writeTokens(res.data);

  const user = res.data.user;
  return jsonOk({
    user,
    // A returning customer who never completed their profile still needs the
    // name step, so don't rely on `is_new_user` alone.
    needsProfile: Boolean(res.data.is_new_user) || !user.name?.trim(),
  });
}
