// Android App Links verification.
//
// Android fetches https://thevsmart.com/.well-known/assetlinks.json at install
// time and only lets the app intercept our https links if the installed APK's
// signing certificate is listed here. Until a correct fingerprint is configured
// the links keep opening in the browser — a silent degradation, not a crash.
//
// IMPORTANT — which fingerprint: with Play App Signing (which this app uses),
// Google re-signs the upload artifact, so the fingerprint Android checks is the
// **app signing key**, NOT the upload key. Take it from
//   Play Console → Test and release → Setup → App integrity
//     → App signing key certificate → SHA-256
// Using the upload-key fingerprint documented in PLAY_CONSOLE_VSMART.md will make
// verification fail for every Play-installed build.
//
// Configure via env (comma-separated to list several — you generally want the
// Play app-signing key AND the upload key, plus a debug key for local testing):
//   ANDROID_SHA256_CERT_FINGERPRINTS="AB:CD:...,12:34:..."
//   ANDROID_PACKAGE_NAME (optional, defaults below)
//
// Verify once deployed:
//   curl -sS https://thevsmart.com/.well-known/assetlinks.json
//   adb shell pm get-app-links com.vsmart.user_app     → "verified"

// Read env per request so the fingerprint can be rotated with a container
// restart instead of a rebuild.
export const dynamic = "force-dynamic";

const DEFAULT_PACKAGE = "com.vsmart.user_app";

function fingerprints(): string[] {
  return (process.env.ANDROID_SHA256_CERT_FINGERPRINTS ?? "")
    .split(",")
    .map((f) => f.trim().toUpperCase())
    .filter(Boolean);
}

export async function GET() {
  const certs = fingerprints();

  // Serving a statement list with no fingerprints would look configured while
  // never verifying. A 404 makes the missing setup obvious in curl and in the
  // Play Console's App Links report.
  if (certs.length === 0) {
    return new Response(
      "App Links are not configured: set ANDROID_SHA256_CERT_FINGERPRINTS.\n",
      { status: 404, headers: { "Content-Type": "text/plain; charset=utf-8" } },
    );
  }

  const statements = [
    {
      relation: ["delegate_permission/common.handle_all_urls"],
      target: {
        namespace: "android_app",
        package_name: process.env.ANDROID_PACKAGE_NAME ?? DEFAULT_PACKAGE,
        sha256_cert_fingerprints: certs,
      },
    },
  ];

  return new Response(JSON.stringify(statements, null, 2), {
    status: 200,
    headers: {
      // Android requires application/json and follows no redirects.
      "Content-Type": "application/json",
      "Cache-Control": "public, max-age=300",
    },
  });
}
