"use client";

import { useCallback, useEffect, useState } from "react";
import Link from "next/link";

import { colors, display, mono } from "../components/ui";
import { formatIndianMobile } from "../lib/phone";
import type { ApiUser, Order } from "../lib/types";

/** `/orders` renders camelCase (core.renderers.EnvelopeJSONRenderer). */
interface OrdersMeta {
  page?: number;
  pageSize?: number;
  total?: number;
  totalPages?: number;
}

export default function AccountClient() {
  const [user, setUser] = useState<ApiUser | null>(null);
  const [orders, setOrders] = useState<Order[]>([]);
  const [ordersMeta, setOrdersMeta] = useState<OrdersMeta | null>(null);
  const [loadingUser, setLoadingUser] = useState(true);
  const [sessionError, setSessionError] = useState(false);
  const [loadingOrders, setLoadingOrders] = useState(true);
  const [ordersError, setOrdersError] = useState<string | null>(null);
  const [signingOut, setSigningOut] = useState(false);

  /** Any 401 means the refresh token died server-side — start over cleanly. */
  const toLogin = useCallback(() => {
    window.location.assign("/login?next=/account");
  }, []);

  useEffect(() => {
    let cancelled = false;
    fetch("/api/auth/session")
      .then((r) => r.json())
      .then((data: { user: ApiUser | null }) => {
        if (cancelled) return;
        if (!data?.user) {
          toLogin();
          return;
        }
        setUser(data.user);
        setLoadingUser(false);
      })
      .catch(() => {
        if (cancelled) return;
        // Network failure — not a signed-out session, so don't bounce to /login.
        setSessionError(true);
        setLoadingUser(false);
      });
    return () => {
      cancelled = true;
    };
  }, [toLogin]);

  const loadOrders = useCallback(
    async (page: number) => {
      setLoadingOrders(true);
      setOrdersError(null);
      try {
        const res = await fetch(`/api/account/orders?page=${page}`);
        const data = await res.json();
        if (res.status === 401) {
          toLogin();
          return;
        }
        if (!res.ok || data?.ok === false) {
          throw new Error(data?.message || "Couldn't load your orders.");
        }
        setOrders((prev) =>
          page === 1 ? (data.orders as Order[]) : [...prev, ...(data.orders as Order[])]
        );
        setOrdersMeta((data.meta ?? null) as OrdersMeta | null);
      } catch (e) {
        setOrdersError(e instanceof Error ? e.message : "Couldn't load your orders.");
      } finally {
        setLoadingOrders(false);
      }
    },
    [toLogin]
  );

  useEffect(() => {
    void loadOrders(1);
  }, [loadOrders]);

  async function signOut() {
    setSigningOut(true);
    try {
      await fetch("/api/auth/logout", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: "{}",
      });
    } catch {
      /* the cookies are cleared server-side regardless */
    }
    window.location.assign("/");
  }

  if (loadingUser) return <AccountSkeleton />;

  if (sessionError || !user) {
    return (
      <section style={cardStyle}>
        <h2 style={cardTitleStyle}>We couldn&apos;t load your account</h2>
        <p style={{ fontSize: 14.5, color: "#64748B", fontWeight: 500, margin: "8px 0 18px" }}>
          Check your connection and try again.
        </p>
        <button type="button" onClick={() => window.location.reload()} style={ghostButtonStyle}>
          Try again
        </button>
      </section>
    );
  }

  const page = ordersMeta?.page ?? 1;
  const totalPages = ordersMeta?.totalPages ?? 1;
  const firstName = (user.name ?? "").trim().split(/\s+/)[0];

  return (
    <>
      <header style={{ marginBottom: 28 }}>
        <div
          style={{
            fontFamily: mono,
            fontSize: 12,
            fontWeight: 600,
            letterSpacing: ".14em",
            color: colors.teal,
            textTransform: "uppercase",
            marginBottom: 12,
          }}
        >
          My account
        </div>
        <h1
          style={{
            fontFamily: display,
            fontWeight: 800,
            fontSize: "clamp(28px,5vw,42px)",
            lineHeight: 1.05,
            letterSpacing: "-.035em",
            margin: 0,
          }}
        >
          {firstName ? `Hi, ${firstName}` : "Welcome back"}
        </h1>
        <p style={{ fontSize: 14.5, color: "#64748B", fontWeight: 600, margin: "8px 0 0" }}>
          {formatIndianMobile(user.phone)}
        </p>
      </header>

      <ProfileCard user={user} onSaved={setUser} />

      <OrdersCard
        orders={orders}
        loading={loadingOrders}
        error={ordersError}
        canLoadMore={page < totalPages}
        onLoadMore={() => void loadOrders(page + 1)}
        onRetry={() => void loadOrders(1)}
      />

      <div
        style={{
          display: "flex",
          flexWrap: "wrap",
          alignItems: "center",
          justifyContent: "space-between",
          gap: 14,
          marginTop: 26,
        }}
      >
        <Link
          href="/delete-account"
          style={{ fontSize: 13, fontWeight: 600, color: "#94A3B8" }}
        >
          Delete my account
        </Link>
        <button
          type="button"
          onClick={() => void signOut()}
          disabled={signingOut}
          style={{
            display: "inline-flex",
            alignItems: "center",
            gap: 8,
            height: 46,
            padding: "0 20px",
            borderRadius: 999,
            border: "1.5px solid rgba(15,23,42,.12)",
            background: "#fff",
            color: "#0F172A",
            fontWeight: 700,
            fontSize: 14.5,
            cursor: signingOut ? "default" : "pointer",
          }}
        >
          <svg
            width="16"
            height="16"
            viewBox="0 0 24 24"
            fill="none"
            stroke="currentColor"
            strokeWidth="2.2"
            strokeLinecap="round"
            strokeLinejoin="round"
            aria-hidden="true"
          >
            <path d="M9 21H5a2 2 0 0 1-2-2V5a2 2 0 0 1 2-2h4M16 17l5-5-5-5M21 12H9" />
          </svg>
          {signingOut ? "Signing out…" : "Sign out"}
        </button>
      </div>
    </>
  );
}

