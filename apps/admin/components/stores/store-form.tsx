"use client";

import * as React from "react";
import { useRouter } from "next/navigation";
import { useQuery } from "@tanstack/react-query";
import { ArrowLeft, Loader2, MapPin, Store as StoreIcon } from "lucide-react";
import { api } from "@/lib/api/client";
import { useApiMutation } from "@/lib/api/hooks";
import { PageHeader } from "@/components/page-header";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import { Switch } from "@/components/ui/switch";
import { Card, CardContent } from "@/components/ui/card";
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from "@/components/ui/select";
import { LoadingState, ErrorState } from "@/components/states";
import { StoreLocationMap } from "@/components/maps/store-location-map";
import type { GeoJSONGeometry } from "@/lib/maps/geojson";

interface Store {
  id: string;
  code: string;
  name: string;
  address: string;
  latitude: number | null;
  longitude: number | null;
  phone: string;
  gstin: string;
  status: string;
  acceptingOrders: boolean;
  opensAt: string | null;
  closesAt: string | null;
  dailyOrderCapacity: number | null;
}
interface ZoneLite { id: string; name: string; store: number | null; polygonGeojson: GeoJSONGeometry | null }

// `zone` is not a Store field — it's the serving zone this store is bound to, sent
// alongside the store body and linked server-side.
type StoreForm = Partial<Store> & { zone?: string | null };

