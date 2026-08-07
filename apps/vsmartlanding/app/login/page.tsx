import type { Metadata } from "next";
import { redirect } from "next/navigation";

import Footer from "../components/Footer";
import Nav from "../components/Nav";
import { safeNextPath } from "../lib/route-utils";
import { hasSessionCookie } from "../lib/session";
import LoginForm from "./LoginForm";

export const metadata: Metadata = {
  title: "Sign in",
  description:
    "Sign in to your VS Mart account with a one-time code sent to your mobile number.",
  alternates: { canonical: "/login" },
  // A personal sign-in page has nothing to index.
  robots: { index: false, follow: true },
};

// Reads the session cookie — never prerendered.
export const dynamic = "force-dynamic";

export default async function LoginPage({
  searchParams,
}: {
  searchParams: Promise<{ next?: string }>;
}) {
  const { next } = await searchParams;
  const target = safeNextPath(next);

  if (await hasSessionCookie()) redirect(target);

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
          display: "flex",
          alignItems: "flex-start",
          justifyContent: "center",
          padding: "clamp(32px,6vw,72px) clamp(16px,5vw,28px) clamp(56px,8vw,96px)",
        }}
      >
        <LoginForm next={target} />
      </main>
      <Footer />
    </div>
  );
}
