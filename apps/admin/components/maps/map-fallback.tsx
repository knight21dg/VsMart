"use client";

import { Loader2, MapPinned, TriangleAlert } from "lucide-react";
import type { MapsStatus } from "@/lib/maps/loader";

/** Shown in place of a map while it loads, or when the browser Maps key is missing
 *  / the script fails. Keeps the surface intentional instead of a broken grey box. */
export function MapFallback({ status, height }: { status: MapsStatus; height: number }) {
  return (
    <div
      className="flex flex-col items-center justify-center gap-2 rounded-lg border border-dashed bg-muted/30 px-6 text-center"
      style={{ height }}
    >
      {status === "loading" && (
        <>
          <Loader2 className="size-5 animate-spin text-muted-foreground" />
          <p className="text-sm text-muted-foreground">Loading map…</p>
        </>
      )}
      {status === "no-key" && (
        <>
          <MapPinned className="size-6 text-muted-foreground" />
          <p className="text-sm font-medium">Map key not configured</p>
          <p className="max-w-sm text-xs text-muted-foreground">
            Set <code className="rounded bg-muted px-1 py-0.5 font-mono">NEXT_PUBLIC_GOOGLE_MAPS_API_KEY</code> in
            the admin app environment to enable Google Maps. You can still enter coordinates manually below.
          </p>
        </>
      )}
      {status === "error" && (
        <>
          <TriangleAlert className="size-6 text-destructive" />
          <p className="text-sm font-medium">Couldn&apos;t load Google Maps</p>
          <p className="max-w-sm text-xs text-muted-foreground">
            Check the API key restrictions (HTTP referrer) and that the Maps JavaScript API is enabled for this key.
          </p>
        </>
      )}
    </div>
  );
}
