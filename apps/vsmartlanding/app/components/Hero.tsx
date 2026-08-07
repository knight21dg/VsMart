import Image from "next/image";
import { display } from "./ui";
import vsmartLogo from "../../public/assets/vsmart-appicon.png";

const trust = [
  "OTP Verified Users",
  "Secure Payments",
  "Credit Approval System",
  "GPS Enabled Delivery",
];

export default function Hero() {
  return (
    <header
      id="top"
      style={{
        position: "relative",
        padding: "clamp(48px,7vw,64px) clamp(16px,5vw,28px) clamp(64px,9vw,92px)",
        background:
          "radial-gradient(120% 90% at 12% 0%,#E6F4F1 0%,#F8FAFC 46%,#F8FAFC 100%)",
        overflow: "hidden",
      }}
    >
      <div
        style={{
          position: "absolute",
          top: -120,
          right: -80,
          width: 420,
          height: 420,
          borderRadius: "50%",
          background: "radial-gradient(circle,rgba(139,195,74,.32),transparent 68%)",
          filter: "blur(8px)",
          animation: "vspulse 7s ease-in-out infinite",
        }}
      />
      <div
        style={{
          position: "absolute",
          bottom: -160,
          left: -100,
          width: 480,
          height: 480,
          borderRadius: "50%",
          background: "radial-gradient(circle,rgba(0,109,119,.16),transparent 70%)",
          animation: "vspulse 9s ease-in-out infinite",
        }}
      />
      <div
        className="r-hero-grid"
        style={{
          position: "relative",
          maxWidth: 1200,
          margin: "0 auto",
          display: "grid",
          gridTemplateColumns: "1.05fr .95fr",
          gap: 48,
          alignItems: "center",
        }}
      >
        {/* LEFT */}
        <div className="r-hero-copy">
          <Image
            src={vsmartLogo}
            alt="VS Mart logo"
            priority
            sizes="120px"
            className="r-hero-brand"
            style={{
              display: "block",
              width: 116,
              height: "auto",
              marginBottom: 18,
              filter: "drop-shadow(0 10px 24px rgba(0,109,119,.18))",
            }}
          />
          <div
            style={{
              display: "inline-flex",
              alignItems: "center",
              gap: 9,
              background: "#fff",
              border: "1px solid rgba(0,109,119,.16)",
              padding: "7px 15px",
              borderRadius: 999,
              boxShadow: "0 6px 18px rgba(15,23,42,.05)",
              marginBottom: 24,
            }}
          >
            <span
              style={{
                width: 8,
                height: 8,
                borderRadius: "50%",
                background: "#8BC34A",
                boxShadow: "0 0 0 4px rgba(139,195,74,.22)",
              }}
            />
            <span
              style={{
                fontSize: 13,
                fontWeight: 700,
                letterSpacing: ".01em",
                color: "#006D77",
              }}
            >
              India&apos;s Smart Grocery &amp; Credit Platform
            </span>
          </div>
          <h1
            style={{
              fontFamily: display,
              fontWeight: 800,
              fontSize: "clamp(34px,7vw,60px)",
              lineHeight: 1.02,
              letterSpacing: "-.035em",
              margin: "0 0 18px",
              color: "#0F172A",
            }}
          >
            Groceries Delivered Fast.
            <br />
            <span style={{ color: "#006D77" }}>Credit Made Easy.</span>
          </h1>
          <p
            className="r-hero-lead"
            style={{
              fontSize: "clamp(16px,2.3vw,18px)",
              lineHeight: 1.55,
              color: "#475569",
              maxWidth: 480,
              margin: "0 0 14px",
              fontWeight: 500,
            }}
          >
            VS Mart combines grocery shopping, credit purchases, doorstep delivery and
            easy repayments — all in one app.
          </p>
          <div
            style={{
              display: "inline-flex",
              alignItems: "baseline",
              gap: 10,
              fontFamily: display,
              fontWeight: 700,
              fontSize: "clamp(16px,2.6vw,21px)",
              color: "#0F172A",
              background:
                "linear-gradient(90deg,rgba(244,196,48,.22),rgba(139,195,74,.14))",
              padding: "9px 18px",
              borderRadius: 12,
              marginBottom: 30,
            }}
          >
            Buy Today. <span style={{ color: "#006D77" }}>Pay Weekly or Monthly.</span>
          </div>

          <div
            className="r-hero-btns"
            style={{
              display: "flex",
              flexWrap: "wrap",
              gap: 13,
              marginBottom: 22,
            }}
          >
            <a
              href="#download"
              className="lift2"
              style={{
                display: "inline-flex",
                alignItems: "center",
                gap: 11,
                background: "#0F172A",
                color: "#fff",
                padding: "14px 22px",
                borderRadius: 14,
                boxShadow: "0 10px 24px rgba(15,23,42,.22)",
                transition: "transform .2s",
              }}
            >
              <svg width="22" height="22" viewBox="0 0 24 24" fill="#8BC34A">
                <path d="M3.6 2.3 13.4 12 3.6 21.7c-.3-.2-.5-.6-.5-1V3.3c0-.4.2-.8.5-1z" />
                <path
                  d="M16.2 8.8 5.9 2.9l8.7 8.7zM5.9 21.1l10.3-5.9-1.6-1.6zM20.4 10.7c.6.4.6 1.6 0 2l-2.6 1.5L15.6 12l2.2-2.2z"
                  fill="#fff"
                />
              </svg>
              <span style={{ textAlign: "left", lineHeight: 1.1 }}>
                <span style={{ display: "block", fontSize: 11, opacity: 0.7, fontWeight: 600 }}>
                  GET IT ON
                </span>
                <span style={{ display: "block", fontSize: 16, fontWeight: 700 }}>
                  Google Play
                </span>
              </span>
            </a>
            <a
              href="#download"
              className="lift2"
              style={{
                display: "inline-flex",
                alignItems: "center",
                gap: 11,
                background: "#006D77",
                color: "#fff",
                padding: "14px 22px",
                borderRadius: 14,
                boxShadow: "0 10px 24px rgba(0,109,119,.26)",
                transition: "transform .2s",
              }}
            >
              <svg width="21" height="21" viewBox="0 0 24 24" fill="#fff">
                <path d="M16.4 1.6c.1 1-.3 2-.9 2.8-.7.8-1.7 1.4-2.7 1.3-.1-1 .4-2 .9-2.7.7-.8 1.8-1.3 2.7-1.4zM19.5 17c-.5 1.2-.8 1.7-1.4 2.7-.9 1.4-2.2 3.2-3.8 3.2-1.4 0-1.8-.9-3.7-.9s-2.3.9-3.7.9c-1.6 0-2.8-1.6-3.7-3C-.1 16.6-.4 11 1.8 8.4c.9-1.2 2.4-1.9 3.8-1.9 1.4 0 2.3 1 3.5 1 1.1 0 1.8-1 3.5-1 1.2 0 2.5.7 3.5 1.8-3 1.7-2.5 6 .9 7z" />
              </svg>
              <span style={{ textAlign: "left", lineHeight: 1.1 }}>
                <span style={{ display: "block", fontSize: 11, opacity: 0.8, fontWeight: 600 }}>
                  DOWNLOAD ON
                </span>
                <span style={{ display: "block", fontSize: 16, fontWeight: 700 }}>
                  App Store
                </span>
              </span>
            </a>
          </div>

          <div
            className="r-hero-trust"
            style={{
              display: "grid",
              gridTemplateColumns: "repeat(2,auto)",
              gap: "10px 26px",
              width: "max-content",
            }}
          >
            {trust.map((t) => (
              <div
                key={t}
                style={{
                  display: "flex",
                  alignItems: "center",
                  gap: 9,
                  fontSize: 14,
                  fontWeight: 600,
                  color: "#334155",
                }}
              >
                <span
                  style={{
                    display: "flex",
                    width: 20,
                    height: 20,
                    borderRadius: "50%",
                    background: "#8BC34A",
                    color: "#fff",
                    alignItems: "center",
                    justifyContent: "center",
                    fontSize: 12,
                  }}
                >
                  ✓
                </span>{" "}
                {t}
              </div>
            ))}
          </div>
        </div>

        {/* RIGHT : phones + floating cards */}
        <HeroPhones />
      </div>

      {/* logos marquee */}
      <div
        style={{
          maxWidth: 1200,
          margin: "64px auto 0",
          display: "flex",
          alignItems: "center",
          gap: 26,
          flexWrap: "wrap",
          justifyContent: "center",
          opacity: 0.7,
        }}
      >
        <span
          style={{
            fontSize: 13,
            fontWeight: 700,
            color: "#94A3B8",
            letterSpacing: ".04em",
          }}
        >
          TRUSTED ACROSS
        </span>
        <span style={{ fontWeight: 700, color: "#475569" }}>50+ Areas</span>
        <span style={{ color: "#CBD5E1" }}>•</span>
        <span style={{ fontWeight: 700, color: "#475569" }}>10,000+ Customers</span>
        <span style={{ color: "#CBD5E1" }}>•</span>
        <span style={{ fontWeight: 700, color: "#475569" }}>5,000+ Deliveries</span>
        <span style={{ color: "#CBD5E1" }}>•</span>
        <span style={{ fontWeight: 700, color: "#475569" }}>99% Success Rate</span>
      </div>
    </header>
  );
}

