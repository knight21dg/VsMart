import type { Metadata } from "next";
import { redirect } from "next/navigation";

import Footer from "../components/Footer";
import Nav from "../components/Nav";
import { hasSessionCookie } from "../lib/session";
import AccountClient from "./AccountClient";

export const metadata: Metadata = {
  title: "My account",
  description: "Your VS Mart profile, orders and account settings.",
  robots: { index: false, follow: false },
};

export const dynamic = "force-dynamic";

export default async function AccountPage() {
  // Cheap gate on the cookie so signed-out visitors never see a flash of the
  // account shell; the data routes enforce the real check against the API.
  if (!(await hasSessionCookie())) redirect("/login?next=/account");

  return (
    <div
      style={{
        overflowX: "hidden",
        display: "flex",
        flexDirection: "column",
        minHeight: "100vh",
      }}
    >
      <Nav />
      <main
        style={{
          flex: 1,
          padding: "clamp(28px,5vw,56px) clamp(16px,5vw,28px) clamp(56px,8vw,96px)",
        }}
      >
        <div style={{ maxWidth: 860, margin: "0 auto" }}>
          <AccountClient />
        </div>
      </main>
      <Footer />
    </div>
  );
}