/* ── profile ─────────────────────────────────────────────────────────── */

function ProfileCard({
  user,
  onSaved,
}: {
  user: ApiUser;
  onSaved: (user: ApiUser) => void;
}) {
  const [editing, setEditing] = useState(false);
  const [name, setName] = useState(user.name ?? "");
  const [email, setEmail] = useState(user.email ?? "");
  const [saving, setSaving] = useState(false);
  const [error, setError] = useState<string | null>(null);

  async function save() {
    setSaving(true);
    setError(null);
    try {
      const res = await fetch("/api/auth/profile", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ name, email }),
      });
      const data = await res.json();
      if (!res.ok || data?.ok === false) {
        throw new Error(data?.message || "Couldn't save your details.");
      }
      onSaved(data.user as ApiUser);
      setEditing(false);
    } catch (e) {
      setError(e instanceof Error ? e.message : "Couldn't save your details.");
    } finally {
      setSaving(false);
    }
  }

  return (
    <section style={cardStyle}>
      <div
        style={{
          display: "flex",
          alignItems: "center",
          justifyContent: "space-between",
          gap: 12,
          marginBottom: 18,
        }}
      >
        <h2 style={cardTitleStyle}>Profile</h2>
        {!editing && (
          <button type="button" onClick={() => setEditing(true)} style={linkButtonStyle}>
            Edit
          </button>
        )}
      </div>

      {error && (
        <div role="alert" style={errorBoxStyle}>
          {error}
        </div>
      )}

      {editing ? (
        <form
          onSubmit={(e) => {
            e.preventDefault();
            if (name.trim().length >= 2 && !saving) void save();
          }}
        >
          <label htmlFor="acc-name" style={labelStyle}>
            Full name
          </label>
          <input
            id="acc-name"
            className="field"
            value={name}
            onChange={(e) => setName(e.target.value)}
            autoComplete="name"
            style={inputStyle}
          />
          <label htmlFor="acc-email" style={{ ...labelStyle, marginTop: 14 }}>
            Email <span style={{ color: "#94A3B8" }}>(optional)</span>
          </label>
          <input
            id="acc-email"
            className="field"
            value={email}
            onChange={(e) => setEmail(e.target.value)}
            type="email"
            autoComplete="email"
            style={inputStyle}
          />
          <div style={{ display: "flex", gap: 10, marginTop: 18 }}>
            <button
              type="submit"
              disabled={name.trim().length < 2 || saving}
              style={{
                ...primaryButtonStyle,
                background: name.trim().length < 2 || saving ? "#CBD5E1" : colors.teal,
                cursor: name.trim().length < 2 || saving ? "not-allowed" : "pointer",
              }}
            >
              {saving ? "Saving…" : "Save changes"}
            </button>
            <button
              type="button"
              onClick={() => {
                setEditing(false);
                setName(user.name ?? "");
                setEmail(user.email ?? "");
                setError(null);
              }}
              style={ghostButtonStyle}
            >
              Cancel
            </button>
          </div>
        </form>
      ) : (
        <>
          <dl style={{ margin: 0, display: "grid", gap: 14 }}>
            <Row label="Name" value={user.name || "Not set"} />
            <Row label="Mobile" value={formatIndianMobile(user.phone)} />
            <Row label="Email" value={user.email || "Not added"} />
            {user.created_at && (
              <Row label="Member since" value={formatDate(user.created_at)} />
            )}
          </dl>

          <div style={{ display: "flex", flexWrap: "wrap", gap: 8, marginTop: 18 }}>
            <Chip
              label={user.credit_enabled ? "VS Credit active" : "VS Credit not active"}
              tone={user.credit_enabled ? "green" : "grey"}
            />
            {user.kyc_status && (
              <Chip
                label={`KYC · ${sentence(user.kyc_status)}`}
                tone={kycTone(user.kyc_status)}
              />
            )}
          </div>
        </>
      )}
    </section>
  );
}

