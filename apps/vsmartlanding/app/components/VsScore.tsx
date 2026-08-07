import type { ReactNode } from "react";
import { display, mono } from "./ui";

type Benefit = { bg: string; icon: ReactNode; label: string };

const benefits: Benefit[] = [
  {
    bg: "#E6F4F1",
    label: "Higher Credit Limit",
    icon: (
      <svg width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="#006D77" strokeWidth="1.9" strokeLinecap="round" strokeLinejoin="round">
        <path d="M3 17l6-6 4 4 8-8" />
        <path d="M21 3h-5M21 3v5" />
      </svg>
    ),
  },
  {
    bg: "#EAF7DE",
    label: "Faster Approvals",
    icon: (
      <svg width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="#3f6212" strokeWidth="1.9" strokeLinecap="round" strokeLinejoin="round">
        <path d="M13 2L4.5 13.5H11l-1 8.5L19 10h-6.5z" />
      </svg>
    ),
  },
  {
    bg: "#FEF3C7",
    label: "Special Offers",
    icon: (
      <svg width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="#b45309" strokeWidth="1.9" strokeLinecap="round" strokeLinejoin="round">
        <path d="M12 3l2.6 5.3 5.9.9-4.3 4.1 1 5.8L12 16.9 6.8 19.2l1-5.8L3.5 9.2l5.9-.9z" />
      </svg>
    ),
  },
  {
    bg: "#E6F4F1",
    label: "Lower Risk Rating",
    icon: (
      <svg width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="#006D77" strokeWidth="1.9" strokeLinecap="round" strokeLinejoin="round">
        <path d="M12 2.5l8 3.2v5.3c0 4.6-3.2 8.4-8 10-4.8-1.6-8-5.4-8-10V5.7z" />
      </svg>
    ),
  },
];

const boosts = ["On-time Payments", "Regular Purchases", "Full Settlements"];

