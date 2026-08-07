"use client";

import { useState } from "react";
import { display } from "./ui";

export default function LeadForm() {
  const [name, setName] = useState("");
  const [phone, setPhone] = useState("");
  const [location, setLocation] = useState("");
  const [type, setType] = useState("");
  const [sent, setSent] = useState(false);

  function submit() {
    // Front-end only, mirroring the prototype: show a thank-you state.
    setSent(true);
  }

  const fieldStyle = {
    width: "100%",
    padding: "12px 14px",
    borderRadius: 12,
    border: "1.5px solid #E2E8F0",
    fontSize: 14,
    fontWeight: 500 as const,
    outline: "none",
  };

  return (
    <div className="r-biz-form" style={{ background: "#F8FAFC", borderRadius: 24, padding: "clamp(20px,4vw,30px)", border: "1px solid rgba(15,23,42,.06)" }}>
      <h3 style={{ fontFamily: display, fontWeight: 800, fontSize: 21, margin: "0 0 6px" }}>Tell us about you</h3>
      <p style={{ fontSize: 13.5, color: "#64748B", fontWeight: 500, margin: "0 0 18px" }}>
        Our team will reach out within 24 hours.
      </p>

      {sent ? (
        <div
          style={{
            background: "#EAF7DE",
            border: "1px solid #8BC34A",
            borderRadius: 14,
            padding: "28px 24px",
            textAlign: "center",
          }}
        >
          <div
            style={{
              width: 48,
              height: 48,
              borderRadius: "50%",
              background: "#8BC34A",
              display: "flex",
              alignItems: "center",
              justifyContent: "center",
              margin: "0 auto 12px",
            }}
          >
            <svg width="24" height="24" viewBox="0 0 24 24" fill="none" stroke="#fff" strokeWidth="2.6" strokeLinecap="round" strokeLinejoin="round">
              <path d="M5 12l4 4L19 6" />
            </svg>
          </div>
          <div style={{ fontWeight: 800, fontFamily: display, fontSize: 19, color: "#3f6212" }}>Thank you!</div>
          <div style={{ fontSize: 13, color: "#3f6212", fontWeight: 600, marginTop: 2 }}>
            We&apos;ll be in touch within 24 hours.
          </div>
        </div>
      ) : (
        <div style={{ display: "flex", flexDirection: "column", gap: 11 }}>
          <input
            className="field"
            value={name}
            onChange={(e) => setName(e.target.value)}
            placeholder="Full name"
            style={fieldStyle}
          />
          <input
            className="field"
            value={phone}
            onChange={(e) => setPhone(e.target.value)}
            placeholder="Phone number"
            style={fieldStyle}
          />
          <input
            className="field"
            value={location}
            onChange={(e) => setLocation(e.target.value)}
            placeholder="Location / City"
            style={fieldStyle}
          />
          <select
            className="field"
            value={type}
            onChange={(e) => setType(e.target.value)}
            style={{ ...fieldStyle, fontWeight: 600, color: "#475569", background: "#fff" }}
          >
            <option value="">Business type</option>
            <option value="agent">Delivery / Collection Agent</option>
            <option value="franchise">Franchise / Store Owner</option>
            <option value="other">Other</option>
          </select>
          <button
            onClick={submit}
            className="lift2"
            style={{
              width: "100%",
              padding: 13,
              borderRadius: 12,
              border: "none",
              background: "#006D77",
              color: "#fff",
              fontWeight: 700,
              fontSize: 15,
              cursor: "pointer",
              boxShadow: "0 10px 22px rgba(0,109,119,.28)",
              transition: "transform .2s",
            }}
          >
            Submit Application
          </button>
        </div>
      )}
    </div>
  );
}