function Row({ label, value }: { label: string; value: string }) {
  return (
    <div style={{ display: "flex", flexWrap: "wrap", gap: 6, justifyContent: "space-between" }}>
      <dt style={{ fontSize: 13.5, fontWeight: 600, color: "#64748B" }}>{label}</dt>
      <dd style={{ margin: 0, fontSize: 14.5, fontWeight: 700, color: "#0F172A" }}>{value}</dd>
    </div>
  );
}

/* ── orders ──────────────────────────────────────────────────────────── */

function OrdersCard({
  orders,
  loading,
  error,
  canLoadMore,
  onLoadMore,
  onRetry,
}: {
  orders: Order[];
  loading: boolean;
  error: string | null;
  canLoadMore: boolean;
  onLoadMore: () => void;
  onRetry: () => void;
}) {
  return (
    <section style={{ ...cardStyle, marginTop: 20 }}>
      <h2 style={{ ...cardTitleStyle, marginBottom: 18 }}>Your orders</h2>

      {error ? (
        <div>
          <div role="alert" style={errorBoxStyle}>
            {error}
          </div>
          <button type="button" onClick={onRetry} style={ghostButtonStyle}>
            Try again
          </button>
        </div>
      ) : loading && orders.length === 0 ? (
        <div style={{ display: "grid", gap: 12 }}>
          {[0, 1, 2].map((i) => (
            <div
              key={i}
              style={{
                height: 78,
                borderRadius: 16,
                background: "#F1F5F9",
                animation: "vspulse 1.4s ease-in-out infinite",
              }}
            />
          ))}
        </div>
      ) : orders.length === 0 ? (
        <EmptyOrders />
      ) : (
        <>
          <ul style={{ listStyle: "none", margin: 0, padding: 0, display: "grid", gap: 12 }}>
            {orders.map((order) => (
              <OrderRow key={order.id} order={order} />
            ))}
          </ul>
          {canLoadMore && (
            <button
              type="button"
              onClick={onLoadMore}
              disabled={loading}
              style={{ ...ghostButtonStyle, marginTop: 16, width: "100%" }}
            >
              {loading ? "Loading…" : "Load older orders"}
            </button>
          )}
        </>
      )}
    </section>
  );
}

