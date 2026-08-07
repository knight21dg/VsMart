import type { ReactNode } from "react";
import { display, mono } from "./ui";
import SectionHeader from "./SectionHeader";

type Capability = {
  icon: ReactNode;
  iconBg: string;
  num: string;
  title: string;
  bullets: string[];
};

const capabilities: Capability[] = [
  {
    iconBg: "#E6F4F1",
    num: "01",
    title: "Grocery Shopping",
    bullets: ["Categories & Search", "Cart & Wishlist", "Daily Offers"],
    icon: (
      <svg width="24" height="24" viewBox="0 0 24 24" fill="none" stroke="#006D77" strokeWidth="1.8" strokeLinecap="round" strokeLinejoin="round">
        <circle cx="9" cy="20" r="1.5" />
        <circle cx="18" cy="20" r="1.5" />
        <path d="M2 3h2.2l2.3 12.2a1.5 1.5 0 0 0 1.5 1.2h8.4a1.5 1.5 0 0 0 1.5-1.2L20.5 7H6" />
      </svg>
    ),
  },
  {
    iconBg: "#EAF7DE",
    num: "02",
    title: "Credit Purchases",
    bullets: ["Buy Now, Pay Later", "Weekly & Monthly Plans", "Flexible Credit Limit"],
    icon: (
      <svg width="24" height="24" viewBox="0 0 24 24" fill="none" stroke="#3f6212" strokeWidth="1.8" strokeLinecap="round" strokeLinejoin="round">
        <rect x="2.5" y="5" width="19" height="14" rx="2.5" />
        <path d="M2.5 9.5h19" />
        <path d="M6 14h3" />
      </svg>
    ),
  },
  {
    iconBg: "#FEF3C7",
    num: "03",
    title: "Order Tracking",
    bullets: ["Live GPS Tracking", "Delivery Updates", "Smart Notifications"],
    icon: (
      <svg width="24" height="24" viewBox="0 0 24 24" fill="none" stroke="#b45309" strokeWidth="1.8" strokeLinecap="round" strokeLinejoin="round">
        <path d="M12 21s-7-4.5-7-10a7 7 0 0 1 14 0c0 5.5-7 10-7 10z" />
        <circle cx="12" cy="11" r="2.4" />
      </svg>
    ),
  },
  {
    iconBg: "#E6F4F1",
    num: "04",
    title: "Payments",
    bullets: ["UPI & QR Pay", "Cash Collection", "Auto Reminders"],
    icon: (
      <svg width="24" height="24" viewBox="0 0 24 24" fill="none" stroke="#006D77" strokeWidth="1.8" strokeLinecap="round" strokeLinejoin="round">
        <rect x="3" y="6" width="18" height="12" rx="2.5" />
        <path d="M3 10h18" />
        <path d="M7 15h2" />
      </svg>
    ),
  },
];

