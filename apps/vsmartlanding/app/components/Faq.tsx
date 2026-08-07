"use client";

import { useState } from "react";
import { display, mono } from "./ui";

const faqData = [
  {
    q: "How does VS Credit work?",
    a: "Register, verify your identity, and get an approved credit limit based on your VS Score. You can then shop groceries on credit and repay weekly or monthly.",
  },
  {
    q: "Is Aadhaar mandatory?",
    a: "Aadhaar is used for secure identity verification along with PAN, a selfie and address. It helps us approve your credit quickly and safely.",
  },
  {
    q: "How are payments collected?",
    a: "Repayments can be made via UPI, QR or cash. Our agents use OTP-based smart collections so every payment is verified and recorded.",
  },
  {
    q: "What is VS Score?",
    a: "VS Score is your credit health rating from 300 to 900. A higher score unlocks a higher limit, faster approvals and special offers.",
  },
  {
    q: "Can I pay online?",
    a: "Yes. You can repay anytime from the app using UPI or QR, or choose cash collection at your doorstep.",
  },
  {
    q: "How long does approval take?",
    a: "Most users are approved within minutes of completing verification, depending on the credit assessment.",
  },
];

export default function Faq() {
  const [open, setOpen] = useState(0);

  return (
    <section id="faq" style={{ padding: "clamp(64px,9vw,108px) clamp(16px,5vw,28px)", background: "#F4F7F6" }}>
      <div
        className="r-faq-grid"
        style={{
          maxWidth: 1200,
          margin: "0 auto",
          display: "grid",
          gridTemplateColumns: ".8fr 1.2fr",
          gap: 48,
          alignItems: "start",
        }}
      >
        <div className="r-faq-aside" data-reveal style={{ position: "sticky", top: 100 }}>
          <div
            style={{
              fontFamily: mono,
              fontSize: 12,
              fontWeight: 600,
              letterSpacing: ".14em",
              color: "#006D77",
              textTransform: "uppercase",
              marginBottom: 16,
            }}
          >
            10 — FAQ
          </div>
          <h2
            style={{
              fontFamily: display,
              fontWeight: 800,
              fontSize: "clamp(28px,4.5vw,42px)",
              lineHeight: 1.02,
              letterSpacing: "-.035em",
              margin: "0 0 18px",
            }}
          >
            Frequently
            <br />
            asked questions.
          </h2>
          <p style={{ fontSize: 15.5, color: "#64748B", fontWeight: 500, margin: "0 0 24px", lineHeight: 1.6, maxWidth: 300 }}>
            Everything you need to know about VS Credit, payments and delivery.
          </p>
          <a
            href="#download"
            style={{
              display: "inline-flex",
              alignItems: "center",
              gap: 10,
              background: "#fff",
              border: "1px solid rgba(15,23,42,.1)",
              borderRadius: 14,
              padding: "14px 18px",
              boxShadow: "0 8px 24px rgba(15,23,42,.05)",
            }}
          >
            <span
              style={{
                width: 40,
                height: 40,
                borderRadius: 11,
                background: "#E6F4F1",
                display: "flex",
                alignItems: "center",
                justifyContent: "center",
                flex: "none",
              }}
            >
              <svg width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="#006D77" strokeWidth="1.8" strokeLinecap="round" strokeLinejoin="round">
                <path d="M21 15a2 2 0 0 1-2 2H7l-4 4V5a2 2 0 0 1 2-2h14a2 2 0 0 1 2 2z" />
              </svg>
            </span>
            <span>
              <span style={{ display: "block", fontFamily: display, fontWeight: 700, fontSize: 14, color: "#0F172A" }}>
                Still have questions?
              </span>
              <span style={{ display: "block", fontSize: 12, color: "#64748B", fontWeight: 600 }}>
                Chat with our team in-app
              </span>
            </span>
          </a>
        </div>

        <div data-reveal-group style={{ display: "flex", flexDirection: "column", gap: 12 }}>
          {faqData.map((f, i) => {
            const isOpen = open === i;
            return (
              <div
                key={f.q}
                className="faq-card"
                style={{
                  background: "#fff",
                  borderRadius: 16,
                  border: "1px solid rgba(15,23,42,.06)",
                  overflow: "hidden",
                  transition: "box-shadow .25s",
                }}
              >
                <button
                  onClick={() => setOpen(isOpen ? -1 : i)}
                  style={{
                    width: "100%",
                    display: "flex",
                    alignItems: "center",
                    justifyContent: "space-between",
                    gap: 16,
                    padding: "22px 26px",
                    background: "none",
                    border: "none",
                    cursor: "pointer",
                    textAlign: "left",
                  }}
                >
                  <span style={{ display: "flex", alignItems: "center", gap: 14 }}>
                    <span style={{ fontFamily: mono, fontSize: 12, fontWeight: 600, color: "#8BC34A" }}>
                      {String(i + 1).padStart(2, "0")}
                    </span>
                    <span style={{ fontFamily: display, fontWeight: 700, fontSize: 17, color: "#0F172A" }}>{f.q}</span>
                  </span>
                  <span
                    style={{
                      fontSize: 24,
                      fontWeight: 600,
                      color: "#006D77",
                      flex: "none",
                      width: 24,
                      textAlign: "center",
                      lineHeight: 1,
                    }}
                  >
                    {isOpen ? "−" : "+"}
                  </span>
                </button>
                <div style={{ maxHeight: isOpen ? 240 : 0, overflow: "hidden", transition: "max-height .4s ease" }}>
                  <p style={{ padding: "0 26px 24px 56px", margin: 0, fontSize: 15, lineHeight: 1.6, color: "#64748B", fontWeight: 500 }}>
                    {f.a}
                  </p>
                </div>
              </div>
            );
          })}
        </div>
      </div>
    </section>
  );
}
