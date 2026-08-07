import type { ReactNode } from "react";
import { display, mono } from "./ui";
import SectionHeader from "./SectionHeader";

type Card = { num: string; bg: string; title: string; desc: string; icon: ReactNode };

const middleCards: Card[] = [
  {
    num: "02",
    bg: "#EAF7DE",
    title: "Instant Delivery",
    desc: "A fast local network built for your neighbourhood.",
    icon: (
      <svg width="22" height="22" viewBox="0 0 24 24" fill="none" stroke="#3f6212" strokeWidth="1.8" strokeLinecap="round" strokeLinejoin="round">
        <path d="M1 4h13v11H1z" />
        <path d="M14 8h4l3 3v4h-7" />
        <circle cx="6" cy="18" r="1.8" />
        <circle cx="17" cy="18" r="1.8" />
      </svg>
    ),
  },
  {
    num: "03",
    bg: "#FEF3C7",
    title: "Credit Purchases",
    desc: "Buy now and pay later — weekly or monthly.",
    icon: (
      <svg width="22" height="22" viewBox="0 0 24 24" fill="none" stroke="#b45309" strokeWidth="1.8" strokeLinecap="round" strokeLinejoin="round">
        <rect x="2.5" y="5" width="19" height="14" rx="2.5" />
        <path d="M2.5 9.5h19" />
        <path d="M6 14h3" />
      </svg>
    ),
  },
  {
    num: "04",
    bg: "#E6F4F1",
    title: "Smart Collections",
    desc: "OTP-based collections keep repayments verified.",
    icon: (
      <svg width="22" height="22" viewBox="0 0 24 24" fill="none" stroke="#006D77" strokeWidth="1.8" strokeLinecap="round" strokeLinejoin="round">
        <path d="M12 2.5l8 3.2v5.3c0 4.6-3.2 8.4-8 10-4.8-1.6-8-5.4-8-10V5.7z" />
        <path d="M9 12l2 2 4-4" />
      </svg>
    ),
  },
  {
    num: "05",
    bg: "#EAF7DE",
    title: "Order Tracking",
    desc: "Real-time updates from cart to doorstep.",
    icon: (
      <svg width="22" height="22" viewBox="0 0 24 24" fill="none" stroke="#3f6212" strokeWidth="1.8" strokeLinecap="round" strokeLinejoin="round">
        <path d="M12 21s-7-4.5-7-10a7 7 0 0 1 14 0c0 5.5-7 10-7 10z" />
        <circle cx="12" cy="11" r="2.4" />
      </svg>
    ),
  },
  {
    num: "06",
    bg: "#E6F4F1",
    title: "Secure Payments",
    desc: "Encrypted across UPI, QR and cash.",
    icon: (
      <svg width="22" height="22" viewBox="0 0 24 24" fill="none" stroke="#006D77" strokeWidth="1.8" strokeLinecap="round" strokeLinejoin="round">
        <rect x="4" y="10" width="16" height="11" rx="2.5" />
        <path d="M8 10V7a4 4 0 0 1 8 0v3" />
      </svg>
    ),
  },
];

