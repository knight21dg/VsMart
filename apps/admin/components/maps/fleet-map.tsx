"use client";

import * as React from "react";
import { useGoogleMaps } from "@/lib/maps/loader";

export interface Rider {
  id: number;
  orderCode: string | null;
  status: string;
  agent: string | null;
  zone: string | null;
  lat: number | null;
  lng: number | null;
  destLat: number | null;
  destLng: number | null;
  eta?: string;
  address?: string;
}

const BENGALURU: google.maps.LatLngLiteral = { lat: 12.9716, lng: 77.5946 };

const STATUS_COLOR: Record<string, string> = {
  assigned: "#64748B",
  accepted: "#0EA5E9",
  picked_up: "#D97706",
  out_for_delivery: "#16A34A",
  reached: "#7C3AED",
};

/** Live last-mile fleet on Google Maps: one marker per active rider (coloured by
 *  status), a dashed line to its destination, and a destination pin. */
export function FleetMap({ riders }: { riders: Rider[] }) {
  const status = useGoogleMaps();
  const divRef = React.useRef<HTMLDivElement>(null);
  const mapRef = React.useRef<google.maps.Map | null>(null);
  const infoRef = React.useRef<google.maps.InfoWindow | null>(null);
  const overlaysRef = React.useRef<Array<google.maps.Marker | google.maps.Polyline>>([]);

  React.useEffect(() => {
    if (status !== "ready" || !divRef.current || mapRef.current) return;
    mapRef.current = new google.maps.Map(divRef.current, {
      center: BENGALURU,
      zoom: 11,
      mapTypeControl: false,
      streetViewControl: false,
      fullscreenControl: false,
      clickableIcons: false,
    });
    infoRef.current = new google.maps.InfoWindow();
  }, [status]);

  React.useEffect(() => {
    const map = mapRef.current;
    if (status !== "ready" || !map) return;

    overlaysRef.current.forEach((o) => o.setMap(null));
    overlaysRef.current = [];

    const positioned = riders.filter((r) => r.lat != null && r.lng != null);
    const bounds = new google.maps.LatLngBounds();

    for (const r of positioned) {
      const pos = { lat: r.lat as number, lng: r.lng as number };
      const color = STATUS_COLOR[r.status] ?? "#334155";
      bounds.extend(pos);

      if (r.destLat != null && r.destLng != null) {
        const dest = { lat: r.destLat, lng: r.destLng };
        bounds.extend(dest);
        overlaysRef.current.push(
          new google.maps.Polyline({
            path: [pos, dest],
            map,
            strokeColor: color,
            strokeOpacity: 0,
            icons: [
              {
                icon: { path: "M 0,-1 0,1", strokeOpacity: 0.5, scale: 3 },
                offset: "0",
                repeat: "12px",
              },
            ],
          }),
          new google.maps.Marker({
            position: dest,
            map,
            title: `Drop: ${r.address || r.orderCode || ""}`,
            icon: {
              path: google.maps.SymbolPath.CIRCLE,
              scale: 5,
              fillColor: "#CBD5E1",
              fillOpacity: 1,
              strokeColor: "#94A3B8",
              strokeWeight: 1,
            },
          })
        );
      }

      const marker = new google.maps.Marker({
        position: pos,
        map,
        icon: {
          path: google.maps.SymbolPath.CIRCLE,
          scale: 8,
          fillColor: color,
          fillOpacity: 1,
          strokeColor: "#fff",
          strokeWeight: 2,
        },
      });
      marker.addListener("click", () => {
        infoRef.current?.setContent(
          `<div style="font-size:12px;line-height:1.4">
             <div style="font-weight:600">${escapeHtml(r.orderCode || "—")}</div>
             <div>${escapeHtml(r.agent || "Unassigned")}</div>
             <div style="text-transform:capitalize">${escapeHtml(r.status.replace(/_/g, " "))}</div>
             ${r.eta ? `<div>ETA ${escapeHtml(r.eta)}</div>` : ""}
           </div>`
        );
        infoRef.current?.open({ map, anchor: marker });
      });
      overlaysRef.current.push(marker);
    }

    if (positioned.length === 1) {
      map.setCenter({ lat: positioned[0].lat as number, lng: positioned[0].lng as number });
      map.setZoom(14);
    } else if (positioned.length > 1 && !bounds.isEmpty()) {
      map.fitBounds(bounds, 40);
    }
  }, [status, riders]);

  if (status !== "ready") {
    return (
      <div className="flex h-full w-full items-center justify-center bg-muted/30 text-sm text-muted-foreground">
        {status === "no-key"
          ? "Set NEXT_PUBLIC_GOOGLE_MAPS_API_KEY to show the live fleet map."
          : status === "error"
            ? "Couldn't load Google Maps."
            : "Loading map…"}
      </div>
    );
  }

  return <div ref={divRef} className="h-full w-full" />;
}

function escapeHtml(s: string): string {
  return s.replace(/[&<>"']/g, (c) =>
    ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" })[c] as string
  );
}
