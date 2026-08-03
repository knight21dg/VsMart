"use client";

import * as React from "react";
import Link from "next/link";
import { useQueryClient } from "@tanstack/react-query";
import { Eye, EyeOff, Loader2, ShieldCheck } from "lucide-react";
import { useAuth } from "@/lib/auth/auth-context";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import { ApiError } from "@/lib/types";

export default function LoginPage() {
  const qc = useQueryClient();
  const { login } = useAuth();
  const [email, setEmail] = React.useState("");
  const [password, setPassword] = React.useState("");
  const [showPassword, setShowPassword] = React.useState(false);
  const [loading, setLoading] = React.useState(false);
  const [error, setError] = React.useState<string | null>(null);
  const [notice, setNotice] = React.useState<string | null>(null);

  React.useEffect(() => {
    const p = new URLSearchParams(window.location.search);
    if (p.get("expired")) setNotice("Your session expired. Please sign in again.");
    if (p.get("denied")) setNotice("This account isn't an admin.");
    if (p.get("reset")) setNotice("Password updated — sign in with your new password.");
  }, []);

  async function handleSubmit(e: React.FormEvent) {
    e.preventDefault();
    setError(null);
    setLoading(true);
    try {
      await login(email.trim(), password);
      await qc.invalidateQueries({ queryKey: ["users", "me"] });
      // Full navigation so the AuthProvider remounts with the new token and
      // resolves /users/me fresh (avoids a stale gate on client-side replace).
      window.location.assign("/");
    } catch (err) {
      setError(
        err instanceof ApiError ? err.message : "Couldn't sign in. Check your details and try again."
      );
      setLoading(false);
    }
  }

  return (
    <div className="flex min-h-screen w-full bg-white">
      {/* ── Left: branded panel ───────────────────────────────────────── */}
      <div className="relative hidden w-1/2 flex-col justify-between overflow-hidden bg-gradient-to-br from-[#0a8b96] via-[#006d77] to-[#03323a] p-12 text-white lg:flex">
        {/* decorative concentric arcs */}
        <svg
          className="pointer-events-none absolute -right-24 top-1/2 h-[150%] w-[150%] -translate-y-1/2 opacity-[0.12]"
          viewBox="0 0 600 600"
          fill="none"
          aria-hidden="true"
        >
          {[120, 200, 280, 360, 440, 520].map((r) => (
            <circle key={r} cx="120" cy="300" r={r} stroke="white" strokeWidth="1" />
          ))}
        </svg>

        <div className="relative flex items-center gap-3">
          <div className="flex size-12 items-center justify-center overflow-hidden rounded-2xl bg-white shadow-lg ring-1 ring-black/5">
            {/* eslint-disable-next-line @next/next/no-img-element */}
            <img src="/vsmart-logo.png" alt="VS Mart" className="size-full object-contain p-1" />
          </div>
          <span className="text-lg font-semibold tracking-tight">VS Mart</span>
        </div>

        <div className="relative max-w-md">
          <h1 className="font-display text-5xl font-extrabold leading-[1.05] tracking-tight">
            Hello,
            <br />
            Admin! 👋
          </h1>
          <p className="mt-6 text-base leading-relaxed text-white/80">
            Run the entire VS Mart operation from one place — zones, stores, catalog,
            orders, credit and collections. Sign in to your Operations Console.
          </p>
          <span className="mt-7 inline-flex items-center gap-1.5 rounded-full bg-white/10 px-3 py-1.5 text-xs font-medium text-white/90 ring-1 ring-white/20">
            <ShieldCheck className="size-3.5" /> Super Admin &amp; Admin access only
          </span>
        </div>

        <p className="relative text-xs text-white/50">
          © {new Date().getFullYear()} VS Mart. All rights reserved.
        </p>
      </div>

      {/* ── Right: sign-in form ───────────────────────────────────────── */}
      <div className="flex w-full flex-col justify-center px-6 py-12 sm:px-12 lg:w-1/2 lg:px-20">
        <div className="mx-auto w-full max-w-sm">
          {/* compact brand for small screens */}
          <div className="mb-10 flex items-center gap-2 lg:hidden">
            <div className="flex size-9 items-center justify-center overflow-hidden rounded-xl bg-white shadow ring-1 ring-black/5">
              {/* eslint-disable-next-line @next/next/no-img-element */}
              <img src="/vsmart-logo.png" alt="VS Mart" className="size-full object-contain p-1" />
            </div>
            <span className="text-base font-semibold tracking-tight">VS Mart</span>
          </div>

          <h2 className="font-display text-2xl font-bold tracking-tight">Welcome back!</h2>
          <p className="mt-1.5 text-sm text-muted-foreground">
            Sign in to the VS Mart Operations Console.
          </p>

          {notice && (
            <div className="mt-6 rounded-md bg-warning/10 px-3 py-2 text-xs text-warning">{notice}</div>
          )}
          {error && (
            <div className="mt-6 rounded-md bg-destructive/10 px-3 py-2 text-xs text-destructive">{error}</div>
          )}

          <form onSubmit={handleSubmit} className="mt-8 space-y-5">
            <div className="space-y-1.5">
              <Label htmlFor="email">Email</Label>
              <Input
                id="email"
                type="email"
                autoComplete="email"
                inputMode="email"
                autoFocus
                placeholder="you@thevsmart.com"
                value={email}
                onChange={(e) => setEmail(e.target.value)}
                required
              />
            </div>

            <div className="space-y-1.5">
              <Label htmlFor="password">Password</Label>
              <div className="relative">
                <Input
                  id="password"
                  type={showPassword ? "text" : "password"}
                  autoComplete="current-password"
                  placeholder="••••••••"
                  className="pr-10"
                  value={password}
                  onChange={(e) => setPassword(e.target.value)}
                  required
                />
                <button
                  type="button"
                  onClick={() => setShowPassword((s) => !s)}
                  className="absolute inset-y-0 right-0 flex w-10 items-center justify-center text-muted-foreground transition-colors hover:text-foreground"
                  aria-label={showPassword ? "Hide password" : "Show password"}
                  tabIndex={-1}
                >
                  {showPassword ? <EyeOff className="size-4" /> : <Eye className="size-4" />}
                </button>
              </div>
              <div className="flex justify-end pt-0.5">
                <Link
                  href="/forgot-password"
                  className="text-xs font-medium text-primary hover:underline"
                >
                  Forgot password?
                </Link>
              </div>
            </div>

            <Button
              type="submit"
              className="h-11 w-full"
              disabled={loading || !email.trim() || !password}
            >
              {loading && <Loader2 className="size-4 animate-spin" />}
              Sign in
            </Button>
          </form>

          <p className="mt-10 text-center text-[11px] text-muted-foreground">
            Access is limited to authorised administrators.
          </p>
        </div>
      </div>
    </div>
  );
}