function OrderRow({ order }: { order: Order }) {
  const itemCount = order.items?.length ?? 0;
  return (
    <li
      style={{
        border: "1px solid rgba(15,23,42,.08)",
        borderRadius: 16,
        padding: "14px 16px",
        display: "flex",
        flexWrap: "wrap",
        gap: 10,
        alignItems: "center",
        justifyContent: "space-between",
      }}
    >
      <div style={{ minWidth: 0 }}>
        <div style={{ display: "flex", alignItems: "center", gap: 9, flexWrap: "wrap" }}>
          <span style={{ fontFamily: mono, fontSize: 13.5, fontWeight: 700 }}>#{order.id}</span>
          <StatusPill status={order.status} />
        </div>
        <div style={{ fontSize: 13, color: "#64748B", fontWeight: 600, marginTop: 5 }}>
          {order.placedAt ? formatDate(order.placedAt) : "—"}
          {itemCount > 0 && ` · ${itemCount} item${itemCount === 1 ? "" : "s"}`}
        </div>
      </div>
      <div style={{ textAlign: "right" }}>
        <div style={{ fontFamily: display, fontWeight: 800, fontSize: 17 }}>
          {formatMoney(order.total)}
        </div>
        {Number(order.creditUsed ?? 0) > 0 && (
          <div style={{ fontSize: 12, fontWeight: 700, color: colors.teal, marginTop: 2 }}>
            {formatMoney(order.creditUsed)} on VS Credit
          </div>
        )}
      </div>
    </li>
  );
}

function EmptyOrders() {
  return (
    <div
      style={{
        background: "#F8FAFC",
        border: "1px dashed rgba(15,23,42,.14)",
        borderRadius: 18,
        padding: "34px 24px",
        textAlign: "center",
      }}
    >
      <p style={{ fontFamily: display, fontWeight: 800, fontSize: 18, margin: "0 0 6px" }}>
        No orders yet
      </p>
      <p
        style={{
          fontSize: 14,
          color: "#64748B",
          fontWeight: 500,
          lineHeight: 1.6,
          margin: "0 0 18px",
        }}
      >
        Shopping happens in the VS Mart app — groceries, VS Credit and doorstep delivery.
      </p>
      <Link
        href="/userapp"
        className="lift2"
        style={{
          display: "inline-flex",
          alignItems: "center",
          gap: 8,
          background: colors.teal,
          color: "#fff",
          fontWeight: 700,
          fontSize: 14.5,
          padding: "12px 22px",
          borderRadius: 999,
          boxShadow: "0 10px 22px rgba(0,109,119,.28)",
          transition: "transform .2s",
        }}
      >
        Get the app
      </Link>
    </div>
  );
}

/* ── bits ────────────────────────────────────────────────────────────── */

function AccountSkeleton() {
  return (
    <div style={{ display: "grid", gap: 18 }}>
      <div
        style={{
          height: 52,
          width: "60%",
          borderRadius: 14,
          background: "#F1F5F9",
          animation: "vspulse 1.4s ease-in-out infinite",
        }}
      />
      <div
        style={{
          height: 230,
          borderRadius: 22,
          background: "#F1F5F9",
          animation: "vspulse 1.4s ease-in-out infinite",
        }}
      />
    </div>
  );
}

const STATUS_TONES: Record<string, "green" | "teal" | "amber" | "red" | "grey"> = {
  delivered: "green",
  placed: "teal",
  pending: "teal",
  confirmed: "teal",
  packed: "teal",
  ready_for_dispatch: "teal",
  out_for_delivery: "amber",
  cancelled: "red",
  rejected: "red",
  returned: "grey",
  partially_returned: "grey",
};

