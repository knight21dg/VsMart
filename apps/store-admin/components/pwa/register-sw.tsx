"use client";

import * as React from "react";
import { toast } from "sonner";

/**
 * Registers the service worker that powers offline cold-start (see public/sw.js)
 * and surfaces a non-blocking toast when a new version is waiting, so cashiers
 * mid-shift are never force-reloaded.
 *
 * Registered in production only: a caching worker fighting the dev server's HMR
 * and per-reload chunk hashes causes stale-asset breakage. Renders nothing.
 */
export function RegisterSW() {
  React.useEffect(() => {
    if (process.env.NODE_ENV !== "production") return;
    if (typeof navigator === "undefined" || !("serviceWorker" in navigator)) return;

    let refreshing = false;
    // When the freshly-activated worker takes control, reload once to pick it up.
    navigator.serviceWorker.addEventListener("controllerchange", () => {
      if (refreshing) return;
      refreshing = true;
      window.location.reload();
    });

    navigator.serviceWorker
      .register("/sw.js", { scope: "/", updateViaCache: "none" })
      .then((reg) => {
        function promptUpdate(worker: ServiceWorker | null) {
          if (!worker) return;
          toast("A new version is available", {
            description: "Reload to update the store panel.",
            duration: Infinity,
            action: {
              label: "Reload",
              onClick: () => worker.postMessage("SKIP_WAITING"),
            },
          });
        }

        // An update was already waiting when this tab opened.
        if (reg.waiting && navigator.serviceWorker.controller) promptUpdate(reg.waiting);

        reg.addEventListener("updatefound", () => {
          const installing = reg.installing;
          installing?.addEventListener("statechange", () => {
            // "installed" + an existing controller ⇒ this is an update, not first install.
            if (installing.state === "installed" && navigator.serviceWorker.controller) {
              promptUpdate(reg.waiting ?? installing);
            }
          });
        });
      })
      .catch(() => {
        // Registration failures are non-fatal — the app works online regardless.
      });
  }, []);

  return null;
}
