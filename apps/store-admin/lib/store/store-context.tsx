"use client";

import * as React from "react";
import { useQuery } from "@tanstack/react-query";
import { jwtDecode } from "jwt-decode";
import { api } from "@/lib/api/client";
import { getAccessToken } from "@/lib/auth/session";
import { ApiError, type StoreMe } from "@/lib/types";

interface StoreState {
  me: StoreMe | null;
  loading: boolean;
  error: unknown;
  /**
   * The server actually REJECTED this session (401/403) — as opposed to being
   * unreachable. Only this may end the session; see the console layout.
   */
  authRejected: boolean;
  /** `me` came from the local cache because the server is unreachable. */
  stale: boolean;
  /** True if the signed-in staff member holds the given permission key. */
  hasPerm: (key: string) => boolean;
  /** True if they hold ANY of the keys (used to show a module). */
  hasAny: (keys: string[]) => boolean;
  isManager: boolean;
  refetch: () => void;
}

const StoreContext = React.createContext<StoreState | null>(null);

/**
 * Last successful /store/me, mirrored to localStorage.
 *
 * The till runs offline by design (IndexedDB catalog + sale outbox) but the
 * service worker deliberately never caches `/api/**`, so a page reload with no
 * network used to leave the panel with no identity at all — and the console
 * layout read that as "not a member of this store" and logged the cashier out,
 * mid-queue, with no way back in until the network returned. The identity is
 * already trusted locally (the JWT lives in the same storage), so keeping a copy
 * costs nothing and keeps the till alive.
 */
const ME_KEY = "vsstore.me";

/**
 * The cache is stamped with the user id it was written for and only ever handed
 * back for that same identity. Without this, a cashier signing out and the next
 * one signing in on a flaky connection would be served the PREVIOUS cashier's
 * store and permissions — the fallback must never outlive its session.
 */
interface CachedMe {
  userId: string;
  me: StoreMe;
}

function readCachedMe(): StoreMe | null {
  if (typeof window === "undefined") return null;
  const me = meFromToken();
  if (!me) return null;
  try {
    const raw = localStorage.getItem(ME_KEY);
    if (!raw) return null;
    const entry = JSON.parse(raw) as CachedMe;
    return entry?.userId === me ? entry.me : null;
  } catch {
    return null;
  }
}

function writeCachedMe(me: StoreMe) {
  if (typeof window === "undefined") return;
  try {
    localStorage.setItem(ME_KEY, JSON.stringify({ userId: me.user.id, me } satisfies CachedMe));
  } catch {
    /* private mode / quota — the cache is an optimisation, never a requirement */
  }
}

/** The user id inside the current access token, or null without one. */
function meFromToken(): string | null {
  const token = getAccessToken();
  if (!token) return null;
  try {
    const { user_id } = jwtDecode<{ user_id?: string | number }>(token);
    return user_id != null ? String(user_id) : null;
  } catch {
    return null;
  }
}

/** Drop the cached identity. Call alongside `clearSession()` on a real sign-out
 * or a genuine auth rejection, so the next user never inherits this one's store. */
export function clearCachedMe() {
  if (typeof window !== "undefined") localStorage.removeItem(ME_KEY);
}

/** A rejection by the server, distinct from the server being unreachable.
 * `fetch` throws a bare TypeError when the network is down, and the API client
 * only ever raises `ApiError` once it has a real HTTP status to report. */
export function isAuthRejection(err: unknown): boolean {
  return err instanceof ApiError && (err.status === 401 || err.status === 403);
}

export function StoreProvider({ children }: { children: React.ReactNode }) {
  const hasToken = typeof window !== "undefined" && !!getAccessToken();
  const { data, isLoading, error, refetch } = useQuery({
    queryKey: ["store", "me"],
    queryFn: async () => {
      const me = await api.get<StoreMe>("/store/me");
      writeCachedMe(me);
      return me;
    },
    enabled: hasToken,
    // A rejection is final; a flaky/absent network is worth a couple of tries
    // before we fall back to the cached identity.
    retry: (count, err) => !isAuthRejection(err) && count < 2,
    staleTime: 60_000,
  });

  const authRejected = isAuthRejection(error);
  // Only stand in for a live answer when the server didn't reject us.
  const cached = React.useMemo(
    () => (hasToken && !data && !authRejected ? readCachedMe() : null),
    [hasToken, data, authRejected],
  );
  const me = data ?? cached;

  const perms = React.useMemo(() => new Set(me?.permissions ?? []), [me]);

  const value: StoreState = {
    me: me ?? null,
    loading: hasToken ? isLoading : false,
    error,
    authRejected,
    stale: !data && !!cached,
    isManager: !!me?.isManager,
    hasPerm: (key) => perms.has(key),
    hasAny: (keys) => keys.some((k) => perms.has(k)),
    refetch,
  };

  return <StoreContext.Provider value={value}>{children}</StoreContext.Provider>;
}

export function useStore() {
  const ctx = React.useContext(StoreContext);
  if (!ctx) throw new Error("useStore must be used within <StoreProvider>");
  return ctx;
}

/** Hook for a page to require a permission; returns whether access is allowed. */
export function usePermission(key: string) {
  const { hasPerm, loading } = useStore();
  return { allowed: hasPerm(key), loading };
}