const TONES = {
  green: { bg: "#EAF7DE", fg: "#3F6212", border: "#8BC34A" },
  teal: { bg: "rgba(0,109,119,.09)", fg: "#006D77", border: "rgba(0,109,119,.28)" },
  amber: { bg: "#FEF6E0", fg: "#92600B", border: "#F4C430" },
  red: { bg: "#FEF2F2", fg: "#B91C1C", border: "#FECACA" },
  grey: { bg: "#F1F5F9", fg: "#475569", border: "rgba(15,23,42,.12)" },
} as const;

function StatusPill({ status }: { status: string }) {
  return <Chip label={sentence(status)} tone={STATUS_TONES[status] ?? "grey"} />;
}

function Chip({ label, tone }: { label: string; tone: keyof typeof TONES }) {
  const t = TONES[tone];
  return (
    <span
      style={{
        display: "inline-flex",
        alignItems: "center",
        background: t.bg,
        color: t.fg,
        border: `1px solid ${t.border}`,
        borderRadius: 999,
        padding: "4px 11px",
        fontSize: 11.5,
        fontWeight: 700,
        letterSpacing: ".02em",
      }}
    >
      {label}
    </span>
  );
}

function kycTone(status: string): keyof typeof TONES {
  if (status === "verified" || status === "approved") return "green";
  if (status === "rejected") return "red";
  if (status === "pending" || status === "submitted") return "amber";
  return "grey";
}

/** `out_for_delivery` → `Out for delivery`. */
function sentence(value: string): string {
  const words = (value || "").replace(/_/g, " ").trim();
  return words ? words[0]!.toUpperCase() + words.slice(1) : words;
}

function formatMoney(value: number | null | undefined): string {
  const n = Number(value ?? 0);
  return `₹${n.toLocaleString("en-IN", { minimumFractionDigits: 0, maximumFractionDigits: 2 })}`;
}

function formatDate(value: string): string {
  const d = new Date(value);
  if (Number.isNaN(d.getTime())) return value;
  return d.toLocaleDateString("en-IN", { day: "numeric", month: "short", year: "numeric" });
}

/* ── shared styles ───────────────────────────────────────────────────── */

const cardStyle = {
  background: "#fff",
  border: "1px solid rgba(15,23,42,.08)",
  borderRadius: 24,
  padding: "clamp(20px,4vw,30px)",
  boxShadow: "0 18px 44px rgba(15,23,42,.05)",
} as const;

const cardTitleStyle = {
  fontFamily: display,
  fontWeight: 800,
  fontSize: 20,
  letterSpacing: "-.02em",
  margin: 0,
} as const;

const labelStyle = {
  display: "block",
  fontSize: 13,
  fontWeight: 700,
  marginBottom: 7,
} as const;

const inputStyle = {
  width: "100%",
  height: 50,
  padding: "0 14px",
  borderRadius: 14,
  border: "1.5px solid #E2E8F0",
  fontSize: 15,
  fontWeight: 600,
  color: "#0F172A",
  outline: "none",
} as const;

const primaryButtonStyle = {
  height: 46,
  padding: "0 22px",
  borderRadius: 999,
  border: "none",
  color: "#fff",
  fontWeight: 700,
  fontSize: 14.5,
} as const;

const ghostButtonStyle = {
  height: 46,
  padding: "0 20px",
  borderRadius: 999,
  border: "1.5px solid rgba(15,23,42,.12)",
  background: "#fff",
  color: "#0F172A",
  fontWeight: 700,
  fontSize: 14.5,
  cursor: "pointer",
} as const;

const linkButtonStyle = {
  border: "none",
  background: "none",
  padding: 0,
  color: colors.teal,
  fontWeight: 700,
  fontSize: 14,
  cursor: "pointer",
} as const;

const errorBoxStyle = {
  background: "#FEF2F2",
  border: "1px solid #FECACA",
  color: "#B91C1C",
  borderRadius: 12,
  padding: "10px 13px",
  fontSize: 13.5,
  fontWeight: 600,
  marginBottom: 14,
} as const;
