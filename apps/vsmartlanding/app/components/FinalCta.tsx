import { display, mono } from "./ui";

export default function FinalCta() {
  return (
    <section id="download" style={{ padding: "clamp(28px,5vw,40px) clamp(16px,5vw,28px) clamp(64px,9vw,100px)", background: "#F4F7F6" }}>
      <div
        data-reveal
        style={{
          maxWidth: 1120,
          margin: "0 auto",
          borderRadius: 34,
          padding: "clamp(40px,8vw,72px) clamp(22px,5vw,48px)",
          background: "linear-gradient(135deg,#06231f 0%,#006D77 58%,#0a8a6f 130%)",
          color: "#fff",
          textAlign: "center",
          position: "relative",
          overflow: "hidden",
          boxShadow: "0 50px 100px rgba(0,109,119,.34)",
        }}
      >
        <div
          style={{
            position: "absolute",
            inset: 0,
            backgroundImage: "radial-gradient(circle,rgba(255,255,255,.06) 1px,transparent 1px)",
            backgroundSize: "24px 24px",
            opacity: 0.5,
          }}
        />
        <div
          style={{
            position: "absolute",
            top: -90,
            right: -50,
            width: 320,
            height: 320,
            borderRadius: "50%",
            background: "radial-gradient(circle,rgba(244,196,48,.4),transparent 70%)",
          }}
        />
        <div
          style={{
            position: "absolute",
            bottom: -120,
            left: -40,
            width: 300,
            height: 300,
            borderRadius: "50%",
            background: "radial-gradient(circle,rgba(139,195,74,.32),transparent 72%)",
          }}
        />
        <div style={{ position: "relative" }}>
          <div
            style={{
              display: "inline-flex",
              alignItems: "center",
              gap: 9,
              background: "rgba(255,255,255,.12)",
              border: "1px solid rgba(255,255,255,.18)",
              padding: "7px 16px",
              borderRadius: 999,
              marginBottom: 24,
            }}
          >
            <span style={{ color: "#F4C430", letterSpacing: 1 }}>★★★★★</span>
            <span style={{ fontFamily: mono, fontSize: 12, fontWeight: 600 }}>4.8 on Play Store</span>
          </div>
          <h2
            style={{
              fontFamily: display,
              fontWeight: 800,
              fontSize: "clamp(30px,6vw,54px)",
              lineHeight: 1.0,
              letterSpacing: "-.035em",
              margin: "0 0 16px",
            }}
          >
            Download VS Mart today.
          </h2>
          <p style={{ fontSize: "clamp(16px,2.6vw,20px)", fontWeight: 600, color: "rgba(255,255,255,.9)", margin: "0 0 36px" }}>
            Shop smarter. Buy on credit. Pay with ease.
          </p>
          <div style={{ display: "flex", gap: 14, justifyContent: "center", flexWrap: "wrap" }}>
            <a
              href="#"
              className="lift3"
              style={{
                display: "inline-flex",
                alignItems: "center",
                gap: 12,
                background: "#fff",
                color: "#0F172A",
                padding: "16px 28px",
                borderRadius: 15,
                boxShadow: "0 14px 30px rgba(0,0,0,.18)",
                transition: "transform .2s",
              }}
            >
              <svg width="26" height="26" viewBox="0 0 24 24" fill="#006D77">
                <path d="M3.6 2.3 13.4 12 3.6 21.7c-.3-.2-.5-.6-.5-1V3.3c0-.4.2-.8.5-1z" />
                <path
                  d="M16.2 8.8 5.9 2.9l8.7 8.7zM5.9 21.1l10.3-5.9-1.6-1.6zM20.4 10.7c.6.4.6 1.6 0 2l-2.6 1.5L15.6 12l2.2-2.2z"
                  fill="#0a8a6f"
                />
              </svg>
              <span style={{ textAlign: "left", lineHeight: 1.1 }}>
                <span style={{ display: "block", fontFamily: mono, fontSize: 10, opacity: 0.6, fontWeight: 600, letterSpacing: ".04em" }}>
                  GET IT ON
                </span>
                <span style={{ display: "block", fontSize: 18, fontWeight: 800, fontFamily: display }}>Google Play</span>
              </span>
            </a>
            <a
              href="#"
              className="lift3"
              style={{
                display: "inline-flex",
                alignItems: "center",
                gap: 12,
                background: "#0F172A",
                color: "#fff",
                padding: "16px 28px",
                borderRadius: 15,
                boxShadow: "0 14px 30px rgba(0,0,0,.24)",
                transition: "transform .2s",
              }}
            >
              <svg width="24" height="24" viewBox="0 0 24 24" fill="#fff">
                <path d="M16.4 1.6c.1 1-.3 2-.9 2.8-.7.8-1.7 1.4-2.7 1.3-.1-1 .4-2 .9-2.7.7-.8 1.8-1.3 2.7-1.4zM19.5 17c-.5 1.2-.8 1.7-1.4 2.7-.9 1.4-2.2 3.2-3.8 3.2-1.4 0-1.8-.9-3.7-.9s-2.3.9-3.7.9c-1.6 0-2.8-1.6-3.7-3C-.1 16.6-.4 11 1.8 8.4c.9-1.2 2.4-1.9 3.8-1.9 1.4 0 2.3 1 3.5 1 1.1 0 1.8-1 3.5-1 1.2 0 2.5.7 3.5 1.8-3 1.7-2.5 6 .9 7z" />
              </svg>
              <span style={{ textAlign: "left", lineHeight: 1.1 }}>
                <span style={{ display: "block", fontFamily: mono, fontSize: 10, opacity: 0.6, fontWeight: 600, letterSpacing: ".04em" }}>
                  DOWNLOAD ON
                </span>
                <span style={{ display: "block", fontSize: 18, fontWeight: 800, fontFamily: display }}>App Store</span>
              </span>
            </a>
          </div>
        </div>
      </div>
    </section>
  );
}
