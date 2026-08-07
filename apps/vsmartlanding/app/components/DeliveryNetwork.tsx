import { display, mono } from "./ui";
import SectionHeader from "./SectionHeader";

export default function DeliveryNetwork() {
  return (
    <section id="delivery" style={{ padding: "clamp(64px,9vw,108px) clamp(16px,5vw,28px)", background: "#fff" }}>
      <div style={{ maxWidth: 1200, margin: "0 auto" }}>
        <SectionHeader
          eyebrow="07 — Delivery Network"
          title={
            <>
              Serving communities,
              <br />
              efficiently.
            </>
          }
          lead="A dense local network across zones, areas, villages and partner stores."
          leftMax={660}
        />

        <div className="r-delivery-grid" style={{ display: "grid", gridTemplateColumns: "1.25fr .75fr", gap: 20, alignItems: "stretch" }}>
          {/* map */}
          <div
            data-reveal
            style={{
              position: "relative",
              borderRadius: 26,
              overflow: "hidden",
              background: "linear-gradient(160deg,#0B2A2E,#06231f)",
              minHeight: 400,
              padding: 28,
              color: "#fff",
            }}
          >
            <div
              style={{
                position: "absolute",
                inset: 0,
                backgroundImage:
                  "linear-gradient(rgba(255,255,255,.045) 1px,transparent 1px),linear-gradient(90deg,rgba(255,255,255,.045) 1px,transparent 1px)",
                backgroundSize: "38px 38px",
              }}
            />
            <svg style={{ position: "absolute", inset: 0, width: "100%", height: "100%" }} preserveAspectRatio="none">
              <line x1="30%" y1="38%" x2="54%" y2="60%" stroke="rgba(139,195,74,.35)" strokeWidth="1.5" strokeDasharray="5 5" />
              <line x1="54%" y1="60%" x2="72%" y2="44%" stroke="rgba(244,196,48,.3)" strokeWidth="1.5" strokeDasharray="5 5" />
              <line x1="30%" y1="38%" x2="22%" y2="74%" stroke="rgba(255,255,255,.18)" strokeWidth="1.5" strokeDasharray="5 5" />
            </svg>
            <div
              style={{
                position: "absolute",
                top: "38%",
                left: "30%",
                width: 120,
                height: 120,
                border: "1.5px solid rgba(139,195,74,.25)",
                borderRadius: "50%",
                transform: "translate(-50%,-50%)",
              }}
            />
            <div
              style={{
                position: "absolute",
                top: "38%",
                left: "30%",
                width: 200,
                height: 200,
                border: "1.5px solid rgba(139,195,74,.12)",
                borderRadius: "50%",
                transform: "translate(-50%,-50%)",
              }}
            />
            <div
              style={{
                position: "absolute",
                top: "38%",
                left: "30%",
                width: 16,
                height: 16,
                borderRadius: "50%",
                background: "#8BC34A",
                boxShadow: "0 0 0 8px rgba(139,195,74,.2)",
                transform: "translate(-50%,-50%)",
                animation: "vspulse 3s infinite",
              }}
            />
            <div
              style={{
                position: "absolute",
                top: "60%",
                left: "54%",
                width: 14,
                height: 14,
                borderRadius: "50%",
                background: "#F4C430",
                boxShadow: "0 0 0 7px rgba(244,196,48,.2)",
                transform: "translate(-50%,-50%)",
                animation: "vspulse 3.4s infinite",
              }}
            />
            <div
              style={{
                position: "absolute",
                top: "44%",
                left: "72%",
                width: 13,
                height: 13,
                borderRadius: "50%",
                background: "#fff",
                boxShadow: "0 0 0 7px rgba(255,255,255,.14)",
                transform: "translate(-50%,-50%)",
                animation: "vspulse 4s infinite",
              }}
            />
            <div
              style={{
                position: "absolute",
                top: "74%",
                left: "22%",
                width: 11,
                height: 11,
                borderRadius: "50%",
                background: "#8BC34A",
                opacity: 0.85,
                transform: "translate(-50%,-50%)",
              }}
            />
            <div
              style={{
                position: "relative",
                display: "inline-flex",
                flexDirection: "column",
                gap: 2,
                background: "rgba(255,255,255,.07)",
                border: "1px solid rgba(255,255,255,.12)",
                borderRadius: 14,
                padding: "14px 18px",
                backdropFilter: "blur(6px)",
                WebkitBackdropFilter: "blur(6px)",
              }}
            >
              <div
                style={{
                  fontFamily: mono,
                  fontSize: 11,
                  fontWeight: 600,
                  color: "#8BC34A",
                  letterSpacing: ".08em",
                  display: "flex",
                  alignItems: "center",
                  gap: 7,
                }}
              >
                <span style={{ width: 7, height: 7, borderRadius: "50%", background: "#8BC34A" }} />
                LIVE COVERAGE
              </div>
              <div style={{ fontFamily: display, fontWeight: 800, fontSize: 20 }}>Zones · Areas · Villages</div>
            </div>
            <div
              style={{
                position: "absolute",
                bottom: 24,
                right: 24,
                display: "flex",
                gap: 16,
                fontFamily: mono,
                fontSize: 10.5,
                fontWeight: 600,
                color: "rgba(255,255,255,.7)",
              }}
            >
              <span style={{ display: "flex", alignItems: "center", gap: 6 }}>
                <span style={{ width: 8, height: 8, borderRadius: "50%", background: "#8BC34A" }} />
                Stores
              </span>
              <span style={{ display: "flex", alignItems: "center", gap: 6 }}>
                <span style={{ width: 8, height: 8, borderRadius: "50%", background: "#F4C430" }} />
                Agents
              </span>
              <span style={{ display: "flex", alignItems: "center", gap: 6 }}>
                <span style={{ width: 8, height: 8, borderRadius: "50%", background: "#fff" }} />
                Hubs
              </span>
            </div>
          </div>

          {/* stats */}
          <div className="r-delivery-stats" data-reveal-group style={{ display: "grid", gridTemplateColumns: "1fr 1fr", gap: 16 }}>
            <StatTile target="50" suffix="+" display="50+" valueColor="#006D77" label="SERVICE AREAS" />
            <StatTile target="10000" suffix="+" display="10000+" valueColor="#8BC34A" label="CUSTOMERS" />
            <StatTile target="5000" suffix="+" display="5000+" valueColor="#F59E0B" label="DELIVERIES" />
            <StatTile
              target="99"
              suffix="%"
              display="99%"
              valueColor="#fff"
              label="SUCCESS RATE"
              dark
            />
          </div>
        </div>
      </div>
    </section>
  );
}

function StatTile({
  target,
  suffix,
  display: displayValue,
  valueColor,
  label,
  dark,
}: {
  target: string;
  suffix: string;
  display: string;
  valueColor: string;
  label: string;
  dark?: boolean;
}) {
  return (
    <div
      style={{
        background: dark ? "#06231f" : "#F8FAFC",
        borderRadius: 20,
        padding: "26px 22px",
        border: "1px solid rgba(15,23,42,.06)",
        display: "flex",
        flexDirection: "column",
        justifyContent: "center",
      }}
    >
      <div
        data-count
        data-target={target}
        data-suffix={suffix}
        style={{ fontFamily: display, fontWeight: 800, fontSize: 40, color: valueColor, lineHeight: 1 }}
      >
        {displayValue}
      </div>
      <div
        style={{
          fontFamily: mono,
          fontSize: 11,
          fontWeight: 600,
          color: dark ? "#8BC34A" : "#64748B",
          letterSpacing: ".04em",
          marginTop: 8,
        }}
      >
        {label}
      </div>
    </div>
  );
}
