// Shared helpers for the site's own `/api/*` route handlers.

import { NextResponse } from "next/server";

export interface ApiFailure {
  ok: false;
  message: string;
  code?: string;
  fields?: Record<string, string[]>;
}

export function jsonOk<T extends Record<string, unknown>>(data: T, status = 200) {
  return NextResponse.json({ ok: true, ...data }, { status });
}

export function jsonError(
  message: string,
  status = 400,
  extra: { code?: string; fields?: Record<string, string[]> } = {}
) {
  return NextResponse.json<ApiFailure>({ ok: false, message, ...extra }, { status });
}

/**
 * Reject cross-site calls to mutating routes. SameSite=Lax cookies already stop
 * the session riding along on a cross-site POST; this closes the same hole for
 * anything that reaches the route with credentials by another path.
 */
export function isSameOrigin(req: Request): boolean {
  const origin = req.headers.get("origin");
  if (!origin) return true; // same-origin fetches may omit it; no cookie risk
  try {
    return new URL(origin).host === (req.headers.get("host") ?? "");
  } catch {
    return false;
  }
}

/** Parse a JSON body, returning `null` for anything malformed. */
export async function readJson(req: Request): Promise<Record<string, unknown> | null> {
  try {
    const body = await req.json();
    return body && typeof body === "object" ? (body as Record<string, unknown>) : null;
  } catch {
    return null;
  }
}

/**
 * Only allow same-site redirect targets (`/account`, `/products/x`), so a
 * crafted `?next=` can't bounce a freshly signed-in customer off-site.
 */
export function safeNextPath(value: string | null | undefined, fallback = "/account"): string {
  if (!value || !value.startsWith("/") || value.startsWith("//")) return fallback;
  return value;
}
