import type { ReactNode } from "react";
import { Fragment } from "react";
import { display, mono } from "./ui";
import SectionHeader from "./SectionHeader";

type Node = {
  badge: string;
  iconBg: string;
  icon: ReactNode;
  title: string;
  sub: string;
  dark?: boolean;
};

const nodes: Node[] = [
  {
    badge: "A1",
    iconBg: "#006D77",
    title: "Customer App",
    sub: "Shop & Credit",
    icon: (
      <svg width="24" height="24" viewBox="0 0 24 24" fill="none" stroke="#fff" strokeWidth="1.8" strokeLinecap="round" strokeLinejoin="round">
        <circle cx="12" cy="8" r="4" />
        <path d="M4 21c0-4 3.5-6 8-6s8 2 8 6" />
      </svg>
    ),
  },
  {
    badge: "A2",
    iconBg: "#F4C430",
    title: "Store Operations",
    sub: "Inventory + Billing",
    icon: (
      <svg width="24" height="24" viewBox="0 0 24 24" fill="none" stroke="#0F172A" strokeWidth="1.8" strokeLinecap="round" strokeLinejoin="round">
        <path d="M3 21V8l9-5 9 5v13" />
        <path d="M3 21h18" />
        <path d="M9 21v-6h6v6" />
      </svg>
    ),
  },
  {
    badge: "A3",
    iconBg: "#8BC34A",
    title: "Agent App",
    sub: "Collection + Delivery",
    icon: (
      <svg width="24" height="24" viewBox="0 0 24 24" fill="none" stroke="#0F172A" strokeWidth="1.8" strokeLinecap="round" strokeLinejoin="round">
        <circle cx="6" cy="18" r="2.4" />
        <circle cx="16" cy="18" r="2.4" />
        <path d="M2 4h3l2.5 9.5h8L18 7H7" />
      </svg>
    ),
  },
  {
    badge: "A4",
    iconBg: "rgba(139,195,74,.18)",
    title: "Admin Center",
    sub: "Manage the Business",
    dark: true,
    icon: (
      <svg width="24" height="24" viewBox="0 0 24 24" fill="none" stroke="#8BC34A" strokeWidth="1.8" strokeLinecap="round" strokeLinejoin="round">
        <circle cx="12" cy="12" r="3" />
        <path d="M12 2v3M12 19v3M2 12h3M19 12h3M5 5l2 2M17 17l2 2M19 5l-2 2M7 17l-2 2" />
      </svg>
    ),
  },
];

function Arrow() {
  return (
    <div className="r-eco-arrow" style={{ display: "flex", alignItems: "center", justifyContent: "center", padding: "0 8px" }}>
      <svg width="26" height="16" viewBox="0 0 26 16" fill="none" stroke="#94A3B8" strokeWidth="1.8" strokeLinecap="round" strokeLinejoin="round">
        <path d="M1 8h22M18 3l5 5-5 5" />
      </svg>
    </div>
  );
}

export default function Ecosystem() {
  return (
    <section id="ecosystem" style={{ padding: "clamp(64px,9vw,108px) clamp(16px,5vw,28px)", background: "#F4F7F6" }}>
      <div style={{ maxWidth: 1200, margin: "0 auto" }}>
        <SectionHeader
          eyebrow="05 — The Ecosystem"
          title={
            <>
              One platform.
              <br />
              Multiple solutions.
            </>
          }
          lead="Four connected apps move every order from the customer to the admin — seamlessly."
          leftMax={660}
          rightMax={340}
          marginBottom={56}
        />

        <div
          className="r-eco-grid"
          data-reveal-group
          style={{
            position: "relative",
            display: "grid",
            gridTemplateColumns: "1fr auto 1fr auto 1fr auto 1fr",
            alignItems: "stretch",
            gap: 0,
          }}
        >
          {nodes.map((n, i) => (
            <Fragment key={n.badge}>
              <div
                style={{
                  background: n.dark ? "#0F172A" : "#fff",
                  color: n.dark ? "#fff" : undefined,
                  borderRadius: 22,
                  padding: "30px 26px",
                  border: "1px solid rgba(15,23,42,.06)",
                  boxShadow: n.dark
                    ? "0 16px 40px rgba(15,23,42,.16)"
                    : "0 12px 34px rgba(15,23,42,.05)",
                }}
              >
                <div
                  style={{
                    display: "flex",
                    alignItems: "center",
                    justifyContent: "space-between",
                    marginBottom: 60,
                  }}
                >
                  <div
                    style={{
                      width: 52,
                      height: 52,
                      borderRadius: 14,
                      background: n.iconBg,
                      display: "flex",
                      alignItems: "center",
                      justifyContent: "center",
                    }}
                  >
                    {n.icon}
                  </div>
                  <span
                    style={{
                      fontFamily: mono,
                      fontSize: 11,
                      fontWeight: 600,
                      color: n.dark ? "rgba(255,255,255,.3)" : "#CBD5E1",
                    }}
                  >
                    {n.badge}
                  </span>
                </div>
                <h3 style={{ fontFamily: display, fontWeight: 700, fontSize: 19, margin: "0 0 6px" }}>
                  {n.title}
                </h3>
                <p
                  style={{
                    fontSize: 13.5,
                    color: n.dark ? "rgba(255,255,255,.6)" : "#64748B",
                    fontWeight: 600,
                    margin: 0,
                  }}
                >
                  {n.sub}
                </p>
              </div>
              {i < nodes.length - 1 && <Arrow />}
            </Fragment>
          ))}
        </div>
      </div>
    </section>
  );
}
