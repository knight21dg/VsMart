"use client";

import { useQuery } from "@tanstack/react-query";
import { MapPin } from "lucide-react";
import { api } from "@/lib/api/client";
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from "@/components/ui/select";

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

/** Shared store + zone reference lists for filter dropdowns. */
export function useStoreZoneRefs() {
  const stores = useQuery({ queryKey: ["ref", "stores"], queryFn: () => api.get<NamedRef[]>("/admin/stores"), staleTime: 300_000 });
  const zones = useQuery({ queryKey: ["ref", "zones"], queryFn: () => api.get<NamedRef[]>("/admin/zones"), staleTime: 300_000 });
  return { stores: stores.data ?? [], zones: zones.data ?? [] };
}

/** Two-select store/zone filter. Values "" mean "all". */
export function StoreZoneFilter({
  store,
  zone,
  onStore,
  onZone,
}: {
  store: string;
  zone: string;
  onStore: (v: string) => void;
  onZone: (v: string) => void;
}) {
  const { stores, zones } = useStoreZoneRefs();
  return (
    <div className="flex flex-wrap gap-2">
      <Select value={store || "all"} onValueChange={(v) => onStore(v === "all" ? "" : v)}>
        <SelectTrigger className="h-9 w-[160px]"><SelectValue placeholder="All stores" /></SelectTrigger>
        <SelectContent>
          <SelectItem value="all">All stores</SelectItem>
          {stores.map((s) => <SelectItem key={s.id} value={s.id}>{s.name}</SelectItem>)}
        </SelectContent>
      </Select>
      <Select value={zone || "all"} onValueChange={(v) => onZone(v === "all" ? "" : v)}>
        <SelectTrigger className="h-9 w-[160px]"><SelectValue placeholder="All zones" /></SelectTrigger>
        <SelectContent>
          <SelectItem value="all">All zones</SelectItem>
          {zones.map((z) => <SelectItem key={z.id} value={z.id}>{z.name}</SelectItem>)}
        </SelectContent>
      </Select>
    </div>
  );
}
