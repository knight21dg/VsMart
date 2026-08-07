"use client";

import { useEffect, useState } from "react";
import Link from "next/link";

import type { ApiUser } from "../lib/types";

// `id` is the in-page section id (for active-link tracking); `href` uses a
// root-relative hash so the link also works from the legal pages (it routes
// home, then scrolls). On the home page this still smooth-scrolls in place.
const links = [
  { id: "app", href: "/#app", label: "App" },
  { id: "credit", href: "/#credit", label: "VS Credit" },
  { id: "ecosystem", href: "/#ecosystem", label: "Ecosystem" },
  { id: "delivery", href: "/#delivery", label: "Delivery" },
  { id: "faq", href: "/#faq", label: "FAQ" },
];

// Standalone routes (legal pages) — rendered with next/link, not hash anchors.
const pageLinks = [
  { href: "/privacy", label: "Privacy" },
  { href: "/terms", label: "Terms" },
];

/** First name, falling back to the last 4 digits of the mobile number for a
 *  customer who hasn't set a name yet. */
function firstNameOf(user: ApiUser): string {
  const first = (user.name ?? "").trim().split(/\s+/)[0];
  return first || `••${user.phone.slice(-4)}`;
}

function initialOf(user: ApiUser): string {
  const first = (user.name ?? "").trim();
  return (first ? first[0] : user.phone.slice(-1)).toUpperCase();
}