export function StoreFormPage({ storeId }: { storeId?: string }) {
  const router = useRouter();
  const editing = !!storeId;

  const storeQuery = useQuery({
    queryKey: ["admin", "store", storeId],
    queryFn: () => api.get<Store>(`/admin/stores/${storeId}`),
    enabled: editing,
  });
  const zones = useQuery({ queryKey: ["admin", "zones"], queryFn: () => api.getPaged<ZoneLite>("/admin/zones") });

  const [form, setForm] = React.useState<StoreForm>({ status: "active", acceptingOrders: true });
  const [hydratedId, setHydratedId] = React.useState<string | null>(null);

  // Seed the form from the fetched store once (React's "adjust state during render"
  // pattern — resets when the target store changes, no effect needed).
  if (editing && storeQuery.data && hydratedId !== storeId) {
    setForm(storeQuery.data);
    setHydratedId(storeId ?? null);
  }

  // The zone currently routing to this store (a store may serve several; show the first).
  const linkedZoneId = editing
    ? (zones.data?.rows ?? []).find((z) => z.store != null && String(z.store) === storeId)?.id
    : undefined;
  const selectedZone = form.zone !== undefined ? form.zone : (linkedZoneId ?? null);

  const save = useApiMutation(
    (body: StoreForm) => (editing ? api.patch(`/admin/stores/${storeId}`, body) : api.post("/admin/stores", body)),
    {
      invalidate: [["admin", "stores"]],
      successMessage: editing ? "Store updated." : "Store created.",
      onDone: () => router.push("/stores"),
    }
  );

  function submit() {
    save.mutate({
      code: form.code,
      name: form.name,
      address: form.address ?? "",
      phone: form.phone ?? "",
      gstin: form.gstin ?? "",
      status: form.status ?? "active",
      latitude: num(form.latitude),
      longitude: num(form.longitude),
      acceptingOrders: form.acceptingOrders ?? true,
      opensAt: form.opensAt || null,
      closesAt: form.closesAt || null,
      dailyOrderCapacity: num(form.dailyOrderCapacity),
      zone: selectedZone,
    });
  }

  const zoneShapes = (zones.data?.rows ?? [])
    .filter((z) => z.polygonGeojson != null)
    .map((z) => ({ id: z.id, name: z.name, geometry: z.polygonGeojson as GeoJSONGeometry }));

  if (editing && storeQuery.isLoading) return <LoadingState label="Loading store…" />;
  if (editing && storeQuery.isError)
    return <ErrorState message="Failed to load store." onRetry={() => storeQuery.refetch()} />;

  return (
    <div className="space-y-6">
      <PageHeader
        title={editing ? `Edit Store${form.name ? ` — ${form.name}` : ""}` : "New Store"}
        description="Set the exact location, store details and operating window."
        actions={
          <div className="flex items-center gap-2">
            <Button variant="outline" onClick={() => router.push("/stores")}>
              <ArrowLeft className="size-4" /> Back
            </Button>
            <Button onClick={submit} disabled={save.isPending || !form.name || !form.code}>
              {save.isPending && <Loader2 className="size-4 animate-spin" />} {editing ? "Save changes" : "Create store"}
            </Button>
          </div>
        }
      />

      <div className="grid gap-6 lg:grid-cols-12">
        {/* Details */}
        <Card className="lg:col-span-5">
          <CardContent className="space-y-4 pt-6">
            <p className="flex items-center gap-1.5 text-sm font-semibold"><StoreIcon className="size-4" /> Store details</p>
            <div className="grid grid-cols-2 gap-3">
              <Field label="Name"><Input value={form.name ?? ""} onChange={(e) => setForm({ ...form, name: e.target.value })} /></Field>
              <Field label="Code"><Input value={form.code ?? ""} onChange={(e) => setForm({ ...form, code: e.target.value })} /></Field>
              <Field label="Phone"><Input value={form.phone ?? ""} onChange={(e) => setForm({ ...form, phone: e.target.value })} /></Field>
              <Field label="GSTIN"><Input value={form.gstin ?? ""} onChange={(e) => setForm({ ...form, gstin: e.target.value })} placeholder="29ABCDE1234F1Z5" /></Field>
            </div>
            <Field label="Address"><Input value={form.address ?? ""} onChange={(e) => setForm({ ...form, address: e.target.value })} placeholder="Auto-fills from the map pin" /></Field>

            <Field label="Serving zone">
              <Select value={selectedZone ?? "none"} onValueChange={(v) => setForm({ ...form, zone: v === "none" ? null : v })}>
                <SelectTrigger><SelectValue placeholder="Select the zone this store serves" /></SelectTrigger>
                <SelectContent>
                  <SelectItem value="none">Unassigned</SelectItem>
                  {(zones.data?.rows ?? []).map((z) => {
                    const takenByOther = z.store != null && String(z.store) !== storeId;
                    return (
                      <SelectItem key={z.id} value={z.id}>
                        {z.name}{takenByOther ? " · already assigned" : ""}
                      </SelectItem>
                    );
                  })}
                </SelectContent>
              </Select>
            </Field>
            {(zones.data?.rows ?? []).length === 0 && (
              <p className="text-xs text-warning">No zones yet — create a zone first, then it will appear here.</p>
            )}

            <div className="grid grid-cols-2 gap-3 pt-2">
              <Field label="Status">
                <Select value={form.status ?? "active"} onValueChange={(v) => setForm({ ...form, status: v })}>
                  <SelectTrigger><SelectValue /></SelectTrigger>
                  <SelectContent>
                    <SelectItem value="active">Active</SelectItem>
                    <SelectItem value="inactive">Inactive</SelectItem>
                  </SelectContent>
                </Select>
              </Field>
              <Field label="Opens at"><Input type="time" value={form.opensAt ?? ""} onChange={(e) => setForm({ ...form, opensAt: e.target.value })} /></Field>
              <Field label="Closes at"><Input type="time" value={form.closesAt ?? ""} onChange={(e) => setForm({ ...form, closesAt: e.target.value })} /></Field>
              <Field label="Daily order capacity">
                <Input type="number" min={0} value={form.dailyOrderCapacity ?? ""} placeholder="Unlimited"
                  onChange={(e) => setForm({ ...form, dailyOrderCapacity: e.target.value as unknown as number })} />
              </Field>
              <div className="flex items-end pb-1">
                <label className="flex items-center gap-2 text-sm">
                  <Switch checked={form.acceptingOrders ?? true} onCheckedChange={(v) => setForm({ ...form, acceptingOrders: v })} />
                  Accepting orders
                </label>
              </div>
            </div>
          </CardContent>
        </Card>

        {/* Location */}
        <Card className="lg:col-span-7">
          <CardContent className="space-y-3 pt-6">
            <p className="flex items-center gap-1.5 text-sm font-semibold"><MapPin className="size-4" /> Exact store location</p>
            <StoreLocationMap
              lat={num(form.latitude)}
              lng={num(form.longitude)}
              onChange={(lat, lng) => setForm((f) => ({ ...f, latitude: lat, longitude: lng }))}
              onResolvedAddress={(addr) => setForm((f) => (f.address ? f : { ...f, address: addr }))}
              zones={zoneShapes}
              height={440}
            />
            <div className="grid grid-cols-2 gap-3">
              <Field label="Latitude"><Input type="number" value={form.latitude ?? ""} onChange={(e) => setForm({ ...form, latitude: e.target.value as unknown as number })} /></Field>
              <Field label="Longitude"><Input type="number" value={form.longitude ?? ""} onChange={(e) => setForm({ ...form, longitude: e.target.value as unknown as number })} /></Field>
            </div>
          </CardContent>
        </Card>
      </div>
    </div>
  );
}

function num(v: unknown): number | null {
  if (v === "" || v == null) return null;
  const n = Number(v);
  return Number.isNaN(n) ? null : n;
}

function Field({ label, children }: { label: string; children: React.ReactNode }) {
  return (
    <div className="space-y-1.5">
      <Label>{label}</Label>
      {children}
    </div>
  );
}
