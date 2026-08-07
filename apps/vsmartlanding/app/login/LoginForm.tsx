"use client";

import { useCallback, useEffect, useRef, useState } from "react";
import Link from "next/link";

import { colors, display, mono } from "../components/ui";
import { formatIndianMobile } from "../lib/phone";
import OtpInput from "./OtpInput";

type Step = "phone" | "otp" | "profile";

const OTP_LENGTH = 6;
const RESEND_SECONDS = 30;

interface ApiEnvelope {
  ok?: boolean;
  message?: string;
  verificationId?: string;
  phone?: string;
  needsProfile?: boolean;
}

export default function LoginForm({ next }: { next: string }) {
  const [step, setStep] = useState<Step>("phone");
  const [mobile, setMobile] = useState("");
  const [phone, setPhone] = useState(""); // E.164, as normalised by the server
  const [verificationId, setVerificationId] = useState("");
  // One slot per box, so editing a digit edits that digit — see OtpInput.
  const [slots, setSlots] = useState<string[]>(() => Array(OTP_LENGTH).fill(""));
  // Bumped whenever the boxes are cleared, to pull focus back to the first one.
  const [resetToken, setResetToken] = useState(0);
  const [name, setName] = useState("");
  const [email, setEmail] = useState("");
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [notice, setNotice] = useState<string | null>(null);
  const [resendIn, setResendIn] = useState(0);
  // Guards the auto-submit that fires when the 6th digit lands.
  const verifying = useRef(false);
  // Set once we're navigating away, so the button keeps its spinner instead of
  // flicking back to "ready" while the new page loads.
  const navigating = useRef(false);

  useEffect(() => {
    if (resendIn <= 0) return;
    const t = setTimeout(() => setResendIn((s) => s - 1), 1000);
    return () => clearTimeout(t);
  }, [resendIn]);

  async function post(path: string, body: unknown): Promise<ApiEnvelope> {
    const res = await fetch(path, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify(body),
    });
    let json: ApiEnvelope = {};
    try {
      json = (await res.json()) as ApiEnvelope;
    } catch {
      /* non-JSON (proxy error page) — fall through to the generic message */
    }
    if (!res.ok || json.ok === false) {
      throw new Error(json.message || "Something went wrong. Please try again.");
    }
    return json;
  }

  /** Empty the boxes and put the cursor back in the first one. */
  function resetCode() {
    setSlots(Array(OTP_LENGTH).fill(""));
    setResetToken((t) => t + 1);
  }

  async function sendOtp(resend = false) {
    setError(null);
    setNotice(null);
    setLoading(true);
    try {
      const data = await post("/api/auth/otp/send", { phone: mobile });
      setVerificationId(data.verificationId ?? "");
      setPhone(data.phone ?? "");
      resetCode();
      setStep("otp");
      setResendIn(RESEND_SECONDS);
      if (resend) setNotice("We've sent a new code.");
    } catch (e) {
      setError(e instanceof Error ? e.message : "Couldn't send the code.");
    } finally {
      setLoading(false);
    }
  }

  const verifyOtp = useCallback(
    async (value: string) => {
      if (verifying.current) return;
      verifying.current = true;
      setError(null);
      setNotice(null);
      setLoading(true);
      try {
        const data = await post("/api/auth/otp/verify", {
          phone,
          otp: value,
          verificationId,
        });
        if (data.needsProfile) {
          setStep("profile");
        } else {
          navigating.current = true;
          window.location.assign(next);
        }
      } catch (e) {
        resetCode();
        setError(e instanceof Error ? e.message : "That code didn't work.");
        // A rejected code usually means the customer needs a fresh one — don't
        // make them sit out the rest of the countdown.
        setResendIn(0);
      } finally {
        verifying.current = false;
        if (!navigating.current) setLoading(false);
      }
    },
    [next, phone, verificationId]
  );

  async function saveProfile() {
    setError(null);
    setLoading(true);
    try {
      await post("/api/auth/profile", { name, email });
      window.location.assign(next);
    } catch (e) {
      setError(e instanceof Error ? e.message : "Couldn't save your details.");
      setLoading(false);
    }
  }

  const mobileValid = /^[6-9]\d{9}$/.test(mobile);
  const code = slots.join("");
  const codeComplete = code.length === OTP_LENGTH;

  return (
    <div style={{ width: "100%", maxWidth: 460 }}>
      <div
        style={{
          background: "#fff",
          border: "1px solid rgba(15,23,42,.08)",
          borderRadius: 26,
          padding: "clamp(24px,5vw,38px)",
          boxShadow: "0 24px 60px rgba(15,23,42,.07)",
        }}
      >
        <div
          style={{
            fontFamily: mono,
            fontSize: 12,
            fontWeight: 600,
            letterSpacing: ".14em",
            color: colors.teal,
            textTransform: "uppercase",
            marginBottom: 12,
          }}
        >
          {step === "profile" ? "Almost there" : "Customer sign in"}
        </div>

        <h1
          style={{
            fontFamily: display,
            fontWeight: 800,
            fontSize: "clamp(26px,4.5vw,34px)",
            lineHeight: 1.1,
            letterSpacing: "-.03em",
            margin: "0 0 8px",
          }}
        >
          {step === "phone" && "Sign in to VS Mart"}
          {step === "otp" && "Enter the code"}
          {step === "profile" && "What should we call you?"}
        </h1>

        <p
          style={{
            fontSize: 14.5,
            color: "#64748B",
            fontWeight: 500,
            lineHeight: 1.6,
            margin: "0 0 22px",
          }}
        >
          {step === "phone" &&
            "We'll text a one-time code to your mobile number. No password needed."}
          {step === "otp" && (
            <>
              Sent to <strong style={{ color: "#0F172A" }}>{formatIndianMobile(phone)}</strong>{" "}
              <button
                type="button"
                onClick={() => {
                  setStep("phone");
                  resetCode();
                  setError(null);
                  setNotice(null);
                }}
                style={{
                  border: "none",
                  background: "none",
                  padding: 0,
                  color: colors.teal,
                  fontWeight: 700,
                  fontSize: 14,
                  cursor: "pointer",
                }}
              >
                Change
              </button>
            </>
          )}
          {step === "profile" &&
            "Add your name so your orders, invoices and deliveries are addressed to you."}
        </p>

        {error && (
          <div
            role="alert"
            style={{
              background: "#FEF2F2",
              border: "1px solid #FECACA",
              color: "#B91C1C",
              borderRadius: 12,
              padding: "10px 13px",
              fontSize: 13.5,
              fontWeight: 600,
              marginBottom: 16,
            }}
          >
            {error}
          </div>
        )}
        {notice && !error && (
          <div
            role="status"
            style={{
              background: "#EAF7DE",
              border: "1px solid #8BC34A",
              color: "#3F6212",
              borderRadius: 12,
              padding: "10px 13px",
              fontSize: 13.5,
              fontWeight: 600,
              marginBottom: 16,
            }}
          >
            {notice}
          </div>
        )}

        {step === "phone" && (
          <form
            onSubmit={(e) => {
              e.preventDefault();
              if (mobileValid && !loading) void sendOtp();
            }}
          >
            <label
              htmlFor="mobile"
              style={{ display: "block", fontSize: 13, fontWeight: 700, marginBottom: 7 }}
            >
              Mobile number
            </label>
            <div
              style={{
                display: "flex",
                alignItems: "center",
                border: "1.5px solid #E2E8F0",
                borderRadius: 14,
                overflow: "hidden",
                background: "#fff",
              }}
            >
              <span
                style={{
                  padding: "0 12px",
                  fontFamily: mono,
                  fontSize: 15,
                  fontWeight: 700,
                  color: "#475569",
                  borderRight: "1.5px solid #E2E8F0",
                  lineHeight: "52px",
                  background: "#F8FAFC",
                }}
              >
                +91
              </span>
              <input
                id="mobile"
                value={mobile}
                onChange={(e) => setMobile(e.target.value.replace(/\D/g, "").slice(0, 10))}
                placeholder="98765 43210"
                inputMode="numeric"
                autoComplete="tel-national"
                autoFocus
                style={{
                  flex: 1,
                  minWidth: 0,
                  height: 52,
                  border: "none",
                  outline: "none",
                  padding: "0 14px",
                  fontSize: 16,
                  fontWeight: 600,
                  letterSpacing: ".04em",
                  color: "#0F172A",
                }}
              />
            </div>

            <SubmitButton disabled={!mobileValid || loading} loading={loading}>
              Send code
            </SubmitButton>

            <p
              style={{
                fontSize: 12,
                color: "#94A3B8",
                fontWeight: 500,
                lineHeight: 1.6,
                margin: "14px 0 0",
                textAlign: "center",
              }}
            >
              By continuing you agree to our{" "}
              <Link href="/terms" style={{ color: colors.teal, fontWeight: 700 }}>
                Terms
              </Link>{" "}
              and{" "}
              <Link href="/privacy" style={{ color: colors.teal, fontWeight: 700 }}>
                Privacy Policy
              </Link>
              .
            </p>
          </form>
        )}

        {step === "otp" && (
          <form
            onSubmit={(e) => {
              e.preventDefault();
              if (codeComplete && !loading) void verifyOtp(code);
            }}
          >
            <OtpInput
              value={slots}
              onChange={(next) => {
                setSlots(next);
                // Clear the red state as soon as they start retyping.
                if (error) setError(null);
              }}
              onComplete={(value) => void verifyOtp(value)}
              length={OTP_LENGTH}
              invalid={Boolean(error)}
              resetToken={resetToken}
            />

            <SubmitButton disabled={!codeComplete || loading} loading={loading}>
              {loading ? "Verifying…" : "Verify & continue"}
            </SubmitButton>

            <div style={{ marginTop: 14, textAlign: "center", fontSize: 13.5, fontWeight: 600 }}>
              {resendIn > 0 ? (
                <span style={{ color: "#94A3B8" }}>
                  Resend code in {resendIn}s
                </span>
              ) : (
                <button
                  type="button"
                  onClick={() => void sendOtp(true)}
                  disabled={loading}
                  style={{
                    border: "none",
                    background: "none",
                    padding: 0,
                    color: colors.teal,
                    fontWeight: 700,
                    fontSize: 13.5,
                    cursor: loading ? "default" : "pointer",
                  }}
                >
                  Resend code
                </button>
              )}
            </div>
          </form>
        )}

        {step === "profile" && (
          <form
            onSubmit={(e) => {
              e.preventDefault();
              if (name.trim().length >= 2 && !loading) void saveProfile();
            }}
          >
            <label
              htmlFor="name"
              style={{ display: "block", fontSize: 13, fontWeight: 700, marginBottom: 7 }}
            >
              Full name
            </label>
            <input
              id="name"
              className="field"
              value={name}
              onChange={(e) => setName(e.target.value)}
              placeholder="Your name"
              autoComplete="name"
              autoFocus
              style={fieldStyle}
            />

            <label
              htmlFor="email"
              style={{
                display: "block",
                fontSize: 13,
                fontWeight: 700,
                margin: "16px 0 7px",
              }}
            >
              Email <span style={{ color: "#94A3B8", fontWeight: 600 }}>(optional)</span>
            </label>
            <input
              id="email"
              className="field"
              value={email}
              onChange={(e) => setEmail(e.target.value)}
              placeholder="you@example.com"
              type="email"
              autoComplete="email"
              style={fieldStyle}
            />

            <SubmitButton disabled={name.trim().length < 2 || loading} loading={loading}>
              Continue
            </SubmitButton>
          </form>
        )}
      </div>

      <p
        style={{
          textAlign: "center",
          fontSize: 13,
          color: "#64748B",
          fontWeight: 600,
          margin: "18px 0 0",
        }}
      >
        Shopping on your phone?{" "}
        <Link href="/userapp" style={{ color: colors.teal, fontWeight: 700 }}>
          Get the VS Mart app
        </Link>
      </p>
    </div>
  );
}

