/**
 * Conversions between Google Maps polygon geometry and the GeoJSON that the
 * serviceability backend stores (`Zone.polygon_geojson`). GeoJSON coordinates are
 * `[lng, lat]`; Google Maps uses `{ lat, lng }`.
 */

export type GeoJSONGeometry = { type: string; coordinates: unknown };

type Ring = [number, number][]; // [lng, lat] pairs

/** Outer ring(s) of a Polygon / MultiPolygon as Google LatLng literals — one entry
 *  per polygon (holes ignored; service zones are simple polygons). */
export function geometryToPaths(geom: GeoJSONGeometry | null | undefined): google.maps.LatLngLiteral[][] {
  if (!geom) return [];
  const paths: google.maps.LatLngLiteral[][] = [];
  const pushRing = (ring: Ring) => {
    const pts = ring
      .filter((c) => Array.isArray(c) && c.length >= 2)
      .map((c) => ({ lat: c[1], lng: c[0] }));
    if (pts.length) paths.push(pts);
  };
  if (geom.type === "Polygon") {
    const rings = geom.coordinates as Ring[];
    if (rings?.[0]) pushRing(rings[0]);
  } else if (geom.type === "MultiPolygon") {
    const polys = geom.coordinates as Ring[][];
    for (const poly of polys ?? []) if (poly?.[0]) pushRing(poly[0]);
  }
  return paths;
}

/** A single Google polygon path -> a closed GeoJSON Polygon geometry. */
export function pathToGeometry(path: google.maps.LatLngLiteral[]): GeoJSONGeometry | null {
  if (!path || path.length < 3) return null;
  const ring: Ring = path.map((p) => [round(p.lng), round(p.lat)]);
  const [first] = ring;
  const last = ring[ring.length - 1];
  if (first[0] !== last[0] || first[1] !== last[1]) ring.push([first[0], first[1]]);
  return { type: "Polygon", coordinates: [ring] };
}

/** Bounds spanning every ring of a geometry, for `map.fitBounds`. */
export function boundsOfGeometry(geom: GeoJSONGeometry | null | undefined): google.maps.LatLngBounds | null {
  const paths = geometryToPaths(geom);
  if (!paths.length) return null;
  const bounds = new google.maps.LatLngBounds();
  for (const ring of paths) for (const p of ring) bounds.extend(p);
  return bounds.isEmpty() ? null : bounds;
}

/** Pure ray-casting containment test against a GeoJSON Polygon / MultiPolygon outer
 *  ring(s). Lets callers derive "which zone is this point in?" during render without
 *  the Maps geometry library or imperative refs. */
export function pointInGeometry(lat: number, lng: number, geom: GeoJSONGeometry | null | undefined): boolean {
  for (const ring of geometryToPaths(geom)) {
    if (pointInRing(lat, lng, ring)) return true;
  }
  return false;
}

function pointInRing(lat: number, lng: number, ring: google.maps.LatLngLiteral[]): boolean {
  let inside = false;
  for (let i = 0, j = ring.length - 1; i < ring.length; j = i++) {
    const xi = ring[i].lng, yi = ring[i].lat;
    const xj = ring[j].lng, yj = ring[j].lat;
    const intersect = yi > lat !== yj > lat && lng < ((xj - xi) * (lat - yi)) / (yj - yi) + xi;
    if (intersect) inside = !inside;
  }
  return inside;
}

function round(n: number): number {
  return Math.round(n * 1e6) / 1e6;
}
