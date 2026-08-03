import { ApiError, type CursorMeta, type Envelope, type PageMeta, type Paged } from "@/lib/types";
import { clearSession, getAccessToken, getRefreshToken, setTokens } from "@/lib/auth/session";

export const API_BASE =
  process.env.NEXT_PUBLIC_API_BASE_URL?.replace(/\/$/, "") || "http://127.0.0.1:8000/api/v1";

// Backend origin (no /api/v1) — media (/media/...) is served at the host root.
const API_ORIGIN = (() => {
  try { return new URL(API_BASE).origin; } catch { return ""; }
})();

type Params = Record<string, string | number | boolean | null | undefined>;

interface RequestOpts {
  method?: string;
  body?: unknown;
  /** multipart upload body; when set, Content-Type is left to the browser. */
  form?: FormData;
  params?: Params;
  auth?: boolean;
  /** retry guard for the 401->refresh flow */
  _retried?: boolean;
}

function buildUrl(path: string, params?: Params): string {
  const url = new URL(`${API_BASE}${path.startsWith("/") ? path : `/${path}`}`);
  if (params) {
    for (const [k, v] of Object.entries(params)) {
      if (v !== undefined && v !== null && v !== "") url.searchParams.set(k, String(v));
    }
  }
  return url.toString();
}

// Single in-flight refresh shared across concurrent 401s.
let refreshInFlight: Promise<boolean> | null = null;

async function doRefresh(): Promise<boolean> {
  const refresh = getRefreshToken();
  if (!refresh) return false;
  try {
    const res = await fetch(buildUrl("/auth/refresh"), {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ refresh }),
    });
    if (!res.ok) return false;
    const env = (await res.json()) as Envelope<{ access_token: string; refresh_token?: string }>;
    const access = env.data?.access_token;
    if (!access) return false;
    setTokens(access, env.data?.refresh_token);
    return true;
  } catch {
    return false;
  }
}

function onAuthFailure() {
  clearSession();
  if (typeof window !== "undefined" && !window.location.pathname.startsWith("/login")) {
    window.location.href = "/login?expired=1";
  }
}

async function rawRequest<T>(path: string, opts: RequestOpts): Promise<Envelope<T>> {
  const { method = "GET", body, form, params, auth = true } = opts;
  const headers: Record<string, string> = { Accept: "application/json" };
  // For multipart, let the browser set Content-Type (with the boundary).
  if (body !== undefined && form === undefined) headers["Content-Type"] = "application/json";
  if (auth) {
    const token = getAccessToken();
    if (token) headers["Authorization"] = `Bearer ${token}`;
  }

  const res = await fetch(buildUrl(path, params), {
    method,
    headers,
    body: form !== undefined ? form : body !== undefined ? JSON.stringify(body) : undefined,
    cache: "no-store",
  });

  // 401 -> attempt a single coordinated refresh, then retry once.
  if (res.status === 401 && auth && !opts._retried) {
    // The promise clears ITSELF once settled. Clearing it here (after `await`)
    // meant the first waiter to resume reset the slot while its siblings were
    // still awaiting, so a 401 arriving in that window kicked off a second,
    // competing refresh — with rotating refresh tokens one of them loses and
    // the whole page's queries fail. React Query doesn't retry 401s, so those
    // panels stayed broken until a manual reload.
    if (!refreshInFlight) {
      refreshInFlight = doRefresh().finally(() => {
        refreshInFlight = null;
      });
    }
    const ok = await refreshInFlight;
    if (ok) return rawRequest<T>(path, { ...opts, _retried: true });
    onAuthFailure();
    throw new ApiError("Your session has expired. Please sign in again.", { code: "unauthenticated", status: 401 });
  }

  let env: Envelope<T> | null = null;
  try {
    env = (await res.json()) as Envelope<T>;
  } catch {
    env = null;
  }

  if (!res.ok || (env && env.success === false)) {
    const fields = env?.error?.fields;
    // Field-level validation detail (e.g. {"price": ["A selling price is required."]})
    // is where the actionable text lives — the top-level message is often the generic
    // catalog line. Surface the specific field messages so the toast is useful.
    const fieldMsg = fields
      ? Object.values(fields).flat().filter(Boolean).join(" ")
      : "";
    const base = env?.error?.message || env?.message || env?.detail;
    const message = fieldMsg || base || `Request failed (${res.status})`;
    throw new ApiError(message, {
      code: env?.error?.code ?? "error",
      status: res.status,
      fields,
    });
  }

  if (!env) throw new ApiError("Empty response from server.", { status: res.status });
  return env;
}

function asPaged<T>(env: Envelope<T[]>): Paged<T> {
  const rows = (env.data ?? []) as T[];
  const meta = env.meta as PageMeta | CursorMeta | undefined;
  return { rows, meta };
}

export const api = {
  /** GET returning the unwrapped `data`. */
  async get<T>(path: string, params?: Params): Promise<T> {
    const env = await rawRequest<T>(path, { method: "GET", params });
    return env.data as T;
  },
  /** GET a list with pagination meta. */
  async getPaged<T>(path: string, params?: Params): Promise<Paged<T>> {
    const env = await rawRequest<T[]>(path, { method: "GET", params });
    return asPaged<T>(env);
  },
  /**
   * GET returning `data` *and* pagination `meta`. Use when the payload is a
   * paginated object rather than a bare array (e.g. the KYC queue, which returns
   * `{applications, summary}` alongside page meta) — `getPaged` assumes an array.
   */
  async getWithMeta<T>(path: string, params?: Params): Promise<{ data: T; meta?: PageMeta | CursorMeta }> {
    const env = await rawRequest<T>(path, { method: "GET", params });
    return { data: env.data as T, meta: env.meta as PageMeta | CursorMeta | undefined };
  },
  async post<T>(path: string, body?: unknown, params?: Params): Promise<T> {
    const env = await rawRequest<T>(path, { method: "POST", body, params });
    return env.data as T;
  },
  async patch<T>(path: string, body?: unknown, params?: Params): Promise<T> {
    const env = await rawRequest<T>(path, { method: "PATCH", body, params });
    return env.data as T;
  },
  async put<T>(path: string, body?: unknown, params?: Params): Promise<T> {
    const env = await rawRequest<T>(path, { method: "PUT", body, params });
    return env.data as T;
  },
  async del<T>(path: string, body?: unknown): Promise<T> {
    const env = await rawRequest<T>(path, { method: "DELETE", body });
    return env.data as T;
  },
  /** Unauthenticated POST (auth endpoints). */
  async postPublic<T>(path: string, body?: unknown): Promise<T> {
    const env = await rawRequest<T>(path, { method: "POST", body, auth: false });
    return env.data as T;
  },
  /** Multipart upload (files). Content-Type/boundary handled by the browser. */
  async upload<T>(path: string, form: FormData): Promise<T> {
    const env = await rawRequest<T>(path, { method: "POST", form });
    return env.data as T;
  },
  /** Absolute URL for a media/asset path (e.g. "/media/..."), served at the host root. */
  assetUrl(path: string): string {
    if (!path) return path;
    if (/^https?:\/\//.test(path)) return path;
    return `${API_ORIGIN}${path.startsWith("/") ? "" : "/"}${path}`;
  },
  buildUrl,
};
