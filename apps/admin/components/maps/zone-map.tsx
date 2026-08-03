"use client";

import * as React from "react";
import { Check, Pencil, Trash2, Undo2 } from "lucide-react";
import { Button } from "@/components/ui/button";
import { currentLocationOrDefault, DEFAULT_CENTER, useGoogleMaps } from "@/lib/maps/loader";
import {
  boundsOfGeometry,
  geometryToPaths,
  pathToGeometry,
  type GeoJSONGeometry,
} from "@/lib/maps/geojson";
import { MapFallback } from "./map-fallback";
import { MapPlacesSearch } from "./map-places-search";

export type { GeoJSONGeometry };

interface StorePoint {
  id: string;
  name: string;
  lat: number;
  lng: number;
}

const BRAND = "#006d77";

const POLY_STYLE = {
  fillColor: BRAND,
  fillOpacity: 0.14,
  strokeColor: BRAND,
  strokeWeight: 2,
} as const;

/**
 * Google Maps polygon editor for a service zone (Google removed the DrawingManager in
 * Maps JS v3.65, so drawing is done manually). Click "Draw" — the cursor becomes a
 * crosshair and map-panning is suspended so every click drops a vertex reliably. Add
 * 3+ points, click "Finish", then drag vertices to fine-tune, or clear and redraw. The
 * closed ring is emitted as GeoJSON; store pins are shown for context.
 */