export default function Features() {
  return (
    <section style={{ padding: "clamp(64px,9vw,108px) clamp(16px,5vw,28px)", background: "#fff" }}>
      <div style={{ maxWidth: 1200, margin: "0 auto" }}>
        <SectionHeader
          eyebrow="04 — Platform"
          title={
            <>
              Built for shoppers,
              <br />
              stores &amp; agents.
            </>
          }
          lead="One platform, eight capabilities — covering the full grocery-credit journey."
        />

        <div className="r-features" data-reveal-group style={{ display: "grid", gridTemplateColumns: "repeat(4,1fr)", gap: 16 }}>
          {/* Anchor card 01 */}
          <div
            className="r-feature-anchor"
            style={{
              gridColumn: "span 2",
              background: "linear-gradient(150deg,#006D77,#024e56)",
              color: "#fff",
              borderRadius: 22,
              padding: 30,
              position: "relative",
              overflow: "hidden",
              display: "flex",
              flexDirection: "column",
              justifyContent: "space-between",
              minHeight: 210,
            }}
          >
            <div
              style={{
                position: "absolute",
                top: -40,
                right: -30,
                width: 180,
                height: 180,
                borderRadius: "50%",
                background: "radial-gradient(circle,rgba(139,195,74,.32),transparent 70%)",
              }}
            />
            <div
              style={{
                position: "relative",
                display: "flex",
                alignItems: "center",
                justifyContent: "space-between",
              }}
            >
              <div
                style={{
                  width: 50,
                  height: 50,
                  borderRadius: 14,
                  background: "rgba(255,255,255,.16)",
                  display: "flex",
                  alignItems: "center",
                  justifyContent: "center",
                }}
              >
                <svg width="24" height="24" viewBox="0 0 24 24" fill="none" stroke="#fff" strokeWidth="1.8" strokeLinecap="round" strokeLinejoin="round">
                  <path d="M3 9l1.5-5h15L21 9" />
                  <path d="M3 9h18v3a3 3 0 0 1-6 0 3 3 0 0 1-6 0 3 3 0 0 1-6 0z" />
                  <path d="M5 13v7h14v-7" />
                </svg>
              </div>
              <span style={{ fontFamily: mono, fontSize: 11, fontWeight: 600, color: "rgba(255,255,255,.4)" }}>
                01
              </span>
            </div>
            <div style={{ position: "relative" }}>
              <h3 style={{ fontFamily: display, fontWeight: 800, fontSize: 24, margin: "0 0 8px" }}>
                Grocery Marketplace
              </h3>
              <p
                style={{
                  fontSize: 14.5,
                  color: "rgba(255,255,255,.82)",
                  fontWeight: 500,
                  margin: 0,
                  lineHeight: 1.55,
                  maxWidth: 360,
                }}
              >
                Thousands of products across staples, fresh produce and daily essentials —
                restocked continuously.
              </p>
            </div>
          </div>

          {/* Middle light cards */}
          {middleCards.map((c) => (
            <div
              key={c.num}
              className="card-feature"
              style={{
                background: "#F8FAFC",
                borderRadius: 22,
                padding: 26,
                border: "1px solid rgba(15,23,42,.07)",
                transition: "transform .3s, box-shadow .3s",
              }}
            >
              <div
                style={{
                  display: "flex",
                  alignItems: "center",
                  justifyContent: "space-between",
                  marginBottom: 18,
                }}
              >
                <div
                  style={{
                    width: 46,
                    height: 46,
                    borderRadius: 13,
                    background: c.bg,
                    display: "flex",
                    alignItems: "center",
                    justifyContent: "center",
                  }}
                >
                  {c.icon}
                </div>
                <span style={{ fontFamily: mono, fontSize: 11, fontWeight: 600, color: "#CBD5E1" }}>{c.num}</span>
              </div>
              <h3 style={{ fontFamily: display, fontWeight: 700, fontSize: 18, margin: "0 0 6px" }}>{c.title}</h3>
              <p style={{ fontSize: 13.5, color: "#64748B", fontWeight: 500, margin: 0, lineHeight: 1.5 }}>
                {c.desc}
              </p>
            </div>
          ))}

          {/* Anchor card 08 (dark) */}
          <div
            className="card-feature-dark"
            style={{
              background: "#0F172A",
              color: "#fff",
              borderRadius: 22,
              padding: 26,
              border: "1px solid rgba(15,23,42,.07)",
              transition: "transform .3s, box-shadow .3s",
            }}
          >
            <div
              style={{
                display: "flex",
                alignItems: "center",
                justifyContent: "space-between",
                marginBottom: 18,
              }}
            >
              <div
                style={{
                  width: 46,
                  height: 46,
                  borderRadius: 13,
                  background: "rgba(139,195,74,.18)",
                  display: "flex",
                  alignItems: "center",
                  justifyContent: "center",
                }}
              >
                <svg width="22" height="22" viewBox="0 0 24 24" fill="none" stroke="#8BC34A" strokeWidth="1.8" strokeLinecap="round" strokeLinejoin="round">
                  <path d="M3 3v18h18" />
                  <path d="M7 14l3-3 3 3 5-6" />
                </svg>
              </div>
              <span style={{ fontFamily: mono, fontSize: 11, fontWeight: 600, color: "rgba(255,255,255,.3)" }}>07</span>
            </div>
            <h3 style={{ fontFamily: display, fontWeight: 700, fontSize: 18, margin: "0 0 6px" }}>Analytics</h3>
            <p style={{ fontSize: 13.5, color: "rgba(255,255,255,.6)", fontWeight: 500, margin: 0, lineHeight: 1.5 }}>
              Track orders, spend and payments clearly.
            </p>
          </div>
        </div>
      </div>
    </section>
  );
}
