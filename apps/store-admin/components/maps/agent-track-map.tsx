"use client";

import "leaflet/dist/leaflet.css";
import * as React from "react";
import L from "leaflet";
import { MapContainer, TileLayer, Marker, Polyline, useMap } from "react-leaflet";

export interface LatLng {
  lat: number;
  lng: number;
}

// Leaflet's default marker image paths break under any bundler (webpack/
// Turbopack rewrite the asset URLs its CSS bakes in) unless patched — the
// classic "marker icon is a broken image" issue. Divs styled directly sidestep
// it entirely instead of fighting the bundler over icon asset paths.
function dotIcon(color: string, label?: string) {
  return L.divIcon({
    className: "",
    html: `<div style="
        width:16px;height:16px;border-radius:9999px;background:${color};
        border:2px solid white;box-shadow:0 0 0 1px rgba(0,0,0,.25);
      "></div>${label ? `<div style="
        margin-top:2px;padding:1px 6px;border-radius:6px;background:white;
        font-size:11px;font-weight:600;white-space:nowrap;box-shadow:0 1px 2px rgba(0,0,0,.2);
        transform:translateX(-50%);position:relative;left:8px;
      ">${label}</div>` : ""}`,
    iconSize: [16, 16],
    iconAnchor: [8, 8],
  });
}

/** Recenters/fits the map whenever the point set changes, without fighting
 * the user's own pan/zoom on every single re-render. */
function FitBounds({ points }: { points: LatLng[] }) {
  const map = useMap();
  const key = points.map((p) => `${p.lat.toFixed(5)},${p.lng.toFixed(5)}`).join("|");
  React.useEffect(() => {
    if (points.length === 0) return;
    if (points.length === 1) {
      map.setView([points[0].lat, points[0].lng], 15);
      return;
    }
    map.fitBounds(points.map((p) => [p.lat, p.lng]), { padding: [40, 40], maxZoom: 16 });
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [key]);
  return null;
}

export function AgentTrackMap({
  agentPos,
  destPos,
  routePoints,
}: {
  agentPos: LatLng | null;
  destPos: LatLng | null;
  /** A real road-following path when available; otherwise a straight line is
   * drawn between the two points as a graceful fallback. */
  routePoints: LatLng[] | null;
}) {
  const points = [agentPos, destPos].filter((p): p is LatLng => p !== null);
  const line = routePoints && routePoints.length > 1 ? routePoints : points;
  const center = points[0] ?? { lat: 20.5937, lng: 78.9629 }; // India centroid fallback

  return (
    <MapContainer
      center={[center.lat, center.lng]}
      zoom={14}
      scrollWheelZoom
      style={{ height: "100%", width: "100%" }}
    >
      <TileLayer
        attribution='&copy; <a href="https://www.openstreetmap.org/copyright">OpenStreetMap</a> contributors'
        url="https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png"
      />
      {points.length > 0 && <FitBounds points={points} />}
      {line.length > 1 && (
        <Polyline
          positions={line.map((p) => [p.lat, p.lng])}
          pathOptions={{
            color: "#16a34a",
            weight: 4,
            opacity: 0.8,
            dashArray: routePoints && routePoints.length > 1 ? undefined : "6 8",
          }}
        />
      )}
      {agentPos && (
        <Marker
          position={[agentPos.lat, agentPos.lng]}
          icon={dotIcon("#16a34a", "Agent")}
        />
      )}
      {destPos && (
        <Marker
          position={[destPos.lat, destPos.lng]}
          icon={dotIcon("#dc2626", "Drop-off")}
        />
      )}
    </MapContainer>
  );
}
