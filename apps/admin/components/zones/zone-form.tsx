"use client";

import * as React from "react";
import { useRouter } from "next/navigation";
import { useQuery } from "@tanstack/react-query";
import { ArrowLeft, Loader2, Map as MapIcon } from "lucide-react";
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
import { ZoneMap, type GeoJSONGeometry } from "@/components/maps/zone-map";

interface Zone {
  id: string;
  name: string;
  code: string;
  polygonGeojson: GeoJSONGeometry | null;
  radiusKm: number | null;
  store: number | null;
  storeName: string | null;
  isActive: boolean;
  creditEnabled: boolean;
  estimatedDeliveryMinutes: number | null;
  priority: number | null;
  deliveryFee: number | null;
  freeDeliveryThreshold: number | null;
  minOrder: number | null;
}
interface StoreLite { id: string; name: string; latitude: number | null; longitude: number | null }

type ZoneForm = Partial<Zone>;

export function ZoneFormPage({ zoneId }: { zoneId?: string }) {
  const router = useRouter();
  const editing = !!zoneId;

  const zoneQuery = useQuery({
    queryKey: ["admin", "zone", zoneId],
    queryFn: () => api.get<Zone>(`/admin/zones/${zoneId}`),
    enabled: editing,
  });
  const stores = useQuery({ queryKey: ["admin", "stores"], queryFn: () => api.getPaged<StoreLite>("/admin/stores") });

  const [form, setForm] = React.useState<ZoneForm>({
    isActive: true,
    creditEnabled: true,
    priority: 10,
    estimatedDeliveryMinutes: 20,
  });
  const [polygon, setPolygon] = React.useState<GeoJSONGeometry | null>(null);
  const [hydratedId, setHydratedId] = React.useState<string | null>(null);

  // Seed the form from the fetched zone once (React's "adjust state during render"
  // pattern — resets when the target zone changes, no effect needed).
  if (editing && zoneQuery.data && hydratedId !== zoneId) {
    setForm(zoneQuery.data);
    setPolygon(zoneQuery.data.polygonGeojson ?? null);
    setHydratedId(zoneId ?? null);
  }

  const save = useApiMutation(
    (body: ZoneForm & { polygonGeojson: GeoJSONGeometry | null }) =>
      editing ? api.patch(`/admin/zones/${zoneId}`, body) : api.post("/admin/zones", body),
    {
      invalidate: [["admin", "zones"]],
      successMessage: editing ? "Zone updated." : "Zone created.",
      onDone: () => router.push("/zones"),
    }
  );

  function submit() {
    save.mutate({
      name: form.name,
      code: form.code,
      store: form.store != null && String(form.store) !== "" ? Number(form.store) : null,
      isActive: form.isActive ?? true,
      creditEnabled: form.creditEnabled ?? false,
      deliveryFee: num(form.deliveryFee),
      freeDeliveryThreshold: num(form.freeDeliveryThreshold),
      minOrder: num(form.minOrder),
      estimatedDeliveryMinutes: num(form.estimatedDeliveryMinutes),
      priority: num(form.priority),
      radiusKm: num(form.radiusKm),
      polygonGeojson: polygon,
    });
  }

  const storePoints = (stores.data?.rows ?? [])
    .filter((s) => s.latitude != null && s.longitude != null)
    .map((s) => ({ id: s.id, name: s.name, lat: Number(s.latitude), lng: Number(s.longitude) }));

  if (editing && zoneQuery.isLoading) return <LoadingState label="Loading zone…" />;
  if (editing && zoneQuery.isError)
    return <ErrorState message="Failed to load zone." onRetry={() => zoneQuery.refetch()} />;

  return (
    <div className="space-y-6">
      <PageHeader
        title={editing ? `Edit Zone${form.name ? ` — ${form.name}` : ""}` : "New Zone"}
        description="Draw the serviceable area, assign a store, and set delivery rules."
        actions={
          <div className="flex items-center gap-2">
            <Button variant="outline" onClick={() => router.push("/zones")}>
              <ArrowLeft className="size-4" /> Back
            </Button>
            <Button onClick={submit} disabled={save.isPending || !form.name || !form.code}>
              {save.isPending && <Loader2 className="size-4 animate-spin" />} {editing ? "Save changes" : "Create zone"}
            </Button>
          </div>
        }
      />

      <div className="grid gap-6 lg:grid-cols-12">
        {/* Fields */}
        <Card className="lg:col-span-5">
          <CardContent className="space-y-4 pt-6">
            <div className="grid grid-cols-2 gap-3">
              <Field label="Name"><Input value={form.name ?? ""} onChange={(e) => setForm({ ...form, name: e.target.value })} /></Field>
              <Field label="Code"><Input value={form.code ?? ""} onChange={(e) => setForm({ ...form, code: e.target.value })} /></Field>
            </div>
            <Field label="Assigned store">
              <Select value={form.store != null ? String(form.store) : "none"} onValueChange={(v) => setForm({ ...form, store: v === "none" ? null : Number(v) })}>
                <SelectTrigger><SelectValue placeholder="None" /></SelectTrigger>
                <SelectContent>
                  <SelectItem value="none">None</SelectItem>
                  {(stores.data?.rows ?? []).map((s) => <SelectItem key={s.id} value={s.id}>{s.name}</SelectItem>)}
                </SelectContent>
              </Select>
            </Field>
            <div className="grid grid-cols-2 gap-3">
              <Field label="Delivery fee (₹)"><Input type="number" value={form.deliveryFee ?? ""} onChange={(e) => setForm({ ...form, deliveryFee: e.target.value as unknown as number })} /></Field>
              <Field label="Free delivery ≥ (₹)"><Input type="number" value={form.freeDeliveryThreshold ?? ""} onChange={(e) => setForm({ ...form, freeDeliveryThreshold: e.target.value as unknown as number })} /></Field>
              <Field label="Min order (₹)"><Input type="number" value={form.minOrder ?? ""} onChange={(e) => setForm({ ...form, minOrder: e.target.value as unknown as number })} /></Field>
              <Field label="ETA (min)"><Input type="number" value={form.estimatedDeliveryMinutes ?? ""} onChange={(e) => setForm({ ...form, estimatedDeliveryMinutes: e.target.value as unknown as number })} /></Field>
              <Field label="Priority"><Input type="number" value={form.priority ?? ""} onChange={(e) => setForm({ ...form, priority: e.target.value as unknown as number })} /></Field>
              <Field label="Radius fallback (km)"><Input type="number" value={form.radiusKm ?? ""} onChange={(e) => setForm({ ...form, radiusKm: e.target.value as unknown as number })} /></Field>
            </div>
            <div className="flex items-center gap-6 pt-1">
              <label className="flex items-center gap-2 text-sm">
                <Switch checked={form.isActive ?? true} onCheckedChange={(v) => setForm({ ...form, isActive: v })} /> Active
              </label>
              <label className="flex items-center gap-2 text-sm">
                <Switch checked={form.creditEnabled ?? false} onCheckedChange={(v) => setForm({ ...form, creditEnabled: v })} /> Credit enabled
              </label>
            </div>
          </CardContent>
        </Card>

        {/* Map */}
        <Card className="lg:col-span-7">
          <CardContent className="space-y-2 pt-6">
            <Label className="flex items-center gap-1.5"><MapIcon className="size-4" /> Service area polygon</Label>
            <ZoneMap value={polygon} onChange={setPolygon} stores={storePoints} height={520} />
            <p className="text-xs text-muted-foreground">{polygon ? "Polygon set ✓" : "No polygon yet — draw the service area."}</p>
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
