import { jwtDecode } from "jwt-decode";
import type { ApiUser, Role } from "@/lib/types";

const ACCESS_KEY = "vsstore.access";
const REFRESH_KEY = "vsstore.refresh";
const USER_KEY = "vsstore.user";

interface JwtPayload {
  user_id?: string | number;
  role?: Role;
  exp?: number;
}

const isBrowser = () => typeof window !== "undefined";

export function getAccessToken(): string | null {
  return isBrowser() ? localStorage.getItem(ACCESS_KEY) : null;
}

export function getRefreshToken(): string | null {
  return isBrowser() ? localStorage.getItem(REFRESH_KEY) : null;
}

export function setTokens(access: string, refresh?: string) {
  if (!isBrowser()) return;
  localStorage.setItem(ACCESS_KEY, access);
  if (refresh) localStorage.setItem(REFRESH_KEY, refresh);
}

export function setCachedUser(user: ApiUser) {
  if (isBrowser()) localStorage.setItem(USER_KEY, JSON.stringify(user));
}

export function getCachedUser(): ApiUser | null {
  if (!isBrowser()) return null;
  const raw = localStorage.getItem(USER_KEY);
  try {
    return raw ? (JSON.parse(raw) as ApiUser) : null;
  } catch {
    return null;
  }
}

export function clearSession() {
  if (!isBrowser()) return;
  localStorage.removeItem(ACCESS_KEY);
  localStorage.removeItem(REFRESH_KEY);
  localStorage.removeItem(USER_KEY);
}

/** Decode the role from the access token (UI hint only; backend enforces RBAC). */
export function roleFromToken(): Role | null {
  const t = getAccessToken();
  if (!t) return null;
  try {
    return jwtDecode<JwtPayload>(t).role ?? null;
  } catch {
    return null;
  }
}

export function isTokenExpired(token: string | null): boolean {
  if (!token) return true;
  try {
    const { exp } = jwtDecode<JwtPayload>(token);
    return !exp || exp * 1000 <= Date.now();
  } catch {
    return true;
  }
}
