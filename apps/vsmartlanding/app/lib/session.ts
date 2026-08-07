// Customer session for the website: JWTs in httpOnly cookies, refreshed
// server-side.
//
// Why cookies and not localStorage — this is a public marketing site with
// CMS-authored HTML on the legal pages; an httpOnly cookie keeps the tokens out
// of reach of any script that ends up on the page. SameSite=Lax also means the
// cookies aren't attached to cross-site POSTs, which is what protects the
// mutating `/api/auth/*` route handlers from CSRF.

import { cookies } from "next/headers";

import { backendFetch, type BackendResult } from "./backend";
import type { ApiUser, AuthTokens } from "./types";

const ACCESS_COOKIE = "vsm_at";
const REFRESH_COOKIE = "vsm_rt";

/** Refresh tokens live 30 days on the API (JWT_REFRESH_DAYS). */
const REFRESH_MAX_AGE = 60 * 60 * 24 * 30;
/** Access tokens are short-lived; the cookie outlives the token slightly and
 *  the refresh path covers the gap. */
const ACCESS_MAX_AGE = 60 * 60;

function cookieOptions(maxAge: number) {
  return {
    httpOnly: true,
    sameSite: "lax" as const,
    secure: process.env.NODE_ENV === "production",
    path: "/",
    maxAge,
  };
}

export async function readTokens(): Promise<{
  access: string | null;
  refresh: string | null;
}> {
  const jar = await cookies();
  return {
    access: jar.get(ACCESS_COOKIE)?.value ?? null,
    refresh: jar.get(REFRESH_COOKIE)?.value ?? null,
  };
}

/** True when the browser still holds a refresh token — used only to gate
 *  rendering (`/login` vs `/account`); never as proof of authentication. */
export async function hasSessionCookie(): Promise<boolean> {
  const jar = await cookies();
  return Boolean(jar.get(REFRESH_COOKIE)?.value);
}

/** Persist a fresh token pair. Only valid inside a route handler. */
export async function writeTokens(tokens: AuthTokens): Promise<void> {
  const jar = await cookies();
  jar.set(ACCESS_COOKIE, tokens.access_token, cookieOptions(ACCESS_MAX_AGE));
  if (tokens.refresh_token) {
    jar.set(REFRESH_COOKIE, tokens.refresh_token, cookieOptions(REFRESH_MAX_AGE));
  }
}

/** Drop the session. Only valid inside a route handler. */
export async function clearTokens(): Promise<void> {
  const jar = await cookies();
  jar.set(ACCESS_COOKIE, "", cookieOptions(0));
  jar.set(REFRESH_COOKIE, "", cookieOptions(0));
}

/**
 * Call an authenticated endpoint, transparently refreshing an expired access
 * token once. On an unrecoverable 401 the cookies are cleared so the customer
 * lands back on a clean signed-out site instead of a redirect loop.
 *
 * Must be called from a route handler (it writes cookies).
 */
export async function authedFetch<T>(
  path: string,
  opts: {
    method?: "GET" | "POST" | "PATCH" | "PUT" | "DELETE";
    body?: unknown;
    forwardedFor?: string | null;
  } = {}
): Promise<BackendResult<T>> {
  const { access, refresh } = await readTokens();

  if (!access && !refresh) {
    return {
      ok: false,
      status: 401,
      data: null,
      meta: null,
      message: "Please sign in to continue.",
      code: "AUTH_REQUIRED",
      fields: {},
    };
  }

  if (access) {
    const res = await backendFetch<T>(path, { ...opts, accessToken: access });
    if (res.status !== 401) return res;
  }

  if (!refresh) {
    await clearTokens();
    return {
      ok: false,
      status: 401,
      data: null,
      meta: null,
      message: "Your session expired. Please sign in again.",
      code: "AUTH_REQUIRED",
      fields: {},
    };
  }

  const refreshed = await backendFetch<AuthTokens>("/auth/refresh", {
    method: "POST",
    body: { refresh },
  });

  if (!refreshed.ok || !refreshed.data?.access_token) {
    await clearTokens();
    return {
      ok: false,
      status: 401,
      data: null,
      meta: null,
      message: "Your session expired. Please sign in again.",
      code: "AUTH_REQUIRED",
      fields: {},
    };
  }

  await writeTokens({
    access_token: refreshed.data.access_token,
    // The API does not rotate refresh tokens; keep the one we already hold if
    // the response omits it.
    refresh_token: refreshed.data.refresh_token || refresh,
  });

  return backendFetch<T>(path, { ...opts, accessToken: refreshed.data.access_token });
}

/** The signed-in customer, or `null`. Refreshes the token when needed, so —
 *  like `authedFetch` — this belongs in a route handler, not a server component
 *  (server components may not write cookies). Pages gate on
 *  `hasSessionCookie()` instead. */
export async function currentUser(): Promise<ApiUser | null> {
  const { access, refresh } = await readTokens();
  if (!access && !refresh) return null;
  const res = await authedFetch<ApiUser>("/users/me");
  return res.ok ? res.data : null;
}
