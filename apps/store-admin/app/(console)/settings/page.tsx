"use client";

import * as React from "react";
import { useQuery } from "@tanstack/react-query";
import { Clock, Loader2, Store } from "lucide-react";
import { api, useApiMutation } from "@/lib/api/hooks";
import { useStore } from "@/lib/store/store-context";
import { PageHeader } from "@/components/page-header";
import { ConfirmDialog } from "@/components/confirm-dialog";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import { Switch } from "@/components/ui/switch";
import { LoadingState } from "@/components/states";
import { inr } from "@/lib/utils";

interface Settings {
  store: {
    id: string; code: string; name: string; address: string; phone: string; status: string;
    // Operating window & capacity — the store's own trading controls. The
    // backend has accepted these all along; nothing in the UI ever sent them,
    // so a store slammed at 8pm had no way to stop taking orders.
    acceptingOrders: boolean;
    opensAt: string | null;
    closesAt: string | null;
    dailyOrderCapacity: number | null;
    isOpenNow: boolean;
    ordersToday: number;
  };
  platform: { gstRate: number; deliveryFee: number; freeDeliveryThreshold: number; creditDefaultLimit: number };
}

export default function SettingsPage() {
  const { hasPerm } = useStore();
  const canManage = hasPerm("settings.manage");
  const q = useQuery({ queryKey: ["store", "settings"], queryFn: () => api.get<Settings>("/store/settings") });

  const [form, setForm] = React.useState({ name: "", address: "", phone: "" });
  React.useEffect(() => {
    if (q.data) setForm({ name: q.data.store.name, address: q.data.store.address, phone: q.data.store.phone });
  }, [q.data]);

  const save = useApiMutation<void>(
    () => api.patch("/store/settings", form),
    { invalidate: [["store", "settings"], ["store", "me"]], successMessage: "Store settings saved" }
  );

  // Trading controls save independently of the profile form — pausing orders is
  // an emergency action and must not require filling in the profile fields.
  const saveTrading = useApiMutation<Record<string, unknown>>(
    (body) => api.patch("/store/settings", body),
    { invalidate: [["store", "settings"], ["store", "me"]], successMessage: "Trading settings saved" }
  );

  if (q.isLoading || !q.data) return <LoadingState />;
  const set = (k: keyof typeof form) => (e: React.ChangeEvent<HTMLInputElement>) => setForm((f) => ({ ...f, [k]: e.target.value }));

  return (
    <div className="space-y-5">
      <PageHeader title="Store Settings" description="Your store profile and the platform rules that apply to it." />

      <Card>
        <CardHeader><CardTitle className="flex items-center gap-2 text-sm"><Store className="size-4" /> Store profile</CardTitle></CardHeader>
        <CardContent className="space-y-3">
          <div className="grid gap-3 sm:grid-cols-2">
            <div className="space-y-1.5"><Label>Store name</Label><Input value={form.name} onChange={set("name")} disabled={!canManage} /></div>
            <div className="space-y-1.5"><Label>Phone</Label><Input value={form.phone} onChange={set("phone")} disabled={!canManage} /></div>
          </div>
          <div className="space-y-1.5"><Label>Address</Label><Input value={form.address} onChange={set("address")} disabled={!canManage} /></div>
          <div className="flex items-center gap-3 text-xs text-muted-foreground">
            <span>Code: <span className="font-mono">{q.data.store.code}</span></span>
            <span>Status: {q.data.store.status}</span>
          </div>
          {canManage && (
            <div className="flex justify-end">
              <Button onClick={() => save.mutate()} disabled={save.isPending}>
                {save.isPending && <Loader2 className="size-4 animate-spin" />} Save changes
              </Button>
            </div>
          )}
        </CardContent>
      </Card>

      <TradingCard store={q.data.store} canManage={canManage} onSave={saveTrading} />

      <Card>
        <CardHeader><CardTitle className="text-sm">Platform rules (set by VS Mart HQ)</CardTitle></CardHeader>
        <CardContent className="grid grid-cols-2 gap-4 sm:grid-cols-4">
          <Field label="GST rate" value={`${(q.data.platform.gstRate * 100).toFixed(0)}%`} />
          <Field label="Delivery fee" value={inr(q.data.platform.deliveryFee)} />
          <Field label="Free delivery over" value={inr(q.data.platform.freeDeliveryThreshold)} />
          <Field label="Default credit limit" value={inr(q.data.platform.creditDefaultLimit)} />
        </CardContent>
      </Card>
    </div>
  );
}

/**
 * The store's own trading controls: the pause switch, business hours and daily
 * capacity. `orders.services` genuinely blocks checkout on `store.is_open_now()`,
 * so this card is what stands between a slammed store and more orders arriving.
 */