export function ZoneMap({
  value,
  onChange,
  stores = [],
  editable = true,
  height = 380,
}: {
  value?: GeoJSONGeometry | null;
  onChange?: (geom: GeoJSONGeometry | null) => void;
  stores?: StorePoint[];
  editable?: boolean;
  height?: number;
}) {
  const status = useGoogleMaps();
  const divRef = React.useRef<HTMLDivElement>(null);
  const mapRef = React.useRef<google.maps.Map | null>(null);
  const polyRef = React.useRef<google.maps.Polygon | null>(null);
  const pathRef = React.useRef<google.maps.MVCArray<google.maps.LatLng> | null>(null);
  const clickRef = React.useRef<google.maps.MapsEventListener | null>(null);
  const markersRef = React.useRef<google.maps.Marker[]>([]);
  const searchMarkerRef = React.useRef<google.maps.Marker | null>(null);
  const onChangeRef = React.useRef(onChange);
  React.useEffect(() => {
    onChangeRef.current = onChange;
  });

  const [hasPolygon, setHasPolygon] = React.useState(!!value);
  const [drawing, setDrawing] = React.useState(false);
  const [vertexCount, setVertexCount] = React.useState(0);

  const emit = React.useCallback(() => {
    const poly = polyRef.current;
    if (!poly) {
      onChangeRef.current?.(null);
      return;
    }
    const ring = poly.getPath().getArray().map((p) => ({ lat: p.lat(), lng: p.lng() }));
    onChangeRef.current?.(pathToGeometry(ring));
  }, []);

  const bindEditListeners = React.useCallback(
    (poly: google.maps.Polygon) => {
      const path = poly.getPath();
      path.addListener("set_at", emit);
      path.addListener("insert_at", emit);
      path.addListener("remove_at", emit);
    },
    [emit]
  );

  // Suspend map panning + show a crosshair so clicks reliably add points (not pan).
  const setDrawMode = React.useCallback((on: boolean) => {
    mapRef.current?.setOptions(
      on
        ? { draggable: false, draggableCursor: "crosshair", disableDoubleClickZoom: true }
        : { draggable: true, draggableCursor: null, disableDoubleClickZoom: false }
    );
  }, []);

  const stopDrawing = React.useCallback(() => {
    clickRef.current?.remove();
    clickRef.current = null;
    setDrawMode(false);
    setDrawing(false);
  }, [setDrawMode]);

  const finishDrawing = React.useCallback(() => {
    const poly = polyRef.current;
    if (!poly || poly.getPath().getLength() < 3) return;
    stopDrawing();
    poly.setEditable(editable);
    poly.setOptions({ clickable: true });
    bindEditListeners(poly);
    setHasPolygon(true);
    emit();
  }, [bindEditListeners, editable, emit, stopDrawing]);

  const startDrawing = React.useCallback(() => {
    const map = mapRef.current;
    if (!map) return;
    polyRef.current?.setMap(null);
    setHasPolygon(false);
    setVertexCount(0);

    // Create the polygon then give it ONE empty ring via setPath([]) — passing a raw
    // MVCArray as `paths` makes Google treat it as a collection of rings, so pushing a
    // LatLng throws "a.forEach is not a function". getPath() returns that single ring;
    // we push LatLngs into it. clickable:false so clicks reach the map.
    const poly = new google.maps.Polygon({
      ...POLY_STYLE,
      editable: true,
      clickable: false,
      map,
    });
    poly.setPath([]);
    polyRef.current = poly;
    const path = poly.getPath();
    pathRef.current = path;
    setDrawMode(true);
    setDrawing(true);
    clickRef.current = map.addListener("click", (e: google.maps.MapMouseEvent) => {
      if (!e.latLng) return;
      path.push(e.latLng);
      setVertexCount(path.getLength());
    });
  }, [setDrawMode]);

  const undoVertex = React.useCallback(() => {
    const path = pathRef.current;
    if (!path || path.getLength() === 0) return;
    path.removeAt(path.getLength() - 1);
    setVertexCount(path.getLength());
  }, []);

  const clearPolygon = React.useCallback(() => {
    stopDrawing();
    polyRef.current?.setMap(null);
    polyRef.current = null;
    setHasPolygon(false);
    setVertexCount(0);
    emit();
    startDrawing();
  }, [emit, startDrawing, stopDrawing]);

  // ── Initialise map ──────────────────────────────────────────────────────
  React.useEffect(() => {
    if (status !== "ready" || !divRef.current || mapRef.current) return;
    const map = new google.maps.Map(divRef.current, {
      center: DEFAULT_CENTER,
      zoom: 11,
      mapTypeControl: false,
      streetViewControl: false,
      fullscreenControl: false,
      clickableIcons: false,
    });
    mapRef.current = map;

    if (value) {
      const paths = geometryToPaths(value);
      if (paths[0]) {
        const poly = new google.maps.Polygon({ ...POLY_STYLE, editable, map, paths: paths[0] });
        polyRef.current = poly;
        bindEditListeners(poly);
      }
      const b = boundsOfGeometry(value);
      if (b) map.fitBounds(b, 24);
    } else {
      // No existing polygon → centre on the operator's GPS location (Kakinada fallback).
      currentLocationOrDefault().then((loc) => {
        if (mapRef.current === map) {
          map.setCenter(loc);
          map.setZoom(12);
        }
      });
    }
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [status]);

  // ── Store pins ──────────────────────────────────────────────────────────
  React.useEffect(() => {
    const map = mapRef.current;
    if (status !== "ready" || !map) return;
    markersRef.current.forEach((m) => m.setMap(null));
    markersRef.current = stores.map(
      (s) =>
        new google.maps.Marker({
          position: { lat: s.lat, lng: s.lng },
          map,
          title: s.name,
          clickable: false,
          icon: {
            path: google.maps.SymbolPath.CIRCLE,
            scale: 6,
            fillColor: BRAND,
            fillOpacity: 0.9,
            strokeColor: "#fff",
            strokeWeight: 2,
          },
        })
    );
    return () => markersRef.current.forEach((m) => m.setMap(null));
  }, [status, stores]);

  // Search result → recentre + drop a non-clickable locator pin.
  const onSearchPick = React.useCallback((lat: number, lng: number) => {
    const map = mapRef.current;
    if (!map) return;
    map.panTo({ lat, lng });
    map.setZoom(13);
    searchMarkerRef.current?.setMap(null);
    searchMarkerRef.current = new google.maps.Marker({
      position: { lat, lng },
      map,
      clickable: false,
      icon: {
        path: google.maps.SymbolPath.CIRCLE,
        scale: 5,
        fillColor: "#c1121f",
        fillOpacity: 0.9,
        strokeColor: "#fff",
        strokeWeight: 2,
      },
    });
  }, []);

  if (status !== "ready") {
    return <MapFallback status={status} height={height} />;
  }

  return (
    <div className="space-y-2">
      <MapPlacesSearch onPick={onSearchPick} placeholder="Search an area to jump to before drawing…" />
      {editable && (
        <div className="flex flex-wrap items-center gap-2">
          {drawing ? (
            <>
              <Button type="button" size="sm" onClick={finishDrawing} disabled={vertexCount < 3}>
                <Check className="size-4" /> Finish ({vertexCount})
              </Button>
              <Button type="button" size="sm" variant="outline" onClick={undoVertex} disabled={vertexCount === 0}>
                <Undo2 className="size-4" /> Undo point
              </Button>
              <span className="text-xs font-medium text-primary">
                Click on the map to drop points (need 3+). Panning is paused while drawing.
              </span>
            </>
          ) : !hasPolygon ? (
            <Button type="button" size="sm" onClick={startDrawing}>
              <Pencil className="size-4" /> Draw service area
            </Button>
          ) : (
            <>
              <Button type="button" size="sm" variant="outline" onClick={clearPolygon}>
                <Trash2 className="size-4" /> Clear &amp; redraw
              </Button>
              <span className="text-xs text-muted-foreground">Drag the vertices to fine-tune.</span>
            </>
          )}
        </div>
      )}
      <div ref={divRef} className="overflow-hidden rounded-lg border" style={{ height, width: "100%" }} />
    </div>
  );
}
