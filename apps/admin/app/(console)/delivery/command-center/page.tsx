"use client";

import * as React from "react";
import dynamic from "next/dynamic";
import Link from "next/link";
import { useQuery } from "@tanstack/react-query";
import { api } from "@/lib/api/client";
import { useDeliverySocket } from "@/lib/realtime/use-delivery-socket";
import { PageHeader } from "@/components/page-header";
import { StatCard } from "@/components/stat-card";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";
import { Button } from "@/components/ui/button";
import { StatusBadge } from "@/components/status-badge";
import type { Rider } from "@/components/maps/fleet-map";

const TERMINAL = new Set([
  "delivered",
  "failed",
  "returned_to_store",
  "reassigned",
  "cancelled",
  "rejected",
]);

const FleetMap = dynamic(() => import("@/components/maps/fleet-map").then((m) => m.FleetMap), {
  ssr: false,
  loading: () => (
    <div className="grid h-full place-items-center text-sm text-muted-foreground">
      Loading live map…
    </div>
  ),
});

interface CommandCenter {
  kpis: {
    successRate: number;
    avgMinutes: number | null;
    activeDeliveries: number;
    deliveredToday: number;
    failedToday: number;
    reattemptRate: number;
  };
  active: Rider[];
  zones: { zone: string | null; active: number }[];
}

export default function DeliveryCommandCenterPage() {
  const q = useQuery({
    queryKey: ["admin", "delivery", "command-center"],
    queryFn: () => api.get<CommandCenter>("/admin/delivery/command-center"),
    refetchInterval: 15000,
  });
  const d = q.data;
  const loading = q.isLoading;

  // Live deltas streamed between polls. Reset on each fresh poll (the poll is the
  // authoritative baseline; the socket just moves riders smoothly in between).
  const [live, setLive] = React.useState<Record<number, Partial<Rider>>>({});
  React.useEffect(() => {
    setLive({});
  }, [q.dataUpdatedAt]);

  const { connected } = useDeliverySocket(
    "/ws/admin/delivery/command-center",
    React.useCallback((msg: unknown) => {
      const m = msg as { type?: string; data?: Rider & { id: number } };
      if (m?.type !== "dispatch" || !m.data?.id) return;
      const r = m.data;
      setLive((prev) => ({ ...prev, [r.id]: { ...prev[r.id], ...r } }));
    }, []),
  );

  // Merge the polled riders with the live deltas (by id), dropping anything that
  // has reached a terminal status via the socket.
  const riders = React.useMemo<Rider[]>(() => {
    const byId = new Map<number, Rider>();
    for (const r of d?.active ?? []) byId.set(r.id, r);
    for (const [id, patch] of Object.entries(live)) {
      const base = byId.get(Number(id));
      byId.set(Number(id), { ...(base ?? { id: Number(id), zone: null }), ...patch } as Rider);
    }
    return [...byId.values()].filter((r) => !TERMINAL.has(r.status));
  }, [d?.active, live]);

  return (
    <div className="space-y-6">
      <PageHeader
        title="Delivery Command Center"
        description="Live fleet — every active rider, with KPIs and zone load. Riders move in real time over a 15s baseline."
        actions={
          <div className="flex items-center gap-3">
            <span className="flex items-center gap-1.5 text-xs font-medium text-muted-foreground">
              <span
                className={`inline-block size-2 rounded-full ${connected ? "animate-pulse bg-green-500" : "bg-muted-foreground/40"}`}
              />
              {connected ? "Live" : "Reconnecting…"}
            </span>
            <Button asChild variant="outline">
              <Link href="/delivery">Control Center</Link>
            </Button>
          </div>
        }
      />

      <div className="grid grid-cols-2 gap-3 sm:grid-cols-3 lg:grid-cols-6">
        <StatCard label="Active Deliveries" value={d?.kpis.activeDeliveries ?? 0} loading={loading} />
        <StatCard label="Delivered Today" value={d?.kpis.deliveredToday ?? 0} accent="green" loading={loading} />
        <StatCard label="Failed Today" value={d?.kpis.failedToday ?? 0} accent="red" loading={loading} />
        <StatCard label="Success Rate" value={`${d?.kpis.successRate ?? 0}%`} accent="green" loading={loading} />
        <StatCard label="Avg Delivery" value={`${d?.kpis.avgMinutes ?? 0} min`} loading={loading} />
        <StatCard label="Reattempt Rate" value={`${d?.kpis.reattemptRate ?? 0}%`} accent="gold" loading={loading} />
      </div>

      <Card>
        <CardHeader>
          <CardTitle>Live Fleet</CardTitle>
        </CardHeader>
        <CardContent>
          <div className="h-[460px] w-full overflow-hidden rounded-lg border">
            <FleetMap riders={riders} />
          </div>
        </CardContent>
      </Card>

      <div className="grid gap-4 lg:grid-cols-3">
        <Card className="lg:col-span-2">
          <CardHeader>
            <CardTitle>Active Deliveries ({riders.length})</CardTitle>
          </CardHeader>
          <CardContent className="space-y-2">
            {riders.length === 0 && (
              <p className="text-sm text-muted-foreground">No active deliveries right now.</p>
            )}
            {riders.map((r) => (
              <div
                key={r.id}
                className="flex items-center justify-between rounded-md border px-3 py-2 text-sm"
              >
                <div className="min-w-0">
                  <Link href={`/orders/${r.orderCode ?? ""}`} className="font-medium hover:underline">
                    {r.orderCode}
                  </Link>
                  <div className="truncate text-xs text-muted-foreground">
                    {r.agent ?? "Unassigned"} · {r.zone ?? "Unzoned"}
                    {r.eta ? ` · ETA ${r.eta}` : ""}
                  </div>
                </div>
                <StatusBadge status={r.status} />
              </div>
            ))}
          </CardContent>
        </Card>

        <Card>
          <CardHeader>
            <CardTitle>Zone Load</CardTitle>
          </CardHeader>
          <CardContent className="space-y-2">
            {(d?.zones ?? []).length === 0 && (
              <p className="text-sm text-muted-foreground">No active zones.</p>
            )}
            {(d?.zones ?? []).map((z) => (
              <div key={z.zone ?? "unzoned"} className="flex items-center justify-between text-sm">
                <span>{z.zone ?? "Unzoned"}</span>
                <span className="font-semibold tabular-nums">{z.active}</span>
              </div>
            ))}
          </CardContent>
        </Card>
      </div>
    </div>
  );
}
