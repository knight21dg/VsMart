"use client";

import * as React from "react";
import dynamic from "next/dynamic";
import { Loader2, Phone } from "lucide-react";
import { api } from "@/lib/api/hooks";
import { useOrderTrackingSocket } from "@/lib/realtime/use-order-tracking-socket";
import { decodePolyline } from "@/lib/maps/decode-polyline";
import { Dialog, DialogContent, DialogHeader, DialogTitle, DialogDescription } from "@/components/ui/dialog";
import { StatusBadge } from "@/components/status-badge";
import { Button } from "@/components/ui/button";
import type { LatLng } from "@/components/maps/agent-track-map";

// Leaflet touches `window` at import time — must never run during SSR.
const AgentTrackMap = dynamic(
  () => import("@/components/maps/agent-track-map").then((m) => m.AgentTrackMap),
  { ssr: false, loading: () => <MapPlaceholder /> },
);

function MapPlaceholder() {
  return (
    <div className="flex h-full items-center justify-center text-sm text-muted-foreground">
      <Loader2 className="mr-2 size-4 animate-spin" /> Loading map…
    </div>
  );
}

// Re-fetch the road route only when the agent has actually moved enough to
// make the old one stale — same threshold the customer app's tracking map
// uses. A route call is a real, billed Directions request; re-firing it on
// every ~15s GPS ping for someone who hasn't moved would just burn quota.
const ROUTE_REFRESH_METERS = 120;

function metersBetween(a: LatLng, b: LatLng): number {
  const R = 6371000;
  const dLat = ((b.lat - a.lat) * Math.PI) / 180;
  const dLng = ((b.lng - a.lng) * Math.PI) / 180;
  const s =
    Math.sin(dLat / 2) ** 2 +
    Math.cos((a.lat * Math.PI) / 180) * Math.cos((b.lat * Math.PI) / 180) * Math.sin(dLng / 2) ** 2;
  return 2 * R * Math.asin(Math.sqrt(s));
}

/**
 * A live map of one delivery's agent — the store-panel counterpart to what
 * the customer already sees on their own tracking screen. Opened from a
 * "Track" button on an in-flight delivery row; subscribes to the same
 * ws/orders/<code>/tracking channel over WebSocket, so the pin moves as the
 * agent's GPS pings arrive rather than needing a manual refresh.
 */
export function AgentTrackDialog({
  orderCode,
  onClose,
}: {
  orderCode: string | null;
  onClose: () => void;
}) {
  const open = orderCode !== null;
  const { snapshot, connected } = useOrderTrackingSocket(orderCode, open);
  const [routePoints, setRoutePoints] = React.useState<LatLng[] | null>(null);
  const lastRouteOrigin = React.useRef<LatLng | null>(null);

  const agentPos: LatLng | null =
    snapshot?.latitude != null && snapshot?.longitude != null
      ? { lat: snapshot.latitude, lng: snapshot.longitude }
      : null;
  const destPos: LatLng | null =
    snapshot?.destLat != null && snapshot?.destLng != null
      ? { lat: snapshot.destLat, lng: snapshot.destLng }
      : null;

  React.useEffect(() => {
    if (!agentPos || !destPos) return;
    const moved = !lastRouteOrigin.current
      || metersBetween(lastRouteOrigin.current, agentPos) >= ROUTE_REFRESH_METERS;
    if (!moved) return;
    lastRouteOrigin.current = agentPos;
    let cancelled = false;
    api
      .get<{ encodedPolyline: string }>("/geo/route", {
        origin: `${agentPos.lat},${agentPos.lng}`,
        dest: `${destPos.lat},${destPos.lng}`,
      })
      .then((r) => {
        if (cancelled || !r.encodedPolyline) return;
        setRoutePoints(decodePolyline(r.encodedPolyline));
      })
      .catch(() => {
        /* falls back to the straight line the map already draws */
      });
    return () => {
      cancelled = true;
    };
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [agentPos?.lat, agentPos?.lng, destPos?.lat, destPos?.lng]);

  function close() {
    setRoutePoints(null);
    lastRouteOrigin.current = null;
    onClose();
  }

  return (
    <Dialog open={open} onOpenChange={(o) => !o && close()}>
      <DialogContent className="max-w-2xl">
        <DialogHeader>
          <DialogTitle className="flex items-center gap-2">
            Tracking {orderCode}
            <span
              className={`inline-flex items-center gap-1 rounded-full px-2 py-0.5 text-xs font-medium ${
                connected ? "bg-[var(--color-success)]/10 text-[var(--color-success)]" : "bg-muted text-muted-foreground"
              }`}
            >
              <span className={`size-1.5 rounded-full ${connected ? "bg-[var(--color-success)] animate-pulse" : "bg-muted-foreground"}`} />
              {connected ? "Live" : "Reconnecting…"}
            </span>
          </DialogTitle>
          <DialogDescription>
            {snapshot ? (
              <span className="flex flex-wrap items-center gap-x-3 gap-y-1">
                <span>{snapshot.agentName || "Agent"}</span>
                {snapshot.agentPhone && (
                  <a href={`tel:${snapshot.agentPhone}`} className="inline-flex items-center gap-1 text-primary hover:underline">
                    <Phone className="size-3" /> {snapshot.agentPhone}
                  </a>
                )}
                {snapshot.deliveryStatus && <StatusBadge status={snapshot.deliveryStatus} />}
                {snapshot.eta && <span className="text-muted-foreground">ETA {snapshot.eta}</span>}
              </span>
            ) : (
              "Waiting for the agent's position…"
            )}
          </DialogDescription>
        </DialogHeader>

        <div className="h-[420px] overflow-hidden rounded-lg border">
          <AgentTrackMap agentPos={agentPos} destPos={destPos} routePoints={routePoints} />
        </div>

        <div className="flex justify-end">
          <Button variant="outline" onClick={close}>Close</Button>
        </div>
      </DialogContent>
    </Dialog>
  );
}
