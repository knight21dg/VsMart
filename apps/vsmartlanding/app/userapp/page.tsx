import type { Metadata } from "next";
import fs from "node:fs";
import path from "node:path";
import Nav from "../components/Nav";
import Footer from "../components/Footer";
import { colors, display, mono } from "../components/ui";

export const metadata: Metadata = {
  title: "Download the VS Mart app",
  description:
    "Install the VS Mart Android app — shop groceries, pay later with VS Credit, and track every delivery.",
};

// Read fresh on each request so dropping in a new build shows up without a
// rebuild. The APK lives on the host (mounted at /srv/downloads for Caddy) and
// is served at /downloads/... — never bundled into this Next image.
export const dynamic = "force-dynamic";

const APK_PATH = "/downloads/vsmart.apk";

/** Candidate locations for the APK, in priority order: an explicit override,
 *  then the container mount. Falls back to walking up from the working
 *  directory to find a repo-level `downloads/` so the page shows real numbers
 *  in local dev too — where cwd depends on how the server was launched. */
function apkCandidates(): string[] {
  const found = [process.env.APK_FILE_PATH, "/srv/downloads/vsmart.apk"].filter(
    Boolean
  ) as string[];
  let dir = process.cwd();
  for (let i = 0; i < 5; i++) {
    found.push(path.join(dir, "downloads", "vsmart.apk"));
    const parent = path.dirname(dir);
    if (parent === dir) break;
    dir = parent;
  }
  return found;
}

interface BuildInfo {
  available: boolean;
  sizeMb?: string;
  updated?: string;
}

function readBuildInfo(): BuildInfo {
  for (const candidate of apkCandidates()) {
    try {
      const stat = fs.statSync(path.resolve(candidate));
      return {
        available: true,
        sizeMb: (stat.size / (1024 * 1024)).toFixed(1),
        updated: stat.mtime.toLocaleDateString("en-IN", {
          day: "numeric",
          month: "long",
          year: "numeric",
        }),
      };
    } catch {
      // Try the next location.
    }
  }
  // No build published yet — show an honest "coming soon" rather than a
  // download button that 404s.
  return { available: false };
}

const steps = [
  {
    n: "01",
    title: "Download the APK",
    body: "Tap the button above. Your browser may warn that this file type can harm your device — that is Android's standard notice for any app installed outside the Play Store.",
  },
  {
    n: "02",
    title: "Allow the install",
    body: "Open the downloaded file. If Android asks, enable “Install unknown apps” for your browser, then come back and tap Install.",
  },
  {
    n: "03",
    title: "Sign in with your mobile number",
    body: "Enter your number, confirm the OTP, and you're in. Your cart, orders and VS Credit follow your account.",
  },
];

export default function UserAppPage() {
  const build = readBuildInfo();

  return (
    <>
      <Nav />
      <main style={{ background: colors.bg, minHeight: "100vh" }}>
        <section
          style={{
            maxWidth: 880,
            margin: "0 auto",
            padding: "140px 24px 72px",
          }}
        >
          <p
            style={{
              fontFamily: mono,
              fontSize: 12,
              fontWeight: 600,
              letterSpacing: ".14em",
              color: colors.teal,
              textTransform: "uppercase",
              marginBottom: 16,
            }}
          >
            Android app
          </p>

          <h1
            style={{
              fontFamily: display,
              fontSize: "clamp(34px, 6vw, 56px)",
              lineHeight: 1.08,
              letterSpacing: "-0.02em",
              color: colors.dark,
              margin: 0,
            }}
          >
            Get the VS Mart app
          </h1>

          <p
            style={{
              fontSize: 17,
              lineHeight: 1.65,
              color: "#475569",
              maxWidth: 560,
              marginTop: 18,
            }}
          >
            Shop your daily groceries, pay later with VS Credit, and follow every
            order from the shop to your door.
          </p>

          <div style={{ marginTop: 36 }}>
            {build.available ? (
              <>
                <a
                  href={APK_PATH}
                  download
                  style={{
                    display: "inline-flex",
                    alignItems: "center",
                    gap: 12,
                    padding: "18px 34px",
                    borderRadius: 14,
                    background: colors.teal,
                    color: "#fff",
                    fontFamily: display,
                    fontSize: 17,
                    fontWeight: 700,
                    textDecoration: "none",
                    boxShadow: "0 10px 28px rgba(0,109,119,.28)",
                  }}
                >
                  <DownloadIcon />
                  Download for Android
                </a>
                <p
                  style={{
                    fontFamily: mono,
                    fontSize: 12.5,
                    color: "#64748B",
                    marginTop: 14,
                  }}
                >
                  APK · {build.sizeMb} MB · Updated {build.updated} · Android 6.0
                  and above
                </p>
              </>
            ) : (
              <div
                style={{
                  display: "inline-block",
                  padding: "18px 30px",
                  borderRadius: 14,
                  background: "#fff",
                  border: "1.5px solid #E2E8F0",
                  color: "#475569",
                  fontSize: 15.5,
                  fontWeight: 600,
                }}
              >
                The Android build is being prepared — check back shortly.
              </div>
            )}
          </div>

          <div
            style={{
              marginTop: 56,
              display: "grid",
              gap: 18,
            }}
          >
            {steps.map((s) => (
              <div
                key={s.n}
                style={{
                  display: "flex",
                  gap: 18,
                  padding: "22px 24px",
                  background: "#fff",
                  border: "1.5px solid #E2E8F0",
                  borderRadius: 16,
                }}
              >
                <span
                  style={{
                    fontFamily: mono,
                    fontSize: 13,
                    fontWeight: 700,
                    color: colors.green,
                    paddingTop: 2,
                  }}
                >
                  {s.n}
                </span>
                <div>
                  <h2
                    style={{
                      fontFamily: display,
                      fontSize: 17,
                      fontWeight: 700,
                      color: colors.dark,
                      margin: "0 0 6px",
                    }}
                  >
                    {s.title}
                  </h2>
                  <p
                    style={{
                      fontSize: 14.5,
                      lineHeight: 1.6,
                      color: "#64748B",
                      margin: 0,
                    }}
                  >
                    {s.body}
                  </p>
                </div>
              </div>
            ))}
          </div>

          <p
            style={{
              marginTop: 32,
              fontSize: 13.5,
              lineHeight: 1.6,
              color: "#94A3B8",
            }}
          >
            Downloaded straight from VS Mart. An iOS build and a Play Store
            listing are on the way.
          </p>
        </section>
      </main>
      <Footer />
    </>
  );
}

function DownloadIcon() {
  return (
    <svg
      width="20"
      height="20"
      viewBox="0 0 24 24"
      fill="none"
      stroke="currentColor"
      strokeWidth="2.2"
      strokeLinecap="round"
      strokeLinejoin="round"
      aria-hidden="true"
    >
      <path d="M21 15v4a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2v-4" />
      <polyline points="7 10 12 15 17 10" />
      <line x1="12" y1="15" x2="12" y2="3" />
    </svg>
  );
}
