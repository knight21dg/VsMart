import type { ReactNode } from "react";
import Link from "next/link";
import Nav from "./Nav";
import Footer from "./Footer";
import { display, mono } from "./ui";
import "./legal.css";

/**
 * Shared shell for the CMS-backed legal pages (Privacy, Terms).
 * Renders the site Nav + Footer around a centered, readable "prose"
 * container so the documents feel native to the marketing site.
 */
export default function LegalPage({
  eyebrow,
  title,
  updatedAt,
  bodyHtml,
  fallback = false,
}: {
  eyebrow: string;
  title: string;
  updatedAt?: string | null;
  bodyHtml?: string | null;
  fallback?: boolean;
}) {
  return (
    <div style={{ overflowX: "hidden", display: "flex", flexDirection: "column", minHeight: "100vh" }}>
      <Nav />

      <main
        style={{
          flex: 1,
          padding: "clamp(40px,7vw,84px) clamp(16px,5vw,28px) clamp(56px,8vw,96px)",
        }}
      >
        <article style={{ maxWidth: 760, margin: "0 auto" }}>
          <Link
            href="/"
            className="legal-back"
            style={{
              display: "inline-flex",
              alignItems: "center",
              gap: 7,
              fontFamily: mono,
              fontSize: 12.5,
              fontWeight: 600,
              letterSpacing: ".12em",
              textTransform: "uppercase",
              color: "#006D77",
              marginBottom: 26,
            }}
          >
            <svg width="15" height="15" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2.4" strokeLinecap="round" strokeLinejoin="round">
              <path d="M15 18l-6-6 6-6" />
            </svg>
            Back to home
          </Link>

          <div
            style={{
              fontFamily: mono,
              fontSize: 12,
              fontWeight: 600,
              letterSpacing: ".14em",
              color: "#006D77",
              textTransform: "uppercase",
              marginBottom: 14,
            }}
          >
            {eyebrow}
          </div>

          <h1
            style={{
              fontFamily: display,
              fontWeight: 800,
              fontSize: "clamp(30px,5.5vw,50px)",
              lineHeight: 1.04,
              letterSpacing: "-.035em",
              margin: "0 0 14px",
            }}
          >
            {title}
          </h1>

          {updatedAt ? (
            <p
              style={{
                fontSize: 13.5,
                fontWeight: 600,
                color: "#94A3B8",
                margin: "0 0 6px",
              }}
            >
              Last updated: {formatDate(updatedAt)}
            </p>
          ) : null}

          <div
            style={{
              height: 1,
              background: "rgba(15,23,42,.1)",
              margin: "26px 0 34px",
            }}
          />

          {fallback ? (
            <FallbackNotice />
          ) : (
            <div
              className="legal-prose"
              // Body HTML is authored by super-admin in the backend CMS.
              dangerouslySetInnerHTML={{ __html: bodyHtml ?? "" }}
            />
          )}
        </article>
      </main>

      <Footer />
    </div>
  );
}

function FallbackNotice(): ReactNode {
  return (
    <div
      style={{
        background: "#F8FAFC",
        border: "1px solid rgba(15,23,42,.08)",
        borderRadius: 20,
        padding: "clamp(28px,5vw,44px)",
        textAlign: "center",
      }}
    >
      <div
        style={{
          width: 52,
          height: 52,
          borderRadius: "50%",
          background: "rgba(0,109,119,.1)",
          color: "#006D77",
          display: "flex",
          alignItems: "center",
          justifyContent: "center",
          margin: "0 auto 16px",
        }}
      >
        <svg width="26" height="26" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round">
          <path d="M12 8v4M12 16h.01" />
          <circle cx="12" cy="12" r="9" />
        </svg>
      </div>
      <p style={{ fontFamily: display, fontWeight: 800, fontSize: 19, margin: "0 0 6px" }}>
        This page is being updated
      </p>
      <p style={{ fontSize: 14.5, color: "#64748B", fontWeight: 500, margin: 0, lineHeight: 1.6 }}>
        We&apos;re refreshing this content — please check back soon. If you need this document right
        away, reach us at{" "}
        <a href="mailto:hello@vsmart.in" style={{ color: "#006D77", fontWeight: 700 }}>
          hello@vsmart.in
        </a>
        .
      </p>
    </div>
  );
}

function formatDate(value: string): string {
  const d = new Date(value);
  if (Number.isNaN(d.getTime())) return value;
  return d.toLocaleDateString("en-IN", {
    day: "numeric",
    month: "long",
    year: "numeric",
  });
}
