import type { ReactNode } from "react";
import { display, mono } from "./ui";

type Step = {
  num: string;
  label: string;
  labelColor: string;
  title: string;
  desc: string;
  descColor: string;
  numColor: string;
  iconBox: { background: string; border: string };
  icon: ReactNode;
  highlight?: boolean;
};

const steps: Step[] = [
  {
    num: "1",
    label: "REGISTER",
    labelColor: "#8BC34A",
    title: "Sign up free",
    desc: "Quick sign-up with Mobile OTP verification. No paperwork to start.",
    descColor: "rgba(255,255,255,.6)",
    numColor: "rgba(255,255,255,.1)",
    iconBox: { background: "rgba(139,195,74,.16)", border: "1px solid rgba(139,195,74,.4)" },
    icon: (
      <svg width="24" height="24" viewBox="0 0 24 24" fill="none" stroke="#8BC34A" strokeWidth="1.8" strokeLinecap="round" strokeLinejoin="round">
        <rect x="6" y="2.5" width="12" height="19" rx="2.5" />
        <path d="M11 18.5h2" />
      </svg>
    ),
  },
  {
    num: "2",
    label: "VERIFY",
    labelColor: "#8BC34A",
    title: "Verify identity",
    desc: "Aadhaar, PAN, selfie and address — verified securely in minutes.",
    descColor: "rgba(255,255,255,.6)",
    numColor: "rgba(255,255,255,.1)",
    iconBox: { background: "rgba(139,195,74,.16)", border: "1px solid rgba(139,195,74,.4)" },
    icon: (
      <svg width="24" height="24" viewBox="0 0 24 24" fill="none" stroke="#8BC34A" strokeWidth="1.8" strokeLinecap="round" strokeLinejoin="round">
        <path d="M12 2.5l8 3.2v5.3c0 4.6-3.2 8.4-8 10-4.8-1.6-8-5.4-8-10V5.7z" />
        <path d="M9 12l2 2 4-4" />
      </svg>
    ),
  },
  {
    num: "3",
    label: "APPROVE",
    labelColor: "#F4C430",
    title: "Get approved",
    desc: "Credit assessment generates your VS Score and personal limit.",
    descColor: "rgba(255,255,255,.6)",
    numColor: "rgba(255,255,255,.1)",
    iconBox: { background: "rgba(244,196,48,.16)", border: "1px solid rgba(244,196,48,.4)" },
    icon: (
      <svg width="24" height="24" viewBox="0 0 24 24" fill="none" stroke="#F4C430" strokeWidth="1.8" strokeLinecap="round" strokeLinejoin="round">
        <path d="M3 17l5-5 3 3 5-6 5 5" />
        <path d="M3 21h18" />
      </svg>
    ),
  },
  {
    num: "4",
    label: "SHOP",
    labelColor: "#bdf36a",
    title: "Shop now",
    desc: "Buy groceries on credit. Pay back weekly or monthly — your choice.",
    descColor: "rgba(255,255,255,.78)",
    numColor: "rgba(255,255,255,.22)",
    iconBox: { background: "#8BC34A", border: "none" },
    highlight: true,
    icon: (
      <svg width="24" height="24" viewBox="0 0 24 24" fill="none" stroke="#06231f" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round">
        <circle cx="9" cy="20" r="1.5" />
        <circle cx="18" cy="20" r="1.5" />
        <path d="M2 3h2.2l2.3 12.2a1.5 1.5 0 0 0 1.5 1.2h8.4a1.5 1.5 0 0 0 1.5-1.2L20.5 7H6" />
      </svg>
    ),
  },
];

