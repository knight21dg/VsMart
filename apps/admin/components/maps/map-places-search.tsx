"use client";

import * as React from "react";
import { Loader2, MapPin, Search, X } from "lucide-react";
import { api } from "@/lib/api/client";
import { Input } from "@/components/ui/input";

interface Prediction {
  placeId: string;
  primary: string;
  secondary: string;
  description: string;
}

/**
 * Place-search box for the admin maps. Queries Google Places through the backend
 * `/geo/places/*` proxy (server key) and emits the chosen place's coordinates via
 * `onPick` — the parent decides whether to drop a pin, pan the map, or both. A
 * stable session token pairs the autocomplete + detail calls for Google billing.
 */
export function MapPlacesSearch({
  onPick,
  placeholder = "Search a place, landmark or address…",
  className,
}: {
  onPick: (lat: number, lng: number) => void;
  placeholder?: string;
  className?: string;
}) {
  const onPickRef = React.useRef(onPick);
  React.useEffect(() => {
    onPickRef.current = onPick;
  });
  const sessionRef = React.useRef<string>("");

  const [query, setQuery] = React.useState("");
  const [predictions, setPredictions] = React.useState<Prediction[]>([]);
  const [searching, setSearching] = React.useState(false);

  React.useEffect(() => {
    const q = query.trim();
    if (q.length < 2) return; // dropdown hidden by the render gate below
    if (!sessionRef.current) sessionRef.current = randomToken();
    let alive = true;
    const t = setTimeout(async () => {
      setSearching(true);
      try {
        const r = await api.get<{ predictions: Prediction[] }>("/geo/places/autocomplete", {
          q,
          session: sessionRef.current,
        });
        if (alive) setPredictions(r.predictions || []);
      } catch {
        if (alive) setPredictions([]);
      } finally {
        if (alive) setSearching(false);
      }
    }, 350);
    return () => {
      alive = false;
      clearTimeout(t);
    };
  }, [query]);

  async function pick(p: Prediction) {
    setQuery(p.primary);
    setPredictions([]);
    try {
      const d = await api.get<{ lat: number | null; lng: number | null }>("/geo/places/detail", {
        placeId: p.placeId,
        session: sessionRef.current,
      });
      sessionRef.current = "";
      if (d.lat != null && d.lng != null) {
        onPickRef.current(round(d.lat), round(d.lng));
      }
    } catch {
      /* ignore */
    }
  }

  const showDropdown = query.trim().length >= 2 && predictions.length > 0;

  return (
    <div className={`relative ${className ?? ""}`}>
      <div className="relative">
        <Search className="pointer-events-none absolute left-3 top-1/2 size-4 -translate-y-1/2 text-muted-foreground" />
        <Input
          value={query}
          onChange={(e) => setQuery(e.target.value)}
          placeholder={placeholder}
          className="pl-9 pr-9"
        />
        {searching ? (
          <Loader2 className="absolute right-3 top-1/2 size-4 -translate-y-1/2 animate-spin text-muted-foreground" />
        ) : query ? (
          <button
            type="button"
            onClick={() => {
              setQuery("");
              setPredictions([]);
            }}
            className="absolute right-2 top-1/2 -translate-y-1/2 rounded p-1 text-muted-foreground hover:text-foreground"
            aria-label="Clear search"
          >
            <X className="size-4" />
          </button>
        ) : null}
      </div>
      {showDropdown && (
        <ul className="absolute z-20 mt-1 max-h-64 w-full overflow-auto rounded-md border bg-popover shadow-md">
          {predictions.map((p) => (
            <li key={p.placeId}>
              <button
                type="button"
                onClick={() => pick(p)}
                className="flex w-full items-start gap-2 px-3 py-2 text-left text-sm hover:bg-accent"
              >
                <MapPin className="mt-0.5 size-3.5 shrink-0 text-muted-foreground" />
                <span>
                  <span className="font-medium">{p.primary}</span>
                  {p.secondary ? <span className="block text-xs text-muted-foreground">{p.secondary}</span> : null}
                </span>
              </button>
            </li>
          ))}
        </ul>
      )}
    </div>
  );
}

function round(n: number): number {
  return Math.round(n * 1e6) / 1e6;
}

function randomToken(): string {
  try {
    return crypto.randomUUID();
  } catch {
    return `s-${Date.now()}-${Math.floor(Math.random() * 1e6)}`;
  }
}
