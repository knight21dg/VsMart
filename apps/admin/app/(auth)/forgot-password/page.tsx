"use client";

import * as React from "react";
import Link from "next/link";
import { toast } from "sonner";
import { ArrowLeft, Eye, EyeOff, KeyRound, Loader2, ShieldCheck } from "lucide-react";
import { useAuth } from "@/lib/auth/auth-context";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import { ApiError } from "@/lib/types";

export default function ForgotPasswordPage() {
  const { forgotPassword, resetPassword } = useAuth();
  const [step, setStep] = React.useState<"phone" | "reset">("phone");
  const [phone, setPhone] = React.useState("");
  const [verificationId, setVerificationId] = React.useState("");
  const [code, setCode] = React.useState("");
  const [password, setPassword] = React.useState("");
  const [confirm, setConfirm] = React.useState("");
  const [showPassword, setShowPassword] = React.useState(false);
  const [loading, setLoading] = React.useState(false);
  const [error, setError] = React.useState<string | null>(null);

  async function handleRequest(e: React.FormEvent) {
    e.preventDefault();
    setError(null);
    setLoading(true);
    try {
      const vid = await forgotPassword(phone.trim());
      setVerificationId(vid);
      setStep("reset");
    } catch (err) {
      setError(
        err instanceof ApiError ? err.message : "Couldn't send the code. Please try again."
      );
    } finally {
      setLoading(false);
    }
  }

  async function handleReset(e: React.FormEvent) {
    e.preventDefault();
    setError(null);
    if (password !== confirm) {
      setError("Passwords don't match.");
      return;
    }
    setLoading(true);
    try {
      await resetPassword({
        phone: phone.trim(),
        verificationId,
        code: code.trim(),
        newPassword: password,
      });
      toast.success("Password updated — sign in.");
      window.location.assign("/login?reset=1");
    } catch (err) {
      setError(
        err instanceof ApiError
          ? err.message
          : "Couldn't reset your password. Check the code and try again."
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
            Forgot your
            <br />
            password? 🔑
          </h1>
          <p className="mt-6 text-base leading-relaxed text-white/80">
            No worries — we&apos;ll text a one-time reset code to your registered
            phone so you can set a new password and get back into your Operations Console.
          </p>
          <span className="mt-7 inline-flex items-center gap-1.5 rounded-full bg-white/10 px-3 py-1.5 text-xs font-medium text-white/90 ring-1 ring-white/20">
            <ShieldCheck className="size-3.5" /> Super Admin &amp; Admin access only
          </span>
        </div>

        <p className="relative text-xs text-white/50">
          © {new Date().getFullYear()} VS Mart. All rights reserved.
        </p>
      </div>

      {/* ── Right: reset form ─────────────────────────────────────────── */}
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

          <h2 className="font-display text-2xl font-bold tracking-tight">
            {step === "phone" ? "Reset your password" : "Set a new password"}
          </h2>
          <p className="mt-1.5 text-sm text-muted-foreground">
            {step === "phone"
              ? "Enter your phone number and we'll text a reset code."
              : "Enter the code we texted you and choose a new password."}
          </p>

          {error && (
            <div className="mt-6 rounded-md bg-destructive/10 px-3 py-2 text-xs text-destructive">{error}</div>
          )}

          {step === "phone" ? (
            <form onSubmit={handleRequest} className="mt-8 space-y-5">
              <div className="space-y-1.5">
                <Label htmlFor="phone">Phone number</Label>
                <Input
                  id="phone"
                  type="tel"
                  autoComplete="tel"
                  inputMode="tel"
                  autoFocus
                  placeholder="+91 90000 00000"
                  value={phone}
                  onChange={(e) => setPhone(e.target.value)}
                  required
                />
                <p className="text-xs text-muted-foreground">
                  We&apos;ll text a reset code to this number if it&apos;s registered.
                </p>
              </div>
              <Button type="submit" className="h-11 w-full" disabled={loading || !phone.trim()}>
                {loading && <Loader2 className="size-4 animate-spin" />}
                Send reset code
              </Button>
            </form>
          ) : (
            <form onSubmit={handleReset} className="mt-8 space-y-5">
              <div className="rounded-md bg-primary/10 px-3 py-2 text-xs text-primary">
                Enter the code texted to{" "}
                <span className="font-semibold">{phone.trim()}</span>.
              </div>

              <div className="space-y-1.5">
                <Label htmlFor="code">Reset code</Label>
                <Input
                  id="code"
                  inputMode="numeric"
                  autoFocus
                  placeholder="6-digit code"
                  value={code}
                  onChange={(e) => setCode(e.target.value)}
                  required
                />
              </div>

              <div className="space-y-1.5">
                <Label htmlFor="new-password">New password</Label>
                <div className="relative">
                  <Input
                    id="new-password"
                    type={showPassword ? "text" : "password"}
                    autoComplete="new-password"
                    placeholder="At least 8 characters"
                    className="pr-10"
                    value={password}
                    onChange={(e) => setPassword(e.target.value)}
                    minLength={8}
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
              </div>

              <div className="space-y-1.5">
                <Label htmlFor="confirm-password">Confirm new password</Label>
                <Input
                  id="confirm-password"
                  type={showPassword ? "text" : "password"}
                  autoComplete="new-password"
                  placeholder="Re-enter new password"
                  value={confirm}
                  onChange={(e) => setConfirm(e.target.value)}
                  minLength={8}
                  required
                />
              </div>

              <Button
                type="submit"
                className="h-11 w-full"
                disabled={loading || !code.trim() || !password || !confirm}
              >
                {loading ? <Loader2 className="size-4 animate-spin" /> : <KeyRound className="size-4" />}
                Update password
              </Button>

              <button
                type="button"
                className="w-full text-center text-xs text-muted-foreground hover:text-foreground"
                onClick={() => {
                  setStep("phone");
                  setCode("");
                  setPassword("");
                  setConfirm("");
                  setError(null);
                }}
              >
                ← Use a different phone number
              </button>
            </form>
          )}

          <div className="mt-8 text-center">
            <Link
              href="/login"
              className="inline-flex items-center gap-1 text-xs font-medium text-muted-foreground hover:text-foreground"
            >
              <ArrowLeft className="size-3.5" /> Back to sign in
            </Link>
          </div>
        </div>
      </div>
    </div>
  );
}