export default function AppPreview() {
  return (
    <section id="app" style={{ padding: "clamp(64px,9vw,108px) clamp(16px,5vw,28px)", background: "#fff" }}>
      <div style={{ maxWidth: 1200, margin: "0 auto" }}>
        <SectionHeader
          eyebrow="01 — The App"
          title={
            <>
              Everything you need,
              <br />
              in one app.
            </>
          }
          lead="Shop groceries, buy on credit, track delivery and repay — four modules working as one."
          rightMax={340}
        />

        <div
          className="r-app-grid"
          style={{
            display: "grid",
            gridTemplateColumns: "0.86fr 1.14fr",
            gap: 24,
            alignItems: "stretch",
          }}
        >
          <PhoneShowcase />

          <div className="r-app-cards" data-reveal-group style={{ display: "grid", gridTemplateColumns: "1fr 1fr", gap: 18 }}>
            {capabilities.map((c) => (
              <div
                key={c.num}
                className="card-app"
                style={{
                  background: "#fff",
                  borderRadius: 22,
                  padding: 28,
                  border: "1px solid rgba(15,23,42,.08)",
                  boxShadow: "0 1px 0 rgba(15,23,42,.02)",
                  transition: "transform .3s, box-shadow .3s, border-color .3s",
                }}
              >
                <div
                  style={{
                    display: "flex",
                    alignItems: "center",
                    justifyContent: "space-between",
                    marginBottom: 20,
                  }}
                >
                  <div
                    style={{
                      width: 50,
                      height: 50,
                      borderRadius: 14,
                      background: c.iconBg,
                      display: "flex",
                      alignItems: "center",
                      justifyContent: "center",
                    }}
                  >
                    {c.icon}
                  </div>
                  <span style={{ fontFamily: mono, fontSize: 11, fontWeight: 600, color: "#CBD5E1" }}>
                    {c.num}
                  </span>
                </div>
                <h3 style={{ fontFamily: display, fontWeight: 700, fontSize: 20, margin: "0 0 12px" }}>
                  {c.title}
                </h3>
                <div style={{ display: "flex", flexDirection: "column", gap: 9 }}>
                  {c.bullets.map((b) => (
                    <div
                      key={b}
                      style={{
                        display: "flex",
                        alignItems: "center",
                        gap: 9,
                        fontSize: 13.5,
                        color: "#475569",
                        fontWeight: 600,
                      }}
                    >
                      <span style={{ width: 5, height: 5, borderRadius: "50%", background: "#8BC34A" }} />
                      {b}
                    </div>
                  ))}
                </div>
              </div>
            ))}
          </div>
        </div>
      </div>
    </section>
  );
}

