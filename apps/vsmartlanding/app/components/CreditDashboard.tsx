import { display, mono } from "./ui";

const GREEN = "linear-gradient(#8BC34A,#6fae2f)";
const TEAL = "linear-gradient(#006D77,#024e56)";
const GOLD = "linear-gradient(#F4C430,#e0a800)";

const bars = [
  { h: "40%", grad: GREEN, delay: "0s" },
  { h: "62%", grad: GREEN, delay: ".1s" },
  { h: "48%", grad: GREEN, delay: ".2s" },
  { h: "80%", grad: TEAL, delay: ".3s" },
  { h: "55%", grad: GREEN, delay: ".4s" },
  { h: "70%", grad: GREEN, delay: ".5s" },
  { h: "92%", grad: GOLD, delay: ".6s" },
];

const checks = [
  "Live balances & available credit",
  "Automatic due-date reminders",
  "Full repayment history & statements",
];

export default function CreditDashboard() {
  return (
    <section
      style={{
        padding: "clamp(64px,8.5vw,100px) clamp(16px,5vw,28px)",
        background: "linear-gradient(160deg,#006D77,#024e56)",
        color: "#fff",
        position: "relative",
        overflow: "hidden",
      }}
    >
      <div
        style={{
          position: "absolute",
          bottom: -120,
          left: -60,
          width: 380,
          height: 380,
          borderRadius: "50%",
          background: "radial-gradient(circle,rgba(139,195,74,.28),transparent 70%)",
        }}
      />
      <div
        className="r-credit-grid"
        style={{
          position: "relative",
          maxWidth: 1200,
          margin: "0 auto",
          display: "grid",
          gridTemplateColumns: ".9fr 1.1fr",
          gap: 50,
          alignItems: "center",
        }}
      >
        <div data-reveal>
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
            06 — Credit Dashboard
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
            Your credit,
            <br />
            crystal clear.
          </h2>
          <p
            style={{
              fontSize: 16.5,
              color: "rgba(255,255,255,.82)",
              fontWeight: 500,
              margin: "0 0 26px",
              maxWidth: 440,
              lineHeight: 1.6,
            }}
          >
            Track limit, usage, outstanding and due dates in real time — with fintech-grade clarity.
          </p>
          <div
            style={{
              display: "flex",
              flexDirection: "column",
              gap: 13,
              fontSize: 14.5,
              fontWeight: 600,
              color: "rgba(255,255,255,.92)",
            }}
          >
            {checks.map((c) => (
              <span key={c} style={{ display: "flex", alignItems: "center", gap: 10 }}>
                <svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="#8BC34A" strokeWidth="2.4">
                  <path d="M5 12l4 4L19 6" />
                </svg>
                {c}
              </span>
            ))}
          </div>
        </div>

        <div
          data-reveal
          style={{
            background: "#fff",
            borderRadius: 26,
            padding: "clamp(16px,4vw,28px)",
            boxShadow: "0 40px 90px rgba(0,0,0,.3)",
            color: "#0F172A",
          }}
        >
          <div
            style={{
              display: "flex",
              justifyContent: "space-between",
              alignItems: "center",
              marginBottom: 20,
            }}
          >
            <div>
              <div style={{ fontFamily: mono, fontSize: 11, fontWeight: 600, color: "#94A3B8", letterSpacing: ".04em" }}>
                CREDIT LIMIT
              </div>
              <div style={{ fontFamily: display, fontWeight: 800, fontSize: 30 }}>₹25,000</div>
            </div>
            <div style={{ textAlign: "right" }}>
              <div style={{ fontFamily: mono, fontSize: 11, fontWeight: 600, color: "#94A3B8", letterSpacing: ".04em" }}>
                NEXT DUE
              </div>
              <div style={{ fontFamily: display, fontWeight: 800, fontSize: 18, color: "#F59E0B" }}>28 Jun</div>
            </div>
          </div>
          <div className="r-credit-stats" style={{ display: "grid", gridTemplateColumns: "1fr 1fr 1fr", gap: 12, marginBottom: 22 }}>
            <StatBox bg="#E6F4F1" label="AVAILABLE" labelColor="#006D77" value="₹20,800" valueColor="#006D77" />
            <StatBox bg="#FEF3C7" label="USED" labelColor="#b45309" value="₹4,200" valueColor="#b45309" />
            <StatBox bg="#FEE2E2" label="OUTSTANDING" labelColor="#dc2626" value="₹4,200" valueColor="#dc2626" />
          </div>
          <div
            style={{
              display: "flex",
              alignItems: "center",
              justifyContent: "space-between",
              marginBottom: 10,
            }}
          >
            <span style={{ fontFamily: mono, fontSize: 10.5, fontWeight: 600, color: "#94A3B8", letterSpacing: ".04em" }}>
              SPEND · LAST 7 DAYS
            </span>
            <span style={{ fontFamily: mono, fontSize: 10.5, fontWeight: 600, color: "#16A34A" }}>▲ 12%</span>
          </div>
          <div
            style={{
              display: "flex",
              alignItems: "flex-end",
              justifyContent: "space-between",
              gap: 8,
              height: 120,
              padding: 14,
              background: "#F8FAFC",
              borderRadius: 16,
            }}
          >
            {bars.map((b, i) => (
              <div
                key={i}
                data-bar
                data-h={b.h}
                style={{
                  flex: 1,
                  height: 0,
                  background: b.grad,
                  borderRadius: "6px 6px 3px 3px",
                  transition: `height 1.2s cubic-bezier(.16,1,.3,1) ${b.delay}`,
                }}
              />
            ))}
          </div>
        </div>
      </div>
    </section>
  );
}

function StatBox({
  bg,
  label,
  labelColor,
  value,
  valueColor,
}: {
  bg: string;
  label: string;
  labelColor: string;
  value: string;
  valueColor: string;
}) {
  return (
    <div style={{ background: bg, borderRadius: 14, padding: 14 }}>
      <div style={{ fontFamily: mono, fontSize: 10, fontWeight: 600, color: labelColor, letterSpacing: ".04em" }}>
        {label}
      </div>
      <div style={{ fontFamily: display, fontWeight: 800, fontSize: 19, color: valueColor }}>{value}</div>
    </div>
  );
}
