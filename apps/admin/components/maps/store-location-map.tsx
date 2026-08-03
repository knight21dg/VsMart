"use client";

import * as React from "react";
import { api } from "@/lib/api/client";
import { currentLocationOrDefault, DEFAULT_CENTER, useGoogleMaps } from "@/lib/maps/loader";
import { geometryToPaths, pointInGeometry, type GeoJSONGeometry } from "@/lib/maps/geojson";
import { MapFallback } from "./map-fallback";
import { MapPlacesSearch } from "./map-places-search";

const BRAND = "#006d77";

interface ZoneShape {
  id: string;
  name: string;
  geometry: GeoJSONGeometry;
}

/**
 * Google Maps store-location picker. Search a place (backend Places proxy), click the
 * map, or drag the pin to set the exact store coordinates. Existing service zones are
 * overlaid and the picker reports which zone the point falls inside (derived purely
 * from the polygons) plus a reverse-geocoded address — so the operator places the
 * store precisely and in-zone.
 */
export function StoreLocationMap({
  lat,
  lng,
  onChange,
  zones = [],
  onResolvedAddress,
  height = 360,
}: {
  lat: number | null;
  lng: number | null;
  onChange: (lat: number, lng: number) => void;
  zones?: ZoneShape[];
  onResolvedAddress?: (address: string) => void;
  height?: number;
}) {
  const status = useGoogleMaps();
  const divRef = React.useRef<HTMLDivElement>(null);
  const mapRef = React.useRef<google.maps.Map | null>(null);
  const markerRef = React.useRef<google.maps.Marker | null>(null);
  const zonePolysRef = React.useRef<google.maps.Polygon[]>([]);
  const onChangeRef = React.useRef(onChange);
  const onAddrRef = React.useRef(onResolvedAddress);

  React.useEffect(() => {
    onChangeRef.current = onChange;
    onAddrRef.current = onResolvedAddress;
  });

  const [address, setAddress] = React.useState<string>("");

  const hasPoint = lat != null && lng != null && !Number.isNaN(lat) && !Number.isNaN(lng);

  // Zone containment is derived at render — pure, no map/geometry library needed.
  const zoneHint = hasPoint ? zones.find((z) => pointInGeometry(lat as number, lng as number, z.geometry)) : undefined;

  // ── Initialise map ──────────────────────────────────────────────────────
  React.useEffect(() => {
    if (status !== "ready" || !divRef.current || mapRef.current) return;
    const map = new google.maps.Map(divRef.current, {
      center: hasPoint ? { lat: lat as number, lng: lng as number } : DEFAULT_CENTER,
      zoom: hasPoint ? 15 : 11,
      mapTypeControl: false,
      streetViewControl: false,
      fullscreenControl: false,
      clickableIcons: false,
    });
    mapRef.current = map;
    map.addListener("click", (e: google.maps.MapMouseEvent) => {
      if (e.latLng) onChangeRef.current(round(e.latLng.lat()), round(e.latLng.lng()));
    });
    // No store point yet → centre on the operator's GPS location (Kakinada fallback).
    if (!hasPoint) {
      currentLocationOrDefault().then((loc) => {
        if (mapRef.current === map) {
          map.setCenter(loc);
          map.setZoom(12);
        }
      });
    }
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [status]);

  // ── Zone overlays ───────────────────────────────────────────────────────
  React.useEffect(() => {
    const map = mapRef.current;
    if (status !== "ready" || !map) return;
    zonePolysRef.current.forEach((p) => p.setMap(null));
    zonePolysRef.current = [];
    for (const z of zones) {
      for (const path of geometryToPaths(z.geometry)) {
        zonePolysRef.current.push(
          new google.maps.Polygon({
            paths: path,
            map,
            clickable: false,
            fillColor: BRAND,
            fillOpacity: 0.06,
            strokeColor: BRAND,
            strokeOpacity: 0.5,
            strokeWeight: 1,
          })
        );
      }
    }
    return () => {
      zonePolysRef.current.forEach((p) => p.setMap(null));
      zonePolysRef.current = [];
    };
  }, [status, zones]);

  // ── Sync the marker to the current point (imperative only — no setState) ──
  React.useEffect(() => {
    const map = mapRef.current;
    if (status !== "ready" || !map) return;
    if (!hasPoint) {
      markerRef.current?.setMap(null);
      markerRef.current = null;
      return;
    }
    const pos = { lat: lat as number, lng: lng as number };
    if (!markerRef.current) {
      const marker = new google.maps.Marker({ position: pos, map, draggable: true });
      marker.addListener("dragend", () => {
        const p = marker.getPosition();
        if (p) onChangeRef.current(round(p.lat()), round(p.lng()));
      });
      markerRef.current = marker;
      map.panTo(pos);
      if ((map.getZoom() ?? 0) < 14) map.setZoom(15);
    } else {
      markerRef.current.setPosition(pos);
    }
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [status, lat, lng]);

  // ── Reverse geocode the point (debounced) via backend proxy ─────────────
  React.useEffect(() => {
    if (!hasPoint) return;
    let alive = true;
    const t = setTimeout(async () => {
      try {
        const r = await api.get<{ formatted: string }>("/geo/reverse", { lat: lat as number, lng: lng as number });
        if (!alive) return;
        setAddress(r.formatted || "");
        if (r.formatted) onAddrRef.current?.(r.formatted);
      } catch {
        /* proxy unavailable / no server key — silent */
      }
    }, 500);
    return () => {
      alive = false;
      clearTimeout(t);
    };
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [lat, lng]);

  // Search result → set the store point and recentre.
  const onSearchPick = React.useCallback((la: number, ln: number) => {
    onChangeRef.current(la, ln);
    const map = mapRef.current;
    if (map) {
      map.panTo({ lat: la, lng: ln });
      map.setZoom(16);
    }
  }, []);

  if (status !== "ready") {
    return <MapFallback status={status} height={height} />;
  }

  return (
    <div className="space-y-2">
      <MapPlacesSearch onPick={onSearchPick} />

      <div ref={divRef} className="overflow-hidden rounded-lg border" style={{ height, width: "100%" }} />

      <div className="flex flex-wrap items-center gap-x-4 gap-y-1 text-xs text-muted-foreground">
        <span>Click the map or drag the pin to set the exact location.</span>
        {hasPoint && !zoneHint && <span className="font-medium text-warning">⚠ Outside all service zones</span>}
        {zoneHint && <span className="font-medium text-primary">Inside zone: {zoneHint.name}</span>}
        {hasPoint && address && <span className="basis-full truncate">📍 {address}</span>}
      </div>
    </div>
  );
}

function round(n: number): number {
  return Math.round(n * 1e6) / 1e6;
}
