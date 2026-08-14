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

/** Human text for a transport/status failure the backend didn't describe itself.
 * Only used as a fallback — a coded envelope message always wins. */
const STATUS_MESSAGE: Record<number, string> = {
  400: "The request was invalid. Please check the details and try again.",
  401: "Your session has expired. Please sign in again.",
  403: "You don't have permission to perform this action.",
  404: "That record no longer exists — it may have already been removed.",
  405: "That action isn't allowed on this record.",
  409: "This conflicts with the record's current state. Refresh and try again.",
  413: "That file is too large to upload.",
  415: "That file type isn't supported.",
  422: "Some of the values entered aren't valid. Please correct them and try again.",
  429: "Too many requests. Please wait a moment and try again.",
  500: "The server ran into a problem. Please try again.",
  502: "The server is unreachable right now. Please try again in a moment.",
  503: "The service is temporarily unavailable. Please try again shortly.",
  504: "The server took too long to respond. Please try again.",
};

function statusMessage(status: number): string {
  return (
    STATUS_MESSAGE[status] ||
    (status >= 500
      ? "The server ran into a problem. Please try again."
      : "That request couldn't be completed. Please try again.")
  );
}

/**
 * Read a response body without ever throwing.
 *
 * A successful DELETE returns `204 No Content`, and per the fetch spec a 204 is
 * a *null-body status* — `res.json()` rejects on it no matter what the server
 * sent. The old code let that rejection collapse the envelope to `null` and then
 * threw "Empty response from server." on a request that had in fact SUCCEEDED,
 * which meant React Query's `onSuccess` never ran: no toast, no
 * `invalidateQueries`, the confirm dialog stayed open and the deleted row only
 * disappeared after a manual page reload. Every delete in the console failed
 * this way.
 *
 * Returns `null` for "no body" (a legitimate success shape) and keeps the raw
 * text so a non-JSON error page (a Caddy 502, an HTML login redirect) can still
 * be reported as its status rather than as a JSON parse error.
 */
async function readBody<T>(res: Response): Promise<{ env: Envelope<T> | null; raw: string }> {
  // 204/205/304 carry no body by definition — don't even read them.
  if (res.status === 204 || res.status === 205 || res.status === 304) return { env: null, raw: "" };
  let raw = "";
  try {
    raw = await res.text();
  } catch {
    return { env: null, raw: "" };
  }
  if (!raw.trim()) return { env: null, raw: "" };
  try {
    const parsed = JSON.parse(raw);
    // Anything that isn't the standard envelope (a bare array/scalar from a
    // legacy endpoint) is treated as the payload itself rather than discarded.
    if (parsed && typeof parsed === "object" && !Array.isArray(parsed) && "success" in parsed) {
      return { env: parsed as Envelope<T>, raw };
    }
    return { env: { success: true, data: parsed as T }, raw };
  } catch {
    return { env: null, raw };
  }
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
    // Through readBody like every other response: the last place that called
    // res.json() directly. A refresh that came back with an empty or non-JSON
    // body (a proxy 200, an HTML error page) threw inside this try and was
    // reported as "refresh failed" — signing the operator out mid-task.
    const { env } = await readBody<{ access_token: string; refresh_token?: string }>(res);
    const access = env?.data?.access_token;
    if (!access) return false;
    setTokens(access, env?.data?.refresh_token);
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

  let res: Response;
  try {
    res = await fetch(buildUrl(path, params), {
      method,
      headers,
      body: form !== undefined ? form : body !== undefined ? JSON.stringify(body) : undefined,
      cache: "no-store",
    });
  } catch {
    // fetch only rejects on a transport failure (offline, DNS, CORS, abort) —
    // surface that as a typed, human-readable error instead of letting a raw
    // TypeError("Failed to fetch") reach a toast.
    throw new ApiError(
      "Can't reach the server. Check your connection and try again.",
      { code: "network_error", status: 0 },
    );
  }

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

  const { env } = await readBody<T>(res);

  if (!res.ok || (env && env.success === false)) {
    const fields = env?.error?.fields;
    // Field-level validation detail (e.g. {"price": ["A selling price is required."]})
    // is where the actionable text lives — the top-level message is often the generic
    // catalog line. Surface the specific field messages so the toast is useful.
    const fieldMsg = fields
      ? Object.values(fields).flat().filter(Boolean).join(" ")
      : "";
    const base = env?.error?.message || env?.message || env?.detail;
    // Fall back to a plain-English line for the status rather than leaking
    // "Request failed (502)" or an HTML error page into the UI.
    const message = fieldMsg || base || statusMessage(res.status);
    throw new ApiError(message, {
      code: env?.error?.code ?? (res.status === 0 ? "network_error" : "error"),
      status: res.status,
      fields,
    });
  }

  // 2xx with no body (204 No Content, or an empty 200) IS a success. Synthesise
  // the envelope so callers and React Query see a resolved mutation.
  return env ?? ({ success: true, message: "", data: undefined } as Envelope<T>);
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
  /**
   * DELETE returning `data` *and* the server's coded message.
   *
   * A "Delete" is not always an erase: anything with trading history comes back
   * as `RECORD_DEACTIVATED` and the row stays in the list. The caller has to be
   * able to say which of the two happened instead of hard-coding "Deleted.".
   */
  async delWithMessage<T>(path: string, body?: unknown): Promise<{ data: T; message: string }> {
    const env = await rawRequest<T>(path, { method: "DELETE", body });
    return { data: env.data as T, message: env.message ?? "" };
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