function TradingCard({
  store, canManage, onSave,
}: {
  store: Settings["store"];
  canManage: boolean;
  onSave: ReturnType<typeof useApiMutation<Record<string, unknown>>>;
}) {
  const [opensAt, setOpensAt] = React.useState(store.opensAt ?? "");
  const [closesAt, setClosesAt] = React.useState(store.closesAt ?? "");
  const [capacity, setCapacity] = React.useState(
    store.dailyOrderCapacity == null ? "" : String(store.dailyOrderCapacity));
  const [confirmPause, setConfirmPause] = React.useState(false);

  React.useEffect(() => {
    setOpensAt(store.opensAt ?? "");
    setClosesAt(store.closesAt ?? "");
    setCapacity(store.dailyOrderCapacity == null ? "" : String(store.dailyOrderCapacity));
  }, [store.opensAt, store.closesAt, store.dailyOrderCapacity]);

  // Both times blank = always open. closes < opens = an overnight window.
  // Mirrors Store.is_open_now() so the hint can't contradict the backend.
  const alwaysOpen = !opensAt || !closesAt;
  const overnight = !alwaysOpen && closesAt < opensAt;

  const setAccepting = (next: boolean) =>
    onSave.mutate({ acceptingOrders: next });

  const saveHours = () =>
    onSave.mutate({
      opensAt: opensAt || null,
      closesAt: closesAt || null,
      dailyOrderCapacity: capacity.trim() === "" ? null : Number(capacity),
    });

  const capacityInvalid = capacity.trim() !== "" && (!Number.isFinite(Number(capacity)) || Number(capacity) < 0);

  return (
    <Card>
      <CardHeader>
        <CardTitle className="flex items-center gap-2 text-sm">
          <Clock className="size-4" /> Taking orders
        </CardTitle>
      </CardHeader>
      <CardContent className="space-y-4">
        <div className="flex flex-wrap items-center justify-between gap-3 rounded-lg border p-3">
          <div className="min-w-0">
            <div className="flex items-center gap-2">
              <span
                className={`inline-block size-2 shrink-0 rounded-full ${
                  store.isOpenNow ? "bg-emerald-500" : "bg-destructive"
                }`}
              />
              <p className="text-sm font-semibold">
                {store.isOpenNow ? "Open — accepting orders now" : "Closed — not accepting orders"}
              </p>
            </div>
            <p className="mt-0.5 text-xs text-muted-foreground">
              {store.ordersToday} order{store.ordersToday === 1 ? "" : "s"} today
              {store.dailyOrderCapacity != null && ` of ${store.dailyOrderCapacity} allowed`}
              {!store.acceptingOrders && " · paused by you"}
              {store.acceptingOrders && !store.isOpenNow && !alwaysOpen && " · outside business hours"}
              {store.status !== "active" && ` · store is ${store.status}`}
            </p>
          </div>
          <Switch
            checked={store.acceptingOrders}
            disabled={!canManage || onSave.isPending}
            onCheckedChange={(next) => (next ? setAccepting(true) : setConfirmPause(true))}
            aria-label="Accepting orders"
          />
        </div>

        <div className="grid gap-3 sm:grid-cols-3">
          <div className="space-y-1.5">
            <Label>Opens at</Label>
            <Input type="time" value={opensAt} onChange={(e) => setOpensAt(e.target.value)} disabled={!canManage} />
          </div>
          <div className="space-y-1.5">
            <Label>Closes at</Label>
            <Input type="time" value={closesAt} onChange={(e) => setClosesAt(e.target.value)} disabled={!canManage} />
          </div>
          <div className="space-y-1.5">
            <Label>Daily order limit</Label>
            <Input
              inputMode="numeric"
              placeholder="No limit"
              value={capacity}
              onChange={(e) => setCapacity(e.target.value)}
              disabled={!canManage}
            />
          </div>
        </div>

        <p className="text-xs text-muted-foreground">
          {alwaysOpen
            ? "Leave both times blank to stay open around the clock."
            : overnight
              ? `Overnight window — open ${opensAt} through ${closesAt} the next morning.`
              : `Customers can order between ${opensAt} and ${closesAt}.`}
          {" "}Leave the daily limit blank for no cap.
        </p>

        {canManage && (
          <div className="flex justify-end">
            <Button onClick={saveHours} disabled={onSave.isPending || capacityInvalid}>
              {onSave.isPending && <Loader2 className="size-4 animate-spin" />} Save hours
            </Button>
          </div>
        )}
      </CardContent>

      <ConfirmDialog
        open={confirmPause}
        onOpenChange={setConfirmPause}
        title="Stop taking orders?"
        description={
          "Customers won't be able to place new orders with your store until you turn this back on. " +
          "Orders already placed are unaffected — keep packing and delivering them as normal."
        }
        confirmLabel="Stop taking orders"
        destructive
        loading={onSave.isPending}
        onConfirm={() => { setAccepting(false); setConfirmPause(false); }}
      />
    </Card>
  );
}

function Field({ label, value }: { label: string; value: string }) {
  return (
    <div>
      <p className="text-xs uppercase tracking-wide text-muted-foreground">{label}</p>
      <p className="mt-0.5 text-lg font-semibold">{value}</p>
    </div>
  );
}