const fieldStyle = {
  width: "100%",
  height: 52,
  padding: "0 14px",
  borderRadius: 14,
  border: "1.5px solid #E2E8F0",
  fontSize: 15.5,
  fontWeight: 600,
  color: "#0F172A",
  outline: "none",
} as const;

function SubmitButton({
  children,
  disabled,
  loading,
}: {
  children: React.ReactNode;
  disabled?: boolean;
  loading?: boolean;
}) {
  return (
    <button
      type="submit"
      disabled={disabled}
      className={disabled ? undefined : "lift2"}
      style={{
        marginTop: 20,
        width: "100%",
        height: 52,
        borderRadius: 14,
        border: "none",
        background: disabled ? "#CBD5E1" : colors.teal,
        color: "#fff",
        fontWeight: 700,
        fontSize: 15.5,
        cursor: disabled ? "not-allowed" : "pointer",
        boxShadow: disabled ? "none" : "0 10px 22px rgba(0,109,119,.28)",
        transition: "transform .2s, background .2s",
        display: "inline-flex",
        alignItems: "center",
        justifyContent: "center",
        gap: 9,
      }}
    >
      {loading && <Spinner />}
      {children}
    </button>
  );
}

function Spinner() {
  return (
    <svg width="17" height="17" viewBox="0 0 24 24" fill="none" aria-hidden="true">
      <circle cx="12" cy="12" r="9" stroke="rgba(255,255,255,.35)" strokeWidth="3" />
      <path
        d="M21 12a9 9 0 0 0-9-9"
        stroke="#fff"
        strokeWidth="3"
        strokeLinecap="round"
        style={{ transformOrigin: "12px 12px", animation: "vsspin .8s linear infinite" }}
      />
    </svg>
  );
}
