/*
 * VS Mart Store Panel — service worker.
 *
 * Goal: let the POS (and the rest of the panel) cold-start while offline. The
 * app's billing logic already survives outages via IndexedDB (catalog cache +
 * sale outbox); this worker caches the *app shell* — HTML, JS/CSS chunks, fonts,
 * icons — so the browser can boot the app with no network at all.
 *
 * Strategy:
 *   - /_next/static/** and other immutable assets → cache-first (hashed URLs,
 *     safe to keep forever; we clean old caches on activate by version).
 *   - navigations (HTML / RSC) → network-first, fall back to the cached page,
 *     then to the last good shell, then to a built-in offline notice.
 *   - /api/** and non-GET → never touched here; the app owns offline behaviour
 *     (React Query + the POS outbox). Caching auth'd API data would be unsafe.
 *
 * Runtime caching (not precache): the first online visit populates the cache as
 * resources are requested, so a later offline reload serves from it. Bump
 * VERSION to invalidate everything on the next activate.
 */

const VERSION = "v1";
const STATIC_CACHE = `vsmart-store-static-${VERSION}`;
const PAGES_CACHE = `vsmart-store-pages-${VERSION}`;
const OWNED = [STATIC_CACHE, PAGES_CACHE];

// Served when a navigation is requested offline and nothing is cached yet.
const OFFLINE_FALLBACK = `<!doctype html><html lang="en"><head><meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1">
<title>Offline — VS Mart Store</title>
<style>body{margin:0;height:100vh;display:flex;align-items:center;justify-content:center;
font-family:system-ui,sans-serif;background:#f6f8f9;color:#0f172a;text-align:center}
.box{max-width:22rem;padding:2rem}.box h1{font-size:1.1rem;margin:0 0 .5rem}
.box p{color:#64748b;font-size:.9rem;line-height:1.5;margin:0 0 1.25rem}
button{background:#558b2f;color:#fff;border:0;border-radius:.5rem;padding:.6rem 1.1rem;
font-size:.9rem;font-weight:600;cursor:pointer}</style></head>
<body><div class="box"><h1>You're offline</h1>
<p>This page hasn't been saved for offline use yet. Reconnect once to cache it — the
POS keeps working offline after that.</p>
<button onclick="location.reload()">Try again</button></div></body></html>`;

self.addEventListener("install", (event) => {
  // Take over as soon as installed; the page-side update flow gates the reload.
  event.waitUntil(self.skipWaiting());
});

self.addEventListener("activate", (event) => {
  event.waitUntil(
    (async () => {
      const keys = await caches.keys();
      await Promise.all(keys.filter((k) => !OWNED.includes(k)).map((k) => caches.delete(k)));
      await self.clients.claim();
    })(),
  );
});

// Let the page trigger an immediate activation when the user accepts an update.
self.addEventListener("message", (event) => {
  if (event.data === "SKIP_WAITING") self.skipWaiting();
});

function isStaticAsset(url) {
  return (
    url.pathname.startsWith("/_next/static/") ||
    /\.(?:js|css|woff2?|ttf|otf|png|jpe?g|svg|gif|webp|ico|webmanifest)$/.test(url.pathname)
  );
}

async function cacheFirst(request) {
  const cache = await caches.open(STATIC_CACHE);
  const hit = await cache.match(request);
  if (hit) return hit;
  const resp = await fetch(request);
  if (resp.ok && resp.type === "basic") cache.put(request, resp.clone());
  return resp;
}

async function networkFirstPage(request) {
  const cache = await caches.open(PAGES_CACHE);
  try {
    const resp = await fetch(request);
    if (resp.ok && resp.type === "basic") cache.put(request, resp.clone());
    return resp;
  } catch {
    const hit = (await cache.match(request)) || (await cache.match("/pos")) || (await cache.match("/"));
    if (hit) return hit;
    return new Response(OFFLINE_FALLBACK, {
      headers: { "Content-Type": "text/html; charset=utf-8" },
      status: 200,
    });
  }
}

self.addEventListener("fetch", (event) => {
  const { request } = event;
  if (request.method !== "GET") return;

  const url = new URL(request.url);
  if (url.origin !== self.location.origin) return; // leave cross-origin alone
  if (url.pathname.startsWith("/api/")) return; // app owns offline for the API
  if (url.pathname === "/sw.js") return;

  if (request.mode === "navigate") {
    event.respondWith(networkFirstPage(request));
    return;
  }
  if (isStaticAsset(url)) {
    event.respondWith(cacheFirst(request));
  }
});

/*
 * "New Order" push (Case 2 — the tab is fully closed, but the browser is
 * still running; the WebSocket in lib/realtime/use-store-orders-socket.ts
 * covers the tab-open case and never touches this file). Handled with the
 * raw Push API rather than the Firebase SDK's onBackgroundMessage — FCM
 * webpush delivers as a standard Push message under the hood, so there's no
 * need to load ~50KB of Firebase JS into this worker just to read it.
 */
self.addEventListener("push", (event) => {
  let payload = {};
  try {
    payload = event.data ? event.data.json() : {};
  } catch {
    return;
  }
  const notification = payload.notification || {};
  const data = payload.data || {};
  const title = notification.title || "VS Mart Store";
  const body = notification.body || "";
  const link = (payload.fcmOptions && payload.fcmOptions.link) || data.route || "/";

  event.waitUntil(
    self.registration.showNotification(title, {
      body,
      icon: notification.icon || "/icon-192.png",
      badge: "/icon-192.png",
      data: { link },
      requireInteraction: true,
      tag: data.orderCode || undefined,
    }),
  );
});

self.addEventListener("notificationclick", (event) => {
  event.notification.close();
  const link = (event.notification.data && event.notification.data.link) || "/";
  event.waitUntil(
    (async () => {
      const clientsList = await self.clients.matchAll({ type: "window", includeUncontrolled: true });
      for (const client of clientsList) {
        if ("focus" in client) {
          await client.focus();
          if ("navigate" in client) await client.navigate(link);
          return;
        }
      }
      await self.clients.openWindow(link);
    })(),
  );
});
