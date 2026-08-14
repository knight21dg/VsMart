"use client";

import { MapPin } from "lucide-react";

export interface NamedRef {
  id: string;
  name: string;
}

/** Compact "where is this from" cell: store (bold) + zone (muted). */
export function StoreZone({ store, zone }: { store?: string | null; zone?: string | null }) {
  if (!store && !zone) return <span className="text-muted-foreground">—</span>;
  return (
    <span className="flex items-start gap-1.5">
      <MapPin className="mt-0.5 size-3.5 shrink-0 text-muted-foreground" />
      <span className="leading-tight">
        <span className="block text-sm">{store || "Unassigned"}</span>
        <span className="block text-xs text-muted-foreground">{zone || "—"}</span>
      </span>
    </span>
  );
}

/*
 * `useStoreZoneRefs` / `StoreZoneFilter` used to live here: two dropdowns fed by
 * `/admin/stores` and `/admin/zones`. Nothing ever rendered them, which is the
 * only reason it never caused an incident — a store employee is not an admin, so
 * both calls answer 403 and both dropdowns would have come up permanently empty.
 *
 * They are gone rather than repaired because the idea itself is wrong here: this
 * panel serves ONE store, so a "which store?" filter either shows a single fixed
 * value or lists every store on the platform inside one store's console — the
 * cross-store leak this codebase has already had to fix four times. A page that
 * needs the current store reads it from `/store/me`, which is scoped by the
 * caller's own membership and cannot leak.
 */