export default function VsScore() {
  return (
    <section
      style={{
        padding: "clamp(64px,9vw,108px) clamp(16px,5vw,28px)",
        background: "radial-gradient(120% 80% at 85% 0%,#E6F4F1,#F8FAFC 58%)",
      }}
    >
      <div
        className="r-vsscore"
        style={{
          maxWidth: 1120,
          margin: "0 auto",
          display: "grid",
          gridTemplateColumns: ".92fr 1.08fr",
          gap: 60,
          alignItems: "center",
        }}
      >
        {/* score card */}
        <div
          data-reveal
          style={{
            position: "relative",
            background: "#fff",
            borderRadius: 30,
            padding: "clamp(22px,5vw,44px)",
            boxShadow: "0 40px 90px rgba(15,23,42,.12)",
            border: "1px solid rgba(15,23,42,.05)",
            textAlign: "center",
            overflow: "hidden",
          }}
        >
          <div
            style={{
              position: "absolute",
              top: 0,
              left: 0,
              right: 0,
              height: 5,
              background: "linear-gradient(90deg,#8BC34A,#006D77)",
            }}
          />
          <div style={{ display: "flex", alignItems: "center", justifyContent: "space-between" }}>
            <div
              style={{
                fontFamily: mono,
                fontSize: 11,
                fontWeight: 600,
                letterSpacing: ".1em",
                color: "#94A3B8",
                textTransform: "uppercase",
              }}
            >
              VS Score
            </div>
            <div
              style={{
                display: "inline-flex",
                alignItems: "center",
                gap: 6,
                background: "#EAF7DE",
                color: "#3f6212",
                fontSize: 11,
                fontWeight: 700,
                padding: "5px 11px",
                borderRadius: 999,
              }}
            >
              <span style={{ width: 6, height: 6, borderRadius: "50%", background: "#16A34A" }} />
              Excellent
            </div>
          </div>
          <div style={{ position: "relative", width: 236, height: 236, margin: "14px auto 10px" }}>
            <svg width="236" height="236" viewBox="0 0 236 236" style={{ transform: "rotate(-90deg)" }}>
              <circle cx="118" cy="118" r="100" fill="none" stroke="#EDF2F7" strokeWidth="22" />
              <circle
                id="vs-score-ring"
                cx="118"
                cy="118"
                r="100"
                fill="none"
                stroke="url(#vsgrad)"
                strokeWidth="22"
                strokeLinecap="round"
                strokeDasharray="628"
                strokeDashoffset="628"
                style={{ transition: "stroke-dashoffset 1.8s cubic-bezier(.16,1,.3,1)" }}
              />
              <defs>
                <linearGradient id="vsgrad" x1="0" y1="0" x2="1" y2="1">
                  <stop offset="0" stopColor="#8BC34A" />
                  <stop offset="1" stopColor="#006D77" />
                </linearGradient>
              </defs>
            </svg>
            <div
              style={{
                position: "absolute",
                inset: 0,
                display: "flex",
                flexDirection: "column",
                alignItems: "center",
                justifyContent: "center",
              }}
            >
              <div
                data-count
                data-target="820"
                style={{
                  fontFamily: display,
                  fontWeight: 800,
                  fontSize: 60,
                  lineHeight: 1,
                  color: "#0F172A",
                }}
              >
                820
              </div>
              <div
                style={{
                  fontFamily: mono,
                  fontSize: 11,
                  fontWeight: 600,
                  color: "#16A34A",
                  letterSpacing: ".04em",
                }}
              >
                +18 THIS MONTH
              </div>
            </div>
          </div>
          <div
            style={{
              display: "flex",
              justifyContent: "space-between",
              fontFamily: mono,
              fontSize: 11,
              fontWeight: 600,
              color: "#94A3B8",
              padding: "0 8px",
            }}
          >
            <span>300</span>
            <span style={{ color: "#CBD5E1" }}>range</span>
            <span>900</span>
          </div>
        </div>

        {/* benefits */}
        <div>
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
            03 — VS Credit Score
          </div>
          <h2
            style={{
              fontFamily: display,
              fontWeight: 800,
              fontSize: "clamp(28px,4.5vw,44px)",
              lineHeight: 1.03,
              letterSpacing: "-.035em",
              margin: "0 0 16px",
            }}
          >
            A higher score
            <br />
            unlocks more.
          </h2>
          <p
            style={{
              fontSize: 16,
              color: "#64748B",
              fontWeight: 500,
              margin: "0 0 28px",
              maxWidth: 480,
              lineHeight: 1.6,
            }}
          >
            Your VS Score reflects how you shop and repay. The better it gets, the more VS Mart
            rewards you.
          </p>
          <div className="r-vsscore-benefits" data-reveal-group style={{ display: "grid", gridTemplateColumns: "1fr 1fr", gap: 14, marginBottom: 24 }}>
            {benefits.map((b) => (
              <div
                key={b.label}
                className="lift3"
                style={{
                  background: "#fff",
                  borderRadius: 16,
                  padding: 18,
                  border: "1px solid rgba(15,23,42,.07)",
                  display: "flex",
                  alignItems: "center",
                  gap: 13,
                  transition: "transform .25s",
                }}
              >
                <span
                  style={{
                    width: 38,
                    height: 38,
                    borderRadius: 11,
                    background: b.bg,
                    display: "flex",
                    alignItems: "center",
                    justifyContent: "center",
                    flex: "none",
                  }}
                >
                  {b.icon}
                </span>
                <span style={{ fontSize: 14, fontWeight: 700 }}>{b.label}</span>
              </div>
            ))}
          </div>
          <div
            style={{
              background: "#06231f",
              borderRadius: 18,
              padding: "20px 24px",
              color: "#fff",
              display: "flex",
              alignItems: "center",
              gap: 24,
              flexWrap: "wrap",
            }}
          >
            <div
              style={{
                fontFamily: mono,
                fontSize: 11,
                fontWeight: 600,
                letterSpacing: ".1em",
                color: "#8BC34A",
                textTransform: "uppercase",
              }}
            >
              Boost your score
            </div>
            <div style={{ display: "flex", gap: 20, flexWrap: "wrap", fontSize: 14, fontWeight: 600 }}>
              {boosts.map((t) => (
                <span key={t} style={{ display: "flex", alignItems: "center", gap: 7 }}>
                  <svg width="15" height="15" viewBox="0 0 24 24" fill="none" stroke="#8BC34A" strokeWidth="2.4">
                    <path d="M5 12l4 4L19 6" />
                  </svg>
                  {t}
                </span>
              ))}
            </div>
          </div>
        </div>
      </div>
    </section>
  );
}
