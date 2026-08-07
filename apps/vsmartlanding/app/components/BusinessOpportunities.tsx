import { display } from "./ui";
import SectionHeader from "./SectionHeader";
import LeadForm from "./LeadForm";

export default function BusinessOpportunities() {
  return (
    <section style={{ padding: "clamp(56px,8vw,96px) clamp(16px,5vw,28px)", background: "#fff" }}>
      <div style={{ maxWidth: 1200, margin: "0 auto" }}>
        <SectionHeader
          eyebrow="09 — Partner With Us"
          title={
            <>
              Grow your business
              <br />
              with VS Mart.
            </>
          }
          lead="Join as a delivery partner or open a franchise store — we'll get you running fast."
        />

        <div className="r-biz-grid" data-reveal-group style={{ display: "grid", gridTemplateColumns: "1fr 1fr 1.1fr", gap: 20, alignItems: "stretch" }}>
          {/* Delivery partner */}
          <div
            style={{
              background: "linear-gradient(160deg,#006D77,#024e56)",
              color: "#fff",
              borderRadius: 24,
              padding: 32,
              display: "flex",
              flexDirection: "column",
              justifyContent: "space-between",
              minHeight: 268,
              position: "relative",
              overflow: "hidden",
            }}
          >
            <div
              style={{
                position: "absolute",
                top: -30,
                right: -20,
                width: 150,
                height: 150,
                borderRadius: "50%",
                background: "radial-gradient(circle,rgba(139,195,74,.28),transparent 70%)",
              }}
            />
            <div style={{ position: "relative" }}>
              <div
                style={{
                  width: 52,
                  height: 52,
                  borderRadius: 14,
                  background: "rgba(255,255,255,.16)",
                  display: "flex",
                  alignItems: "center",
                  justifyContent: "center",
                  marginBottom: 22,
                }}
              >
                <svg width="26" height="26" viewBox="0 0 24 24" fill="none" stroke="#fff" strokeWidth="1.8" strokeLinecap="round" strokeLinejoin="round">
                  <circle cx="6" cy="18" r="2.4" />
                  <circle cx="16" cy="18" r="2.4" />
                  <path d="M2 4h3l2.5 9.5h8L18 7H7" />
                </svg>
              </div>
              <h3 style={{ fontFamily: display, fontWeight: 800, fontSize: 24, margin: "0 0 8px" }}>
                Become a Delivery Partner
              </h3>
              <p style={{ fontSize: 14.5, color: "rgba(255,255,255,.82)", fontWeight: 500, margin: 0, lineHeight: 1.55 }}>
                Earn flexibly with delivery and collection routes in your area.
              </p>
            </div>
            <span
              style={{
                position: "relative",
                marginTop: 22,
                display: "inline-flex",
                alignItems: "center",
                gap: 8,
                fontWeight: 700,
                fontSize: 14,
                color: "#8BC34A",
              }}
            >
              Apply as Agent{" "}
              <svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="#8BC34A" strokeWidth="2.2">
                <path d="M5 12h14M13 6l6 6-6 6" />
              </svg>
            </span>
          </div>

          {/* Franchise */}
          <div
            style={{
              background: "linear-gradient(160deg,#8BC34A,#6fae2f)",
              color: "#0F172A",
              borderRadius: 24,
              padding: 32,
              display: "flex",
              flexDirection: "column",
              justifyContent: "space-between",
              minHeight: 268,
              position: "relative",
              overflow: "hidden",
            }}
          >
            <div style={{ position: "relative" }}>
              <div
                style={{
                  width: 52,
                  height: 52,
                  borderRadius: 14,
                  background: "rgba(15,23,42,.14)",
                  display: "flex",
                  alignItems: "center",
                  justifyContent: "center",
                  marginBottom: 22,
                }}
              >
                <svg width="26" height="26" viewBox="0 0 24 24" fill="none" stroke="#0F172A" strokeWidth="1.8" strokeLinecap="round" strokeLinejoin="round">
                  <path d="M3 9l1.5-5h15L21 9" />
                  <path d="M3 9h18v3a3 3 0 0 1-6 0 3 3 0 0 1-6 0 3 3 0 0 1-6 0z" />
                  <path d="M5 13v7h14v-7" />
                </svg>
              </div>
              <h3 style={{ fontFamily: display, fontWeight: 800, fontSize: 24, margin: "0 0 8px" }}>
                Franchise Expansion
              </h3>
              <p style={{ fontSize: 14.5, color: "rgba(15,23,42,.78)", fontWeight: 600, margin: 0, lineHeight: 1.55 }}>
                Open a new VS Mart store and bring grocery-credit to your town.
              </p>
            </div>
            <span
              style={{
                position: "relative",
                marginTop: 22,
                display: "inline-flex",
                alignItems: "center",
                gap: 8,
                fontWeight: 800,
                fontSize: 14,
                color: "#0F172A",
              }}
            >
              Open New Store{" "}
              <svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="#0F172A" strokeWidth="2.2">
                <path d="M5 12h14M13 6l6 6-6 6" />
              </svg>
            </span>
          </div>

          <LeadForm />
        </div>
      </div>
    </section>
  );
}
