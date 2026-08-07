import Link from "next/link";
import { display, mono } from "./ui";
import FooterWordmark from "./FooterWordmark";

const legalLinks = [
  { label: "Privacy Policy", href: "/privacy" },
  { label: "Terms & Conditions", href: "/terms" },
  { label: "Delete Account", href: "/delete-account" },
];

const socials = [
  { label: "Instagram", href: "#" },
  { label: "Facebook", href: "#" },
  { label: "E-mail", href: "mailto:hello@vsmart.in" },
];

const pillLinks = [
  { label: "App", href: "#app" },
  { label: "Credit", href: "#credit" },
  { label: "Delivery", href: "#delivery" },
];

function ArrowUpRight({ size = "0.62em" }: { size?: string }) {
  return (
    <svg
      width={size}
      height={size}
      viewBox="0 0 24 24"
      fill="none"
      stroke="currentColor"
      strokeWidth="2.4"
      strokeLinecap="round"
      strokeLinejoin="round"
      style={{ verticalAlign: "super" }}
    >
      <path d="M7 17L17 7M9 7h8v8" />
    </svg>
  );
}

export default function Footer() {
  return (
    <footer
      style={{
        position: "relative",
        background: "#06231f",
        color: "#fff",
        overflow: "hidden",
        padding: "clamp(56px,8vw,96px) clamp(16px,5vw,28px) 28px",
      }}
    >
      {/* soft brand glows */}
      <div
        style={{
          position: "absolute",
          top: -140,
          left: "-6%",
          width: 420,
          height: 420,
          borderRadius: "50%",
          background: "radial-gradient(circle,rgba(0,109,119,.5),transparent 70%)",
        }}
      />
      <div
        style={{
          position: "absolute",
          bottom: -160,
          right: "-4%",
          width: 380,
          height: 380,
          borderRadius: "50%",
          background: "radial-gradient(circle,rgba(139,195,74,.2),transparent 72%)",
        }}
      />

      <div style={{ position: "relative", maxWidth: 1280, margin: "0 auto" }}>
        {/* giant brand wordmark — grab & toss (physics) */}
        <FooterWordmark />

        {/* connect with us */}
        <div style={{ textAlign: "center", marginBottom: "clamp(40px,6vw,64px)" }}>
          <div
            style={{
              fontFamily: mono,
              fontSize: 13,
              fontWeight: 600,
              letterSpacing: ".16em",
              textTransform: "uppercase",
              color: "rgba(255,255,255,.55)",
              marginBottom: 22,
            }}
          >
            Connect with us:
          </div>
          <div
            style={{
              display: "flex",
              flexWrap: "wrap",
              alignItems: "center",
              justifyContent: "center",
              gap: "clamp(20px,5vw,52px)",
            }}
          >
            {socials.map((s) => (
              <a
                key={s.label}
                href={s.href}
                className="footer-biglink"
                style={{
                  display: "inline-flex",
                  alignItems: "flex-start",
                  gap: 4,
                  fontFamily: display,
                  fontWeight: 700,
                  fontSize: "clamp(30px,7vw,60px)",
                  letterSpacing: "-.02em",
                  color: "#fff",
                  transition: "color .2s",
                }}
              >
                {s.label}
                <ArrowUpRight />
              </a>
            ))}
          </div>
        </div>

        {/* pill nav */}
        <div style={{ display: "flex", justifyContent: "center" }}>
          <div
            style={{
              display: "inline-flex",
              alignItems: "center",
              gap: 6,
              background: "rgba(255,255,255,.06)",
              border: "1px solid rgba(255,255,255,.12)",
              borderRadius: 999,
              padding: 6,
              maxWidth: "100%",
            }}
          >
            <a
              href="#top"
              style={{
                display: "inline-flex",
                alignItems: "center",
                gap: 8,
                background: "rgba(255,255,255,.08)",
                borderRadius: 999,
                padding: "8px 14px 8px 8px",
                flex: "none",
              }}
            >
              {/* eslint-disable-next-line @next/next/no-img-element */}
              <img
                src="/assets/vsmart-appicon.png"
                alt="VS Mart"
                style={{ width: 26, height: 26, borderRadius: 8 }}
              />
              <span style={{ fontFamily: display, fontWeight: 800, fontSize: 15 }}>VS Mart</span>
            </a>

            <div className="footer-pill-links" style={{ display: "inline-flex", alignItems: "center", gap: 2 }}>
              {pillLinks.map((l) => (
                <a
                  key={l.label}
                  href={l.href}
                  className="footer-pill-link"
                  style={{
                    padding: "8px 14px",
                    borderRadius: 999,
                    fontSize: 14,
                    fontWeight: 600,
                    color: "rgba(255,255,255,.8)",
                    transition: "color .2s, background .2s",
                  }}
                >
                  {l.label}
                </a>
              ))}
            </div>

            <a
              href="#download"
              className="lift2"
              style={{
                display: "inline-flex",
                alignItems: "center",
                background: "#8BC34A",
                color: "#06231f",
                fontWeight: 800,
                fontSize: 14,
                padding: "10px 18px",
                borderRadius: 999,
                whiteSpace: "nowrap",
                flex: "none",
                transition: "transform .2s",
              }}
            >
              Download App
            </a>
          </div>
        </div>

        {/* legal links */}
        <div
          style={{
            marginTop: "clamp(34px,5vw,52px)",
            display: "flex",
            flexWrap: "wrap",
            justifyContent: "center",
            gap: "10px 26px",
          }}
        >
          {legalLinks.map((l) => (
            <Link
              key={l.href}
              href={l.href}
              className="footer-link"
              style={{
                fontSize: 13.5,
                fontWeight: 600,
                color: "rgba(255,255,255,.7)",
                transition: "color .2s",
              }}
            >
              {l.label}
            </Link>
          ))}
        </div>

        {/* copyright */}
        <div
          style={{
            marginTop: "clamp(26px,4vw,38px)",
            paddingTop: 24,
            borderTop: "1px solid rgba(255,255,255,.08)",
            display: "flex",
            justifyContent: "space-between",
            flexWrap: "wrap",
            gap: 10,
            fontSize: 13,
            fontWeight: 500,
            color: "rgba(255,255,255,.5)",
          }}
        >
          <span>© 2026 VS Mart. All rights reserved.</span>
          <span>Made in India 🇮🇳</span>
        </div>
      </div>
    </footer>
  );
}