function HeroPhones() {
  return (
    <div className="r-hero-phones-wrap" style={{ display: "flex", justifyContent: "center" }}>
      <div className="r-hero-phones" style={{ position: "relative", width: 520, height: 560, flex: "none" }}>
      {/* floating brand mark — transparent PNG dropped on the gradient */}
      <Image
        src={vsmartLogo}
        alt="VS Mart — smart grocery and credit app"
        priority
        sizes="(max-width: 880px) 220px, 300px"
        style={{
          position: "absolute",
          top: -34,
          left: "50%",
          width: 300,
          height: "auto",
          transform: "translateX(-50%)",
          zIndex: 1,
          opacity: 0.16,
          filter: "drop-shadow(0 22px 48px rgba(0,109,119,.28))",
          animation: "vsfloat 9s ease-in-out infinite",
          pointerEvents: "none",
          userSelect: "none",
        }}
      />
      {/* floating cards */}
      <div
        style={{
          position: "absolute",
          top: 8,
          left: -6,
          zIndex: 5,
          background: "#fff",
          borderRadius: 16,
          padding: "13px 16px",
          boxShadow: "0 18px 40px rgba(15,23,42,.14)",
          border: "1px solid rgba(15,23,42,.05)",
          animation: "vsfloat 6s ease-in-out infinite",
        }}
      >
        <div
          style={{
            fontSize: 11,
            fontWeight: 700,
            color: "#94A3B8",
            textTransform: "uppercase",
            letterSpacing: ".06em",
          }}
        >
          Credit Limit
        </div>
        <div style={{ fontFamily: display, fontWeight: 800, fontSize: 23, color: "#006D77" }}>
          ₹25,000
        </div>
      </div>
      <div
        style={{
          position: "absolute",
          top: 120,
          right: -14,
          zIndex: 5,
          background: "#0F172A",
          borderRadius: 16,
          padding: "13px 16px",
          boxShadow: "0 18px 40px rgba(15,23,42,.22)",
          animation: "vsfloat2 7.5s ease-in-out infinite",
        }}
      >
        <div
          style={{
            fontSize: 11,
            fontWeight: 700,
            color: "#8BC34A",
            textTransform: "uppercase",
            letterSpacing: ".06em",
          }}
        >
          Delivery
        </div>
        <div style={{ fontFamily: display, fontWeight: 800, fontSize: 21, color: "#fff" }}>
          10 Minutes
        </div>
      </div>
      <div
        style={{
          position: "absolute",
          bottom: 78,
          left: -22,
          zIndex: 5,
          background: "#fff",
          borderRadius: 16,
          padding: "12px 15px",
          boxShadow: "0 18px 40px rgba(15,23,42,.14)",
          border: "1px solid rgba(15,23,42,.05)",
          display: "flex",
          alignItems: "center",
          gap: 11,
          animation: "vsfloat2 8s ease-in-out infinite",
        }}
      >
        <div
          style={{
            width: 38,
            height: 38,
            borderRadius: 11,
            background: "conic-gradient(#8BC34A 0 78%,#E2E8F0 78% 100%)",
            display: "flex",
            alignItems: "center",
            justifyContent: "center",
          }}
        >
          <div
            style={{
              width: 28,
              height: 28,
              borderRadius: 8,
              background: "#fff",
              display: "flex",
              alignItems: "center",
              justifyContent: "center",
              fontFamily: display,
              fontWeight: 800,
              fontSize: 13,
              color: "#006D77",
            }}
          >
            820
          </div>
        </div>
        <div>
          <div
            style={{
              fontSize: 11,
              fontWeight: 700,
              color: "#94A3B8",
              textTransform: "uppercase",
              letterSpacing: ".05em",
            }}
          >
            VS Score
          </div>
          <div style={{ fontFamily: display, fontWeight: 800, fontSize: 17, color: "#0F172A" }}>
            Excellent
          </div>
        </div>
      </div>
      <div
        style={{
          position: "absolute",
          bottom: 10,
          right: 6,
          zIndex: 5,
          background: "#fff",
          borderRadius: 16,
          padding: "13px 16px",
          boxShadow: "0 18px 40px rgba(15,23,42,.14)",
          border: "1px solid rgba(15,23,42,.05)",
          animation: "vsfloat 6.6s ease-in-out infinite",
        }}
      >
        <div
          style={{
            fontSize: 11,
            fontWeight: 700,
            color: "#94A3B8",
            textTransform: "uppercase",
            letterSpacing: ".06em",
          }}
        >
          Outstanding
        </div>
        <div style={{ fontFamily: display, fontWeight: 800, fontSize: 21, color: "#F59E0B" }}>
          ₹4,200
        </div>
      </div>

      {/* PHONE BACK : credit dashboard */}
      <div
        style={{
          position: "absolute",
          top: 30,
          right: 34,
          width: 248,
          height: 506,
          borderRadius: 38,
          background: "#0F172A",
          padding: 9,
          boxShadow: "0 40px 80px rgba(15,23,42,.32)",
          transform: "rotate(5deg)",
        }}
      >
        <div
          style={{
            width: "100%",
            height: "100%",
            borderRadius: 30,
            overflow: "hidden",
            background: "linear-gradient(180deg,#006D77,#00565f)",
            position: "relative",
          }}
        >
          <div style={{ padding: "18px 16px 0", color: "#fff" }}>
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
              <span>VS Credit</span>
            </div>
            <div style={{ marginTop: 18, fontSize: 12, fontWeight: 600, opacity: 0.8 }}>
              Available Credit
            </div>
            <div style={{ fontFamily: display, fontWeight: 800, fontSize: 34, letterSpacing: "-.02em" }}>
              ₹20,800
            </div>
            <div
              style={{
                height: 7,
                borderRadius: 6,
                background: "rgba(255,255,255,.22)",
                marginTop: 8,
                overflow: "hidden",
              }}
            >
              <div style={{ width: "62%", height: "100%", background: "#8BC34A", borderRadius: 6 }} />
            </div>
            <div
              style={{
                display: "flex",
                justifyContent: "space-between",
                fontSize: 10,
                marginTop: 6,
                opacity: 0.85,
              }}
            >
              <span>Used ₹4,200</span>
              <span>Limit ₹25,000</span>
            </div>
          </div>
          <div style={{ margin: "16px 12px 0", background: "#fff", borderRadius: 18, padding: 14 }}>
            <div style={{ display: "flex", alignItems: "center", justifyContent: "space-between" }}>
              <div>
                <div style={{ fontSize: 10, color: "#94A3B8", fontWeight: 700 }}>VS SCORE</div>
                <div style={{ fontFamily: display, fontWeight: 800, fontSize: 26, color: "#0F172A" }}>
                  820
                </div>
                <div style={{ fontSize: 9.5, color: "#16A34A", fontWeight: 700 }}>▲ +18 this month</div>
              </div>
              <div
                style={{
                  width: 58,
                  height: 58,
                  borderRadius: "50%",
                  background: "conic-gradient(#8BC34A 0 78%,#EDF2F7 78% 100%)",
                  display: "flex",
                  alignItems: "center",
                  justifyContent: "center",
                }}
              >
                <div
                  style={{
                    width: 42,
                    height: 42,
                    borderRadius: "50%",
                    background: "#fff",
                    display: "flex",
                    alignItems: "center",
                    justifyContent: "center",
                    fontSize: 9,
                    fontWeight: 700,
                    color: "#006D77",
                  }}
                >
                  Good
                </div>
              </div>
            </div>
          </div>
          <div style={{ margin: 12, display: "flex", flexDirection: "column", gap: 8 }}>
            <div
              style={{
                display: "flex",
                alignItems: "center",
                justifyContent: "space-between",
                background: "rgba(255,255,255,.12)",
                borderRadius: 12,
                padding: "9px 12px",
              }}
            >
              <span style={{ fontSize: 11, color: "#fff", fontWeight: 600 }}>Grocery — Weekly</span>
              <span style={{ fontSize: 11, color: "#F4C430", fontWeight: 700 }}>-₹820</span>
            </div>
            <div
              style={{
                display: "flex",
                alignItems: "center",
                justifyContent: "space-between",
                background: "rgba(255,255,255,.12)",
                borderRadius: 12,
                padding: "9px 12px",
              }}
            >
              <span style={{ fontSize: 11, color: "#fff", fontWeight: 600 }}>Repayment</span>
              <span style={{ fontSize: 11, color: "#8BC34A", fontWeight: 700 }}>+₹1,500</span>
            </div>
          </div>
        </div>
      </div>

      {/* PHONE FRONT : grocery */}
      <div
        style={{
          position: "absolute",
          top: 64,
          left: 30,
          width: 248,
          height: 506,
          borderRadius: 38,
          background: "#fff",
          padding: 9,
          boxShadow: "0 40px 80px rgba(15,23,42,.26)",
          transform: "rotate(-6deg)",
          border: "1px solid rgba(15,23,42,.06)",
        }}
      >
        <div
          style={{
            width: "100%",
            height: "100%",
            borderRadius: 30,
            overflow: "hidden",
            background: "#F8FAFC",
            position: "relative",
          }}
        >
          <div
            style={{
              background: "#006D77",
              padding: "16px 14px 14px",
              color: "#fff",
              borderRadius: "0 0 18px 18px",
            }}
          >
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
              <span>●●● ▮</span>
            </div>
            <div style={{ marginTop: 10, fontSize: 10, opacity: 0.85, fontWeight: 600 }}>
              Deliver to · Home
            </div>
            <div style={{ fontFamily: display, fontWeight: 800, fontSize: 14 }}>Whitefield, 560066</div>
            <div
              style={{
                marginTop: 11,
                background: "#fff",
                borderRadius: 11,
                padding: "8px 11px",
                display: "flex",
                alignItems: "center",
                gap: 8,
              }}
            >
              <span style={{ color: "#94A3B8", fontSize: 12 }}>⌕</span>
              <span style={{ fontSize: 11, color: "#94A3B8", fontWeight: 500 }}>
                Search &quot;atta, milk, oil&quot;
              </span>
            </div>
          </div>
          <div style={{ padding: "11px 12px 0", display: "flex", gap: 7 }}>
            <div
              style={{
                background: "#EAF7DE",
                color: "#3f6212",
                fontSize: 10,
                fontWeight: 700,
                padding: "5px 10px",
                borderRadius: 999,
              }}
            >
              Staples
            </div>
            <div
              style={{
                background: "#fff",
                color: "#475569",
                fontSize: 10,
                fontWeight: 700,
                padding: "5px 10px",
                borderRadius: 999,
                border: "1px solid #E2E8F0",
              }}
            >
              Dairy
            </div>
            <div
              style={{
                background: "#fff",
                color: "#475569",
                fontSize: 10,
                fontWeight: 700,
                padding: "5px 10px",
                borderRadius: 999,
                border: "1px solid #E2E8F0",
              }}
            >
              Snacks
            </div>
          </div>
          <div
            style={{
              margin: "11px 12px",
              background: "linear-gradient(100deg,#F4C430,#f0b429)",
              borderRadius: 14,
              padding: "11px 13px",
              display: "flex",
              alignItems: "center",
              justifyContent: "space-between",
            }}
          >
            <div>
              <div style={{ fontFamily: display, fontWeight: 800, fontSize: 14, color: "#0F172A" }}>
                10-min delivery
              </div>
              <div style={{ fontSize: 9.5, fontWeight: 600, color: "#0F172A", opacity: 0.8 }}>
                on 2,000+ daily items
              </div>
            </div>
            <div style={{ width: 34, height: 34, borderRadius: 10, background: "rgba(15,23,42,.12)" }} />
          </div>
          <div
            style={{
              padding: "0 12px",
              display: "grid",
              gridTemplateColumns: "1fr 1fr",
              gap: 9,
            }}
          >
            <ProductCard
              swatch="repeating-linear-gradient(135deg,#EDF7E3,#EDF7E3 6px,#E2F0D2 6px,#E2F0D2 12px)"
              name="Fortune Atta 5kg"
              price="₹249"
            />
            <ProductCard
              swatch="repeating-linear-gradient(135deg,#E6F4F1,#E6F4F1 6px,#D5ECE8 6px,#D5ECE8 12px)"
              name="Toned Milk 1L"
              price="₹54"
            />
          </div>
        </div>
      </div>
      </div>
    </div>
  );
}

function ProductCard({ swatch, name, price }: { swatch: string; name: string; price: string }) {
  return (
    <div
      style={{
        background: "#fff",
        borderRadius: 13,
        padding: 9,
        border: "1px solid rgba(15,23,42,.05)",
      }}
    >
      <div style={{ height: 48, borderRadius: 9, background: swatch }} />
      <div style={{ fontSize: 10, fontWeight: 700, marginTop: 6, color: "#0F172A" }}>{name}</div>
      <div
        style={{
          display: "flex",
          alignItems: "center",
          justifyContent: "space-between",
          marginTop: 3,
        }}
      >
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