function PhoneShowcase() {
  return (
    <div
      data-reveal
      style={{
        position: "relative",
        borderRadius: 30,
        background: "radial-gradient(120% 100% at 30% 0%,#E6F4F1,#F4F9F8 70%)",
        border: "1px solid rgba(15,23,42,.05)",
        padding: "44px 0 0",
        overflow: "hidden",
        display: "flex",
        justifyContent: "center",
        alignItems: "flex-end",
        minHeight: 520,
      }}
    >
      <div
        style={{
          position: "absolute",
          top: 26,
          left: 26,
          background: "#fff",
          borderRadius: 14,
          padding: "11px 14px",
          boxShadow: "0 14px 30px rgba(15,23,42,.1)",
          zIndex: 3,
          animation: "vsfloat 6s ease-in-out infinite",
        }}
      >
        <div style={{ fontFamily: mono, fontSize: 10, fontWeight: 600, color: "#94A3B8", letterSpacing: ".04em" }}>
          CART TOTAL
        </div>
        <div style={{ fontFamily: display, fontWeight: 800, fontSize: 18, color: "#006D77" }}>₹1,248</div>
      </div>
      <div
        style={{
          position: "absolute",
          top: 96,
          right: 24,
          background: "#0F172A",
          borderRadius: 14,
          padding: "11px 14px",
          boxShadow: "0 14px 30px rgba(15,23,42,.18)",
          zIndex: 3,
          animation: "vsfloat2 7.4s ease-in-out infinite",
        }}
      >
        <div style={{ fontFamily: mono, fontSize: 10, fontWeight: 600, color: "#8BC34A", letterSpacing: ".04em" }}>
          ETA
        </div>
        <div style={{ fontFamily: display, fontWeight: 800, fontSize: 16, color: "#fff" }}>8 min</div>
      </div>

      <div
        style={{
          position: "relative",
          width: 264,
          borderRadius: "34px 34px 0 0",
          background: "#0F172A",
          padding: "8px 8px 0",
          boxShadow: "0 30px 60px rgba(15,23,42,.22)",
        }}
      >
        <div style={{ borderRadius: "28px 28px 0 0", overflow: "hidden", background: "#F8FAFC" }}>
          <div style={{ background: "#006D77", padding: "16px 15px 15px", color: "#fff" }}>
            <div
              style={{
                display: "flex",
                justifyContent: "space-between",
                fontSize: 10,
                fontWeight: 700,
                opacity: 0.85,
              }}
            >
              <span>9:41</span>
              <span>VS Mart</span>
            </div>
            <div style={{ marginTop: 10, fontSize: 10, opacity: 0.85, fontWeight: 600 }}>Deliver to · Home</div>
            <div style={{ fontFamily: display, fontWeight: 800, fontSize: 15 }}>Whitefield, 560066</div>
            <div
              style={{
                marginTop: 11,
                background: "#fff",
                borderRadius: 11,
                padding: "9px 12px",
                display: "flex",
                alignItems: "center",
                gap: 8,
              }}
            >
              <svg width="13" height="13" viewBox="0 0 24 24" fill="none" stroke="#94A3B8" strokeWidth="2.4">
                <circle cx="11" cy="11" r="7" />
                <path d="M21 21l-4-4" />
              </svg>
              <span style={{ fontSize: 11, color: "#94A3B8", fontWeight: 500 }}>
                Search &quot;atta, milk, oil&quot;
              </span>
            </div>
          </div>
          <div style={{ padding: "12px 13px 0", display: "flex", gap: 7 }}>
            <div style={{ background: "#EAF7DE", color: "#3f6212", fontSize: 10, fontWeight: 700, padding: "6px 11px", borderRadius: 999 }}>
              Staples
            </div>
            <div style={{ background: "#fff", color: "#475569", fontSize: 10, fontWeight: 700, padding: "6px 11px", borderRadius: 999, border: "1px solid #E2E8F0" }}>
              Dairy
            </div>
            <div style={{ background: "#fff", color: "#475569", fontSize: 10, fontWeight: 700, padding: "6px 11px", borderRadius: 999, border: "1px solid #E2E8F0" }}>
              Snacks
            </div>
          </div>
          <div
            style={{
              margin: "12px 13px",
              background: "linear-gradient(100deg,#F4C430,#f0b429)",
              borderRadius: 14,
              padding: "12px 14px",
              display: "flex",
              alignItems: "center",
              justifyContent: "space-between",
            }}
          >
            <div>
              <div style={{ fontFamily: display, fontWeight: 800, fontSize: 14, color: "#0F172A" }}>10-min delivery</div>
              <div style={{ fontSize: 9.5, fontWeight: 600, color: "#0F172A", opacity: 0.8 }}>on 2,000+ daily items</div>
            </div>
            <div
              style={{
                width: 30,
                height: 30,
                borderRadius: 9,
                background: "rgba(15,23,42,.14)",
                display: "flex",
                alignItems: "center",
                justifyContent: "center",
              }}
            >
              <svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="#0F172A" strokeWidth="2">
                <path d="M5 12l5 5L20 7" />
              </svg>
            </div>
          </div>
          <div style={{ padding: "0 13px 16px", display: "grid", gridTemplateColumns: "1fr 1fr", gap: 10 }}>
            <ShowcaseProduct
              swatch="repeating-linear-gradient(135deg,#EDF7E3,#EDF7E3 6px,#E2F0D2 6px,#E2F0D2 12px)"
              name="Fortune Atta 5kg"
              price="₹249"
            />
            <ShowcaseProduct
              swatch="repeating-linear-gradient(135deg,#E6F4F1,#E6F4F1 6px,#D5ECE8 6px,#D5ECE8 12px)"
              name="Toned Milk 1L"
              price="₹54"
            />
          </div>
        </div>
      </div>
    </div>
  );
}

function ShowcaseProduct({ swatch, name, price }: { swatch: string; name: string; price: string }) {
  return (
    <div style={{ background: "#fff", borderRadius: 13, padding: 9, border: "1px solid rgba(15,23,42,.05)" }}>
      <div style={{ height: 50, borderRadius: 9, background: swatch }} />
      <div style={{ fontSize: 10, fontWeight: 700, marginTop: 6, color: "#0F172A" }}>{name}</div>
      <div style={{ display: "flex", alignItems: "center", justifyContent: "space-between", marginTop: 3 }}>
        <span style={{ fontSize: 11, fontWeight: 800, color: "#006D77" }}>{price}</span>
        <span
          style={{
            width: 22,
            height: 22,
            borderRadius: 7,
            background: "#8BC34A",
            color: "#fff",
            fontSize: 13,
            fontWeight: 800,
            display: "flex",
            alignItems: "center",
            justifyContent: "center",
          }}
        >
          +
        </span>
      </div>
    </div>
  );
}
