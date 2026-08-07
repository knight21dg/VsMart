import { display, mono } from "./ui";

function SideCard({
  quote,
  avatarBg,
  avatarColor,
  initial,
  name,
  location,
}: {
  quote: string;
  avatarBg: string;
  avatarColor: string;
  initial: string;
  name: string;
  location: string;
}) {
  return (
    <div
      style={{
        background: "#fff",
        borderRadius: 24,
        padding: 32,
        boxShadow: "0 18px 44px rgba(15,23,42,.06)",
        border: "1px solid rgba(15,23,42,.05)",
        marginTop: 20,
      }}
    >
      <div style={{ fontFamily: display, fontWeight: 800, fontSize: 48, lineHeight: 0.6, color: "#8BC34A", height: 26 }}>
        &ldquo;
      </div>
      <p style={{ fontSize: 16, lineHeight: 1.6, fontWeight: 600, color: "#0F172A", margin: "0 0 24px" }}>{quote}</p>
      <div
        style={{
          display: "flex",
          alignItems: "center",
          gap: 12,
          borderTop: "1px solid rgba(15,23,42,.07)",
          paddingTop: 18,
        }}
      >
        <div
          style={{
            width: 44,
            height: 44,
            borderRadius: "50%",
            background: avatarBg,
            display: "flex",
            alignItems: "center",
            justifyContent: "center",
            fontWeight: 800,
            color: avatarColor,
          }}
        >
          {initial}
        </div>
        <div>
          <div style={{ fontWeight: 700, fontSize: 14 }}>{name}</div>
          <div style={{ fontFamily: mono, fontSize: 11, color: "#94A3B8", fontWeight: 600 }}>{location}</div>
        </div>
      </div>
    </div>
  );
}

export default function Testimonials() {
  return (
    <section
      style={{
        padding: "clamp(64px,9vw,108px) clamp(16px,5vw,28px)",
        background: "radial-gradient(100% 80% at 20% 0%,#E6F4F1,#F8FAFC 60%)",
      }}
    >
      <div style={{ maxWidth: 1200, margin: "0 auto" }}>
        <div
          data-reveal
          style={{
            display: "flex",
            justifyContent: "space-between",
            alignItems: "flex-end",
            gap: 40,
            flexWrap: "wrap",
            borderTop: "1px solid rgba(15,23,42,.1)",
            paddingTop: 26,
            marginBottom: 52,
          }}
        >
          <div style={{ maxWidth: 620 }}>
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
              08 — Testimonials
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
              Loved by families
              <br />
              &amp; shopkeepers.
            </h2>
          </div>
          <div style={{ display: "flex", alignItems: "center", gap: 12 }}>
            <div style={{ color: "#F4C430", fontSize: 18, letterSpacing: 2 }}>★★★★★</div>
            <div style={{ fontFamily: mono, fontSize: 12, fontWeight: 600, color: "#64748B" }}>
              4.8 / 5 · 2,400+ reviews
            </div>
          </div>
        </div>

        <div className="r-testi-grid" data-reveal-group style={{ display: "grid", gridTemplateColumns: "1fr 1.15fr 1fr", gap: 20, alignItems: "start" }}>
          <SideCard
            quote="VS Mart helped me buy monthly groceries without any financial pressure."
            avatarBg="#E6F4F1"
            avatarColor="#006D77"
            initial="A"
            name="Anjali R."
            location="WHITEFIELD"
          />

          {/* featured */}
          <div
            style={{
              background: "linear-gradient(160deg,#006D77,#024e56)",
              borderRadius: 24,
              padding: "38px 34px",
              boxShadow: "0 30px 70px rgba(0,109,119,.28)",
              color: "#fff",
              position: "relative",
              overflow: "hidden",
            }}
          >
            <div
              style={{
                position: "absolute",
                top: -30,
                right: -20,
                width: 160,
                height: 160,
                borderRadius: "50%",
                background: "radial-gradient(circle,rgba(139,195,74,.3),transparent 70%)",
              }}
            />
            <div style={{ position: "relative" }}>
              <div style={{ color: "#F4C430", fontSize: 16, letterSpacing: 2, marginBottom: 16 }}>★★★★★</div>
              <p
                style={{
                  fontSize: 20,
                  lineHeight: 1.5,
                  fontWeight: 700,
                  fontFamily: display,
                  margin: "0 0 28px",
                  letterSpacing: "-.01em",
                }}
              >
                Fast delivery and easy repayments — exactly what my shop needed to keep customers
                coming back.
              </p>
              <div
                style={{
                  display: "flex",
                  alignItems: "center",
                  gap: 12,
                  borderTop: "1px solid rgba(255,255,255,.18)",
                  paddingTop: 20,
                }}
              >
                <div
                  style={{
                    width: 46,
                    height: 46,
                    borderRadius: "50%",
                    background: "#8BC34A",
                    display: "flex",
                    alignItems: "center",
                    justifyContent: "center",
                    fontWeight: 800,
                    color: "#06231f",
                  }}
                >
                  M
                </div>
                <div>
                  <div style={{ fontWeight: 700, fontSize: 15 }}>Mahesh K.</div>
                  <div style={{ fontFamily: mono, fontSize: 11, color: "rgba(255,255,255,.7)", fontWeight: 600 }}>
                    HOSKOTE · STORE OWNER
                  </div>
                </div>
              </div>
            </div>
          </div>

          <SideCard
            quote="The credit facility is extremely useful for running my household every month."
            avatarBg="#FEF3C7"
            avatarColor="#b45309"
            initial="S"
            name="Sunita D."
            location="DEVANAHALLI"
          />
        </div>
      </div>
    </section>
  );
}
