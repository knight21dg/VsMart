"use client";

import { useState } from "react";
import Link from "next/link";
import Nav from "../components/Nav";
import Footer from "../components/Footer";
import { display, mono } from "../components/ui";

const API_BASE_URL =
  process.env.NEXT_PUBLIC_API_BASE_URL || "https://api.thevsmart.com/api/v1";

const fieldStyle: React.CSSProperties = {
  width: "100%",
  padding: "12px 14px",
  borderRadius: 12,
  border: "1.5px solid #E2E8F0",
  fontSize: 14.5,
  fontWeight: 500,
  outline: "none",
  background: "#fff",
  color: "#0F172A",
};

const labelStyle: React.CSSProperties = {
  display: "block",
  fontSize: 13,
  fontWeight: 700,
  color: "#334155",
  marginBottom: 7,
};

export default function DeleteAccountPage() {
  const [name, setName] = useState("");
  const [contact, setContact] = useState("");
  const [reason, setReason] = useState("");
  const [submitting, setSubmitting] = useState(false);
  const [done, setDone] = useState(false);
  const [error, setError] = useState("");

  async function submit(e: React.FormEvent) {
    e.preventDefault();
    setError("");

    if (!contact.trim()) {
      setError("Please enter your account email or mobile number.");
      return;
    }

    setSubmitting(true);
    try {
      const res = await fetch(`${API_BASE_URL}/account/deletion-request`, {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({
          name: name.trim(),
          contact: contact.trim(),
          reason: reason.trim(),
        }),
      });

      if (res.ok) {
        setDone(true);
      } else {
        setError(
          "We couldn't submit your request right now. Please try again, or email hello@vsmart.in."
        );
      }
    } catch {
      setError(
        "We couldn't reach our servers. Please check your connection and try again."
      );
    } finally {
      setSubmitting(false);
    }
  }

  return (
    <div
      style={{
        overflowX: "hidden",
        display: "flex",
        flexDirection: "column",
        minHeight: "100vh",
      }}
    >
      <Nav />

      <main
        style={{
          flex: 1,
          padding: "clamp(40px,7vw,80px) clamp(16px,5vw,28px) clamp(56px,8vw,96px)",
        }}
      >
        <div style={{ maxWidth: 560, margin: "0 auto" }}>
          <Link
            href="/"
            className="legal-back"
            style={{
              display: "inline-flex",
              alignItems: "center",
              gap: 7,
              fontFamily: mono,
              fontSize: 12.5,
              fontWeight: 600,
              letterSpacing: ".12em",
              textTransform: "uppercase",
              color: "#006D77",
              marginBottom: 24,
            }}
          >
            <svg width="15" height="15" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2.4" strokeLinecap="round" strokeLinejoin="round">
              <path d="M15 18l-6-6 6-6" />
            </svg>
            Back to home
          </Link>

          <div
            style={{
              fontFamily: mono,
              fontSize: 12,
              fontWeight: 600,
              letterSpacing: ".14em",
              color: "#006D77",
              textTransform: "uppercase",
              marginBottom: 14,
            }}
          >
            Account & Privacy
          </div>

          <h1
            style={{
              fontFamily: display,
              fontWeight: 800,
              fontSize: "clamp(28px,5.5vw,42px)",
              lineHeight: 1.05,
              letterSpacing: "-.035em",
              margin: "0 0 14px",
            }}
          >
            Delete your account
          </h1>

          <p
            style={{
              fontSize: 15.5,
              color: "#64748B",
              fontWeight: 500,
              lineHeight: 1.65,
              margin: "0 0 18px",
            }}
          >
            Request permanent deletion of your VS Mart account and the personal data
            associated with it.
          </p>

          {/* what gets deleted */}
          <div
            style={{
              background: "#F8FAFC",
              border: "1px solid rgba(15,23,42,.07)",
              borderRadius: 16,
              padding: "18px 20px",
              marginBottom: 26,
            }}
          >
            <ul
              style={{
                listStyle: "none",
                margin: 0,
                padding: 0,
                display: "flex",
                flexDirection: "column",
                gap: 10,
              }}
            >
              {[
                "We delete your profile, contact details, addresses, KYC documents and order history.",
                "Deletion is permanent and cannot be undone once processed.",
                "We process requests within ~7 days and email you to confirm.",
                "Some records may be retained where the law requires (e.g. completed credit & tax records).",
              ].map((item) => (
                <li
                  key={item}
                  style={{
                    display: "flex",
                    gap: 10,
                    fontSize: 13.5,
                    color: "#475569",
                    fontWeight: 500,
                    lineHeight: 1.55,
                  }}
                >
                  <svg
                    width="17"
                    height="17"
                    viewBox="0 0 24 24"
                    fill="none"
                    stroke="#8BC34A"
                    strokeWidth="2.6"
                    strokeLinecap="round"
                    strokeLinejoin="round"
                    style={{ flex: "none", marginTop: 2 }}
                  >
                    <path d="M5 12l4 4L19 6" />
                  </svg>
                  <span>{item}</span>
                </li>
              ))}
            </ul>
          </div>

          {/* form card */}
          <div
            style={{
              background: "#fff",
              border: "1px solid rgba(15,23,42,.08)",
              borderRadius: 24,
              padding: "clamp(22px,4vw,32px)",
              boxShadow: "0 18px 44px rgba(15,23,42,.06)",
            }}
          >
            {done ? (
              <div
                style={{
                  background: "#EAF7DE",
                  border: "1px solid #8BC34A",
                  borderRadius: 16,
                  padding: "30px 24px",
                  textAlign: "center",
                }}
              >
                <div
                  style={{
                    width: 52,
                    height: 52,
                    borderRadius: "50%",
                    background: "#8BC34A",
                    display: "flex",
                    alignItems: "center",
                    justifyContent: "center",
                    margin: "0 auto 14px",
                  }}
                >
                  <svg width="26" height="26" viewBox="0 0 24 24" fill="none" stroke="#fff" strokeWidth="2.6" strokeLinecap="round" strokeLinejoin="round">
                    <path d="M5 12l4 4L19 6" />
                  </svg>
                </div>
                <div
                  style={{
                    fontFamily: display,
                    fontWeight: 800,
                    fontSize: 20,
                    color: "#3f6212",
                    marginBottom: 4,
                  }}
                >
                  Request received
                </div>
                <div
                  style={{
                    fontSize: 14,
                    color: "#3f6212",
                    fontWeight: 600,
                    lineHeight: 1.6,
                  }}
                >
                  We&apos;ll process it within 7 days and email you to confirm.
                </div>
              </div>
            ) : (
              <form onSubmit={submit} style={{ display: "flex", flexDirection: "column", gap: 16 }}>
                <div>
                  <label htmlFor="da-name" style={labelStyle}>
                    Full name <span style={{ color: "#94A3B8", fontWeight: 600 }}>(optional)</span>
                  </label>
                  <input
                    id="da-name"
                    className="field"
                    value={name}
                    onChange={(e) => setName(e.target.value)}
                    placeholder="Your name"
                    autoComplete="name"
                    style={fieldStyle}
                  />
                </div>

                <div>
                  <label htmlFor="da-contact" style={labelStyle}>
                    Account email or mobile <span style={{ color: "#DC2626", fontWeight: 700 }}>*</span>
                  </label>
                  <input
                    id="da-contact"
                    className="field"
                    value={contact}
                    onChange={(e) => setContact(e.target.value)}
                    placeholder="name@email.com or +91 98xxxxxxxx"
                    required
                    style={fieldStyle}
                  />
                </div>

                <div>
                  <label htmlFor="da-reason" style={labelStyle}>
                    Reason <span style={{ color: "#94A3B8", fontWeight: 600 }}>(optional)</span>
                  </label>
                  <textarea
                    id="da-reason"
                    className="field"
                    value={reason}
                    onChange={(e) => setReason(e.target.value)}
                    placeholder="Help us improve — why are you leaving?"
                    rows={4}
                    style={{ ...fieldStyle, resize: "vertical", minHeight: 96, lineHeight: 1.55 }}
                  />
                </div>

                {error ? (
                  <div
                    role="alert"
                    style={{
                      background: "#FEF2F2",
                      border: "1px solid #FCA5A5",
                      borderRadius: 12,
                      padding: "11px 14px",
                      fontSize: 13.5,
                      fontWeight: 600,
                      color: "#B91C1C",
                      lineHeight: 1.5,
                    }}
                  >
                    {error}
                  </div>
                ) : null}

                <button
                  type="submit"
                  disabled={submitting}
                  className={submitting ? "" : "lift2"}
                  style={{
                    width: "100%",
                    padding: 14,
                    borderRadius: 12,
                    border: "none",
                    background: submitting ? "#94A3B8" : "#006D77",
                    color: "#fff",
                    fontWeight: 700,
                    fontSize: 15,
                    cursor: submitting ? "not-allowed" : "pointer",
                    boxShadow: submitting ? "none" : "0 10px 22px rgba(0,109,119,.28)",
                    transition: "transform .2s, background .2s",
                  }}
                >
                  {submitting ? "Submitting…" : "Request account deletion"}
                </button>

                <p style={{ fontSize: 12.5, color: "#94A3B8", fontWeight: 500, margin: 0, textAlign: "center", lineHeight: 1.5 }}>
                  Need help? Email{" "}
                  <a href="mailto:hello@vsmart.in" style={{ color: "#006D77", fontWeight: 700 }}>
                    hello@vsmart.in
                  </a>
                </p>
              </form>
            )}
          </div>
        </div>
      </main>

      <Footer />
    </div>
  );
}
