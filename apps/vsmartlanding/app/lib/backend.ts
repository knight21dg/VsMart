// Server-side client for the VS Mart backend API.
//
// Every authenticated call from this site goes through Next route handlers
// (`app/api/**`), never straight from the browser: the JWTs live in httpOnly
// cookies so page scripts can't read them, and the API origin never needs the
// landing domain in its CORS allow-list.

/** Public origin — also used by the client-rendered product pages. */
export const PUBLIC_API_BASE_URL =
  process.env.NEXT_PUBLIC_API_BASE_URL || "https://api.thevsmart.com/api/v1";

/**
 * Origin used for server-to-server calls. In Docker the backend sits on the
 * same compose network, so `API_INTERNAL_BASE_URL=http://backend:8000/api/v1`
 * skips the public hairpin through Caddy. Falls back to the public URL.
 */
export const SERVER_API_BASE_URL = (
  process.env.API_INTERNAL_BASE_URL || PUBLIC_API_BASE_URL
).replace(/\/+$/, "");

export interface BackendResult<T> {
  ok: boolean;
  status: number;
  data: T | null;
  /** Pagination/meta block, when the endpoint is a paginated list. */
  meta: Record<string, unknown> | null;
  /** Human-readable message — safe to show the customer. */
  message: string;
  /** Catalog code (`OTP_INVALID`, `TOO_MANY_REQUESTS`, …) when the API sent one. */
  code: string;
  fields: Record<string, string[]>;
}

interface BackendOptions {
  method?: "GET" | "POST" | "PATCH" | "PUT" | "DELETE";
  body?: unknown;
  /** Bearer token for authenticated endpoints. */
  accessToken?: string | null;
  /** Caller's IP, forwarded so the API's per-IP OTP throttle stays per-customer. */
  forwardedFor?: string | null;
  timeoutMs?: number;
}

const DEFAULT_ERROR = "Something went wrong. Please try again.";

/**
 * Best-effort client IP for a request arriving through Caddy.
 *
 * Deliberately the LAST entry of X-Forwarded-For, not the first: Caddy appends
 * the address it actually saw, so everything before it is caller-supplied and
 * spoofable — keying the API's OTP throttle on a value the caller controls
 * would hand out an unlimited OTP allowance.
 */
export function clientIp(req: Request): string | null {
  const xff = req.headers.get("x-forwarded-for");
  if (xff) {
    const hops = xff.split(",").map((h) => h.trim()).filter(Boolean);
    if (hops.length) return hops[hops.length - 1]!;
  }
  return req.headers.get("x-real-ip");
}

/**
 * Call the backend and unwrap its `{success, message, data, meta}` envelope.
 * Never throws — network failures and non-JSON bodies come back as a result
 * with `ok: false` so callers always have one shape to handle.
 */
export async function backendFetch<T>(
  path: string,
  opts: BackendOptions = {}
): Promise<BackendResult<T>> {
  const { method = "GET", body, accessToken, forwardedFor, timeoutMs = 12_000 } = opts;

  const headers: Record<string, string> = { Accept: "application/json" };
  if (body !== undefined) headers["Content-Type"] = "application/json";
  if (accessToken) headers.Authorization = `Bearer ${accessToken}`;
  // Preserve the real client IP: without it every OTP request from this site
  // would share one throttle bucket (the container's address).
  if (forwardedFor) {
    headers["X-Forwarded-For"] = forwardedFor;
    headers["X-Real-IP"] = forwardedFor;
  }

  let res: Response;
  try {
    res = await fetch(`${SERVER_API_BASE_URL}${path}`, {
      method,
      headers,
      body: body === undefined ? undefined : JSON.stringify(body),
      cache: "no-store",
      signal: AbortSignal.timeout(timeoutMs),
    });
  } catch {
    return {
      ok: false,
      status: 0,
      data: null,
      meta: null,
      message: "Couldn't reach VS Mart. Check your connection and try again.",
      code: "NETWORK_ERROR",
      fields: {},
    };
  }

  let json: Record<string, unknown> | null = null;
  try {
    json = (await res.json()) as Record<string, unknown>;
  } catch {
    json = null;
  }

  const error = (json?.error ?? null) as
    | { code?: string; message?: string; fields?: Record<string, string[]> }
    | null;

  if (!res.ok || json?.success === false) {
    return {
      ok: false,
      status: res.status,
      data: null,
      meta: null,
      message:
        (typeof json?.message === "string" && json.message) ||
        error?.message ||
        (res.status === 429
          ? "Too many attempts. Please wait a minute and try again."
          : DEFAULT_ERROR),
      code: (typeof json?.code === "string" && json.code) || error?.code || "",
      fields: error?.fields ?? {},
    };
  }

  return {
    ok: true,
    status: res.status,
    data: (json?.data ?? null) as T | null,
    meta: (json?.meta ?? null) as Record<string, unknown> | null,
    message: typeof json?.message === "string" ? json.message : "",
    code: typeof json?.code === "string" ? json.code : "",
    fields: {},
  };
}
