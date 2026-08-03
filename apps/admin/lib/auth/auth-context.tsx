"use client";

import * as React from "react";
import { useRouter } from "next/navigation";
import { api } from "@/lib/api/client";
import {
  clearSession,
  getAccessToken,
  getCachedUser,
  isConsoleRole,
  setCachedUser,
  setTokens,
} from "@/lib/auth/session";
import type { ApiUser } from "@/lib/types";
import { ApiError } from "@/lib/types";

interface AuthState {
  user: ApiUser | null;
  loading: boolean;
  /** Email + password sign-in, gated on the admin/superadmin console role. Returns the user. */
  login: (email: string, password: string) => Promise<ApiUser>;
  /** Request a password-reset OTP texted to the account's phone. Returns a verification id. */
  forgotPassword: (phone: string) => Promise<string>;
  /** Complete a password reset with the texted OTP. */
  resetPassword: (args: {
    phone: string;
    verificationId: string;
    code: string;
    newPassword: string;
  }) => Promise<void>;
  /** @deprecated phone OTP login — retained so older flows still build. */
  verifyOtp: (args: { phone: string; otp: string; verificationId: string }) => Promise<ApiUser>;
  /** @deprecated phone OTP login — retained so older flows still build. */
  sendOtp: (phone: string) => Promise<string>; // returns verification_id
  logout: () => Promise<void>;
  refreshUser: () => Promise<void>;
}

const AuthContext = React.createContext<AuthState | null>(null);

interface LoginResponse {
  access_token: string;
  refresh_token?: string;
  expires_at?: string;
  is_new_user?: boolean;
  user: ApiUser;
}

interface OtpVerifyResponse {
  access_token: string;
  refresh_token?: string;
  user: ApiUser;
}

export function AuthProvider({ children }: { children: React.ReactNode }) {
  const router = useRouter();
  const [user, setUser] = React.useState<ApiUser | null>(null);
  const [loading, setLoading] = React.useState(true);

  // Hydrate from cache + validate token on mount.
  React.useEffect(() => {
    const cached = getCachedUser();
    if (cached) setUser(cached);
    const token = getAccessToken();
    if (!token) {
      setLoading(false);
      return;
    }
    api
      .get<ApiUser>("/users/me")
      .then((u) => {
        setUser(u);
        setCachedUser(u);
      })
      .catch(() => {
        // 401 handling in the client already clears the session/redirects.
      })
      .finally(() => setLoading(false));
  }, []);

  const login = React.useCallback(async (email: string, password: string) => {
    const data = await api.postPublic<LoginResponse>("/auth/login", { email, password });
    setTokens(data.access_token, data.refresh_token);
    // Gate on console role: only super-admins / admins may enter the console.
    let me: ApiUser;
    try {
      me = await api.get<ApiUser>("/users/me");
    } catch {
      clearSession();
      throw new ApiError("Couldn't verify this account. Please try again.", {
        code: "gate_failed",
        status: 403,
      });
    }
    if (!isConsoleRole(me.role)) {
      clearSession();
      throw new ApiError("This account isn't an admin.", { code: "not_console_role", status: 403 });
    }
    setCachedUser(me);
    setUser(me);
    return me;
  }, []);

  const forgotPassword = React.useCallback(async (phone: string) => {
    const data = await api.postPublic<{ verificationId: string }>(
      "/auth/password/forgot",
      { phone }
    );
    return data.verificationId;
  }, []);

  const resetPassword = React.useCallback(
    async ({
      phone,
      verificationId,
      code,
      newPassword,
    }: {
      phone: string;
      verificationId: string;
      code: string;
      newPassword: string;
    }) => {
      await api.postPublic("/auth/password/reset", {
        phone,
        verification_id: verificationId,
        code,
        new_password: newPassword,
      });
    },
    []
  );

  const sendOtp = React.useCallback(async (phone: string) => {
    const data = await api.postPublic<{ verification_id: string }>("/auth/otp/send", { phone });
    return data.verification_id;
  }, []);

  const verifyOtp = React.useCallback(
    async ({ phone, otp, verificationId }: { phone: string; otp: string; verificationId: string }) => {
      const data = await api.postPublic<OtpVerifyResponse>("/auth/otp/verify", {
        phone,
        otp,
        verification_id: verificationId,
      });
      setTokens(data.access_token, data.refresh_token);
      setCachedUser(data.user);
      setUser(data.user);
      return data.user;
    },
    []
  );

  const logout = React.useCallback(async () => {
    const refresh = typeof window !== "undefined" ? localStorage.getItem("vsadmin.refresh") : null;
    try {
      if (refresh) await api.post("/auth/logout", { refresh });
    } catch {
      /* best effort */
    }
    clearSession();
    setUser(null);
    router.replace("/login");
  }, [router]);

  const refreshUser = React.useCallback(async () => {
    const u = await api.get<ApiUser>("/users/me");
    setUser(u);
    setCachedUser(u);
  }, []);

  const value: AuthState = {
    user,
    loading,
    login,
    forgotPassword,
    resetPassword,
    sendOtp,
    verifyOtp,
    logout,
    refreshUser,
  };
  return <AuthContext.Provider value={value}>{children}</AuthContext.Provider>;
}

export function useAuth() {
  const ctx = React.useContext(AuthContext);
  if (!ctx) throw new Error("useAuth must be used within <AuthProvider>");
  return ctx;
}

export { isConsoleRole };