export default function HowCreditWorks() {
  return (
    <section
      id="credit"
      style={{
        padding: "clamp(64px,9vw,108px) clamp(16px,5vw,28px)",
        background: "#06231f",
        color: "#fff",
        position: "relative",
        overflow: "hidden",
      }}
    >
      <div
        style={{
          position: "absolute",
          inset: 0,
          backgroundImage:
            "linear-gradient(rgba(255,255,255,.035) 1px,transparent 1px),linear-gradient(90deg,rgba(255,255,255,.035) 1px,transparent 1px)",
          backgroundSize: "40px 40px",
          maskImage: "radial-gradient(120% 90% at 50% 0%,#000,transparent 75%)",
          WebkitMaskImage: "radial-gradient(120% 90% at 50% 0%,#000,transparent 75%)",
        }}
      />
      <div
        style={{
          position: "absolute",
          top: -120,
          left: "8%",
          width: 380,
          height: 380,
          borderRadius: "50%",
          background: "radial-gradient(circle,rgba(0,109,119,.45),transparent 70%)",
        }}
      />
      <div
        style={{
          position: "absolute",
          bottom: -140,
          right: "6%",
          width: 340,
          height: 340,
          borderRadius: "50%",
          background: "radial-gradient(circle,rgba(139,195,74,.22),transparent 72%)",
        }}
      />
      <div style={{ position: "relative", maxWidth: 1200, margin: "0 auto" }}>
        <div
          data-reveal
          style={{
            display: "flex",
            justifyContent: "space-between",
            alignItems: "flex-end",
            gap: 40,
            flexWrap: "wrap",
            borderTop: "1px solid rgba(255,255,255,.14)",
            paddingTop: 26,
            marginBottom: 64,
          }}
        >
          <div style={{ maxWidth: 680 }}>
            <div
              style={{
                fontFamily: mono,
                fontSize: 12,
                fontWeight: 600,
                letterSpacing: ".14em",
                color: "#8BC34A",
                textTransform: "uppercase",
                marginBottom: 16,
              }}
            >
              02 — How VS Credit Works
            </div>
            <h2
              style={{
                fontFamily: display,
                fontWeight: 800,
                fontSize: "clamp(28px,5vw,48px)",
                lineHeight: 1.02,
                letterSpacing: "-.035em",
                margin: 0,
              }}
            >
              India&apos;s smart grocery
              <br />
              credit system.
            </h2>
          </div>
          <p
            style={{
              fontSize: 16,
              color: "rgba(255,255,255,.62)",
              fontWeight: 500,
              margin: 0,
              maxWidth: 320,
              lineHeight: 1.6,
            }}
          >
            From sign-up to checkout in four steps — most users get approved in minutes.
          </p>
        </div>

        <div
          className="r-steps"
          data-reveal-group
          style={{
            position: "relative",
            display: "grid",
            gridTemplateColumns: "repeat(4,1fr)",
            gap: 20,
          }}
        >
          <div
            className="r-steps-line"
            style={{
              position: "absolute",
              top: 46,
              left: "8%",
              right: "8%",
              height: 2,
              background: "linear-gradient(90deg,#8BC34A,#3aa39a 55%,#006D77)",
              opacity: 0.5,
            }}
          />

          {steps.map((s) => (
            <div
              key={s.num}
              style={
                s.highlight
                  ? {
                      position: "relative",
                      background: "linear-gradient(165deg,rgba(0,109,119,.55),rgba(0,109,119,.18))",
                      border: "1px solid rgba(139,195,74,.45)",
                      borderRadius: 22,
                      padding: "30px 24px",
                      boxShadow: "0 24px 60px rgba(0,109,119,.3)",
                    }
                  : {
                      position: "relative",
                      background: "rgba(255,255,255,.04)",
                      border: "1px solid rgba(255,255,255,.1)",
                      borderRadius: 22,
                      padding: "30px 24px",
                      backdropFilter: "blur(4px)",
                      WebkitBackdropFilter: "blur(4px)",
                    }
              }
            >
              <div
                style={{
                  display: "flex",
                  alignItems: "center",
                  justifyContent: "space-between",
                  marginBottom: 22,
                }}
              >
                <div
                  style={{
                    width: 54,
                    height: 54,
                    borderRadius: 16,
                    background: s.iconBox.background,
                    border: s.iconBox.border,
                    display: "flex",
                    alignItems: "center",
                    justifyContent: "center",
                  }}
                >
                  {s.icon}
                </div>
                <span
                  style={{
                    fontFamily: display,
                    fontWeight: 800,
                    fontSize: 44,
                    lineHeight: 1,
                    color: s.numColor,
                  }}
                >
                  {s.num}
                </span>
              </div>
              <div
                style={{
                  fontFamily: mono,
                  fontSize: 10.5,
                  fontWeight: 600,
                  letterSpacing: ".12em",
                  color: s.labelColor,
                  marginBottom: 8,
                }}
              >
                {s.label}
              </div>
              <h3 style={{ fontFamily: display, fontWeight: 700, fontSize: 20, margin: "0 0 8px" }}>
                {s.title}
              </h3>
              <p style={{ fontSize: 13.5, color: s.descColor, fontWeight: 500, margin: 0, lineHeight: 1.55 }}>
                {s.desc}
              </p>
            </div>
          ))}
        </div>
      </div>
    </section>
  );
}
