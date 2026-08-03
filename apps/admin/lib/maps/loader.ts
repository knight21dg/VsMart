"use client";

import * as React from "react";

/**
 * Single-load bootstrap for the Google Maps JavaScript API.
 *
 * The browser key is a **separate** referrer-restricted key from the backend's
 * server key (which powers the /geo/* proxy). Set it in the admin app env as
 * `NEXT_PUBLIC_GOOGLE_MAPS_API_KEY`. Every map component calls `useGoogleMaps()`
 * and renders a graceful fallback when the key is missing or the script fails,
 * so the console never shows a broken grey box.
 */

const LIBRARIES = "geometry";
let loadPromise: Promise<void> | null = null;

/** Default map centre when the operator's location can't be resolved (Kakinada). */
export const DEFAULT_CENTER = { lat: 16.9891, lng: 82.2475 };

/** The browser's current GPS position, or the Kakinada fallback when geolocation is
 *  unavailable, denied, or times out. Never rejects. */
export function currentLocationOrDefault(): Promise<{ lat: number; lng: number }> {
  return new Promise((resolve) => {
    if (typeof navigator === "undefined" || !navigator.geolocation) {
      resolve(DEFAULT_CENTER);
      return;
    }
    navigator.geolocation.getCurrentPosition(
      (pos) => resolve({ lat: pos.coords.latitude, lng: pos.coords.longitude }),
      () => resolve(DEFAULT_CENTER),
      { timeout: 8000, maximumAge: 300000 }
    );
  });
}

export function mapsApiKey(): string {
  return process.env.NEXT_PUBLIC_GOOGLE_MAPS_API_KEY?.trim() || "";
}

export function isMapsReady(): boolean {
  return typeof window !== "undefined" && !!window.google?.maps;
}

/** Injects the Maps JS script exactly once (idempotent across all map components). */
export function loadGoogleMaps(): Promise<void> {
  if (typeof window === "undefined") return Promise.reject(new Error("no-window"));
  if (window.google?.maps) return Promise.resolve();
  if (loadPromise) return loadPromise;

  const key = mapsApiKey();
  if (!key) return Promise.reject(new Error("no-key"));

  loadPromise = new Promise<void>((resolve, reject) => {
    const CALLBACK = "__vsmartGoogleMapsReady";
    (window as unknown as Record<string, unknown>)[CALLBACK] = () => resolve();

    const script = document.createElement("script");
    script.src =
      "https://maps.googleapis.com/maps/api/js" +
      `?key=${encodeURIComponent(key)}` +
      `&libraries=${LIBRARIES}` +
      `&callback=${CALLBACK}` +
      "&loading=async&v=weekly";
    script.async = true;
    script.defer = true;
    script.onerror = () => {
      loadPromise = null;
      reject(new Error("load-failed"));
    };
    document.head.appendChild(script);
  });
  return loadPromise;
}

export type MapsStatus = "loading" | "ready" | "no-key" | "error";

/** React hook that loads the API and reports its status for conditional rendering. */
export function useGoogleMaps(): MapsStatus {
  const [status, setStatus] = React.useState<MapsStatus>(() => {
    if (isMapsReady()) return "ready";
    return mapsApiKey() ? "loading" : "no-key";
  });

  React.useEffect(() => {
    // Initial state already resolves no-key / ready / loading synchronously; the
    // effect only awaits the async script load, updating state from its callbacks
    // (never synchronously in the effect body).
    if (!mapsApiKey()) return;
    let alive = true;
    loadGoogleMaps()
      .then(() => alive && setStatus("ready"))
      .catch((e: Error) => alive && setStatus(e.message === "no-key" ? "no-key" : "error"));
    return () => {
      alive = false;
    };
  }, []);

  return status;
}
