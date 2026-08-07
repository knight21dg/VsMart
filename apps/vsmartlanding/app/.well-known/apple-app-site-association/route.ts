// iOS Universal Links verification.
//
// Apple fetches https://thevsmart.com/.well-known/apple-app-site-association when
// the app is installed. Two hard requirements this Route Handler exists to meet:
//   * the file is served with NO extension (hence the directory name), and
//   * the Content-Type must be application/json.
// Dropping a file in `public/` cannot satisfy both — an extensionless static file
// is served as application/octet-stream and Apple rejects it.
//
// BLOCKED until an Apple Team ID is available: `appIDs` must be
// "<TeamID>.com.vsmart.userApp", and no DEVELOPMENT_TEAM is set anywhere in the
// repo (see CODEMAGIC_IOS.md — signing is delegated to an App Store Connect API
// key, which never writes the Team ID into the project). Find it at
//   developer.apple.com → Membership → Team ID
// then set:
//   APPLE_APP_ID="ABCDE12345.com.vsmart.userApp"
//
// The app side also needs Associated Domains (`applinks:thevsmart.com`) enabled
// on the Runner target — see ios/Runner/Runner.entitlements.
//
// Verify once deployed:
//   curl -sSI https://thevsmart.com/.well-known/apple-app-site-association
//     → Content-Type: application/json

export const dynamic = "force-dynamic";

export async function GET() {
  const appId = (process.env.APPLE_APP_ID ?? "").trim();

  if (!appId) {
    return new Response(
      "Universal Links are not configured: set APPLE_APP_ID " +
        '("<TeamID>.com.vsmart.userApp").\n',
      { status: 404, headers: { "Content-Type": "text/plain; charset=utf-8" } },
    );
  }

  const association = {
    applinks: {
      details: [
        {
          appIDs: [appId],
          // Scoped to the links we actually publish, so marketing pages, /privacy
          // and /terms keep opening in Safari.
          components: [
            { "/": "/products/*", comment: "Product share links" },
            { "/": "/product/*", comment: "Legacy singular product alias" },
          ],
        },
      ],
    },
  };

  return new Response(JSON.stringify(association, null, 2), {
    status: 200,
    headers: {
      "Content-Type": "application/json",
      "Cache-Control": "public, max-age=300",
    },
  });
}