export default function Nav() {
  const [open, setOpen] = useState(false);
  const [scrolled, setScrolled] = useState(false);
  const [progress, setProgress] = useState(0);
  const [activeId, setActiveId] = useState("");
  // `undefined` = still resolving; `null` = signed out. Nothing is rendered for
  // the account slot until it resolves, so the nav never flickers Sign in →
  // account chip for a signed-in customer.
  const [user, setUser] = useState<ApiUser | null | undefined>(undefined);

  useEffect(() => {
    let cancelled = false;
    fetch("/api/auth/session")
      .then((r) => r.json())
      .then((data: { user: ApiUser | null }) => {
        if (!cancelled) setUser(data?.user ?? null);
      })
      .catch(() => {
        if (!cancelled) setUser(null);
      });
    return () => {
      cancelled = true;
    };
  }, []);

  useEffect(() => {
    const onScroll = () => {
      const y = window.scrollY;
      setScrolled(y > 6);
      const max = document.documentElement.scrollHeight - window.innerHeight;
      setProgress(max > 0 ? Math.min(1, Math.max(0, y / max)) : 0);
    };
    onScroll();
    window.addEventListener("scroll", onScroll, { passive: true });

    const els = links
      .map((l) => document.getElementById(l.id))
      .filter((el): el is HTMLElement => !!el);
    const io = new IntersectionObserver(
      (entries) => {
        entries.forEach((e) => {
          if (e.isIntersecting) setActiveId(e.target.id);
        });
      },
      { rootMargin: "-45% 0px -50% 0px", threshold: 0 }
    );
    els.forEach((el) => io.observe(el));

    return () => {
      window.removeEventListener("scroll", onScroll);
      io.disconnect();
    };
  }, []);

  return (
    <nav
      style={{
        position: "sticky",
        top: 0,
        zIndex: 50,
        backdropFilter: "blur(18px)",
        WebkitBackdropFilter: "blur(18px)",
        background: scrolled ? "rgba(248,250,252,.92)" : "rgba(248,250,252,.7)",
        borderBottom: scrolled
          ? "1px solid rgba(15,23,42,.08)"
          : "1px solid rgba(15,23,42,.04)",
        boxShadow: scrolled ? "0 8px 30px rgba(15,23,42,.08)" : "none",
        transition: "background .3s, box-shadow .3s, border-color .3s",
      }}
    >
      <div
        style={{
          maxWidth: 1200,
          margin: "0 auto",
          padding: scrolled ? "9px clamp(16px,4vw,28px)" : "13px clamp(16px,4vw,28px)",
          display: "flex",
          alignItems: "center",
          justifyContent: "space-between",
          gap: 16,
          transition: "padding .3s",
        }}
      >
        <a
          href="#top"
          onClick={() => setOpen(false)}
          aria-label="VS Mart — home"
          style={{ display: "flex", alignItems: "center", flex: "none" }}
        >
          {/* eslint-disable-next-line @next/next/no-img-element */}
          <img
            src="/assets/vsmart-appicon.png"
            alt="VS Mart"
            style={{
              width: scrolled ? 50 : 60,
              height: scrolled ? 50 : 60,
              maxWidth: "none",
              flex: "none",
              display: "block",
              transition: "width .3s, height .3s",
            }}
          />
        </a>

        {/* desktop nav */}
        <div className="nav-desktop" style={{ display: "flex", alignItems: "center", gap: 30 }}>
          <div
            style={{
              display: "flex",
              alignItems: "center",
              gap: 26,
              fontSize: 14.5,
              fontWeight: 600,
              color: "#334155",
            }}
          >
            {links.map((l) => (
              <a
                key={l.href}
                href={l.href}
                className={`navlink${activeId === l.id ? " is-active" : ""}`}
                style={{ transition: "color .2s" }}
              >
                {l.label}
              </a>
            ))}
            {pageLinks.map((l) => (
              <Link
                key={l.href}
                href={l.href}
                className="navlink"
                style={{ transition: "color .2s" }}
              >
                {l.label}
              </Link>
            ))}
          </div>

          {/* account slot — sign in, or the signed-in customer */}
          {user === undefined ? null : user ? (
            <Link
              href="/account"
              className="nav-account"
              style={{
                display: "inline-flex",
                alignItems: "center",
                gap: 9,
                padding: "6px 14px 6px 6px",
                borderRadius: 999,
                border: "1px solid rgba(15,23,42,.1)",
                background: "#fff",
                fontWeight: 700,
                fontSize: 14,
                color: "#0F172A",
                whiteSpace: "nowrap",
                transition: "border-color .2s, box-shadow .2s",
              }}
            >
              <span
                aria-hidden
                style={{
                  width: 28,
                  height: 28,
                  borderRadius: "50%",
                  background: "#006D77",
                  color: "#fff",
                  display: "inline-flex",
                  alignItems: "center",
                  justifyContent: "center",
                  fontSize: 13,
                  fontWeight: 800,
                }}
              >
                {initialOf(user)}
              </span>
              {firstNameOf(user)}
            </Link>
          ) : (
            <Link
              href="/login"
              className="navlink"
              style={{
                fontSize: 14.5,
                fontWeight: 700,
                color: "#334155",
                transition: "color .2s",
                whiteSpace: "nowrap",
              }}
            >
              Sign in
            </Link>
          )}

          <a
            href="#download"
            className="btn-nav"
            style={{
              display: "inline-flex",
              alignItems: "center",
              gap: 8,
              background: "#006D77",
              color: "#fff",
              fontWeight: 700,
              fontSize: 14.5,
              padding: "11px 20px",
              borderRadius: 999,
              boxShadow: "0 8px 20px rgba(0,109,119,.28)",
              transition: "transform .2s, box-shadow .2s",
              whiteSpace: "nowrap",
            }}
          >
            Download App
          </a>
        </div>

        {/* mobile hamburger */}
        <button
          type="button"
          className="nav-burger"
          aria-label={open ? "Close menu" : "Open menu"}
          aria-expanded={open}
          onClick={() => setOpen((v) => !v)}
        >
          {open ? (
            <svg width="22" height="22" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round">
              <path d="M6 6l12 12M18 6L6 18" />
            </svg>
          ) : (
            <svg width="22" height="22" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round">
              <path d="M3 6h18M3 12h18M3 18h18" />
            </svg>
          )}
        </button>
      </div>

      {/* mobile dropdown panel */}
      <div className="nav-mobile" data-open={open}>
        <div
          style={{
            maxWidth: 1200,
            margin: "0 auto",
            padding: "10px clamp(16px,4vw,28px) 18px",
            display: "flex",
            flexDirection: "column",
            gap: 4,
          }}
        >
          {links.map((l) => {
            const isActive = activeId === l.id;
            return (
              <a
                key={l.href}
                href={l.href}
                onClick={() => setOpen(false)}
                style={{
                  padding: "12px 6px",
                  fontSize: 16,
                  fontWeight: 600,
                  color: isActive ? "#006D77" : "#334155",
                  borderBottom: "1px solid rgba(15,23,42,.05)",
                }}
              >
                {l.label}
              </a>
            );
          })}
          {pageLinks.map((l) => (
            <Link
              key={l.href}
              href={l.href}
              onClick={() => setOpen(false)}
              style={{
                padding: "12px 6px",
                fontSize: 16,
                fontWeight: 600,
                color: "#334155",
                borderBottom: "1px solid rgba(15,23,42,.05)",
              }}
            >
              {l.label}
            </Link>
          ))}
          {user !== undefined && (
            <Link
              href={user ? "/account" : "/login"}
              onClick={() => setOpen(false)}
              style={{
                padding: "12px 6px",
                fontSize: 16,
                fontWeight: 700,
                color: "#006D77",
                borderBottom: "1px solid rgba(15,23,42,.05)",
              }}
            >
              {user ? `My account (${firstNameOf(user)})` : "Sign in"}
            </Link>
          )}
          <a
            href="#download"
            onClick={() => setOpen(false)}
            style={{
              marginTop: 12,
              display: "flex",
              justifyContent: "center",
              alignItems: "center",
              gap: 8,
              background: "#006D77",
              color: "#fff",
              fontWeight: 700,
              fontSize: 15,
              padding: "13px 20px",
              borderRadius: 999,
              boxShadow: "0 8px 20px rgba(0,109,119,.28)",
            }}
          >
            Download App
          </a>
        </div>
      </div>

      {/* scroll progress bar */}
      <div
        aria-hidden
        style={{
          position: "absolute",
          left: 0,
          bottom: 0,
          height: 2.5,
          width: `${progress * 100}%`,
          background: "linear-gradient(90deg,#8BC34A,#006D77)",
          borderRadius: "0 2px 2px 0",
          transition: "width .12s linear",
          opacity: progress > 0.002 ? 1 : 0,
        }}
      />
    </nav>
  );
}
