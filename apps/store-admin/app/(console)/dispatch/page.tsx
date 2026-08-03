"use client";

import * as React from "react";
import { useQuery, useQueryClient } from "@tanstack/react-query";
import { toast } from "sonner";
import { Loader2, Route, Sparkles, Truck } from "lucide-react";
import { api, useApiMutation } from "@/lib/api/hooks";
import { useStore } from "@/lib/store/store-context";
import { PageHeader } from "@/components/page-header";
import { RequirePerm } from "@/components/permission-gate";
import { StatCard } from "@/components/stat-card";
import { StatusBadge } from "@/components/status-badge";
import { Button } from "@/components/ui/button";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";
import { Badge } from "@/components/ui/badge";
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from "@/components/ui/select";
import {
  Dialog, DialogContent, DialogHeader, DialogTitle, DialogDescription,
} from "@/components/ui/dialog";
import { ErrorState, LoadingState } from "@/components/states";
import { KV, Section, sheetClass } from "@/components/detail-sheet";
import { inr, titleize } from "@/lib/utils";

interface QueueOrder { code: string; customer: string | null; items: number; value: number; paymentMethod: string; priority: string }
interface AgentRow { id: string; name: string; phone: string; available: boolean; vehicle: string; bagCapacity: number; cashCapacity: number; maxStops: number; rating: number; activeLoad: number }
interface Coll { id: string; customer: string | null; amount: number }
interface Queue {
  queue: QueueOrder[]; collections: Coll[]; agents: AgentRow[];
  kpis: { readyOrders: number; availableAgents: number; pendingCollections: number; collectionsValue: number; activeBatches: number };
}
interface BatchRow { id: number; status: string; priority: string; agent: string | null; stops: number; deliveries: number; collections: number; distanceKm: number; etaMinutes: number; pickupCode: string; createdAt: string }

export default function DispatchPage() {
  return (
    <RequirePerm perm="delivery.view">
      <DispatchInner />
    </RequirePerm>
  );
}

function DispatchInner() {
  const qc = useQueryClient();
  const { hasPerm } = useStore();
  const canManage = hasPerm("delivery.manage");
  const [selected, setSelected] = React.useState<Set<string>>(new Set());
  const [manualAgent, setManualAgent] = React.useState<string>("");
  const [openBatch, setOpenBatch] = React.useState<number | null>(null);

  const queueQ = useQuery({
    queryKey: ["store", "dispatch", "queue"],
    queryFn: () => api.get<Queue>("/store/dispatch/queue"),
    refetchInterval: 30_000,
  });
  const batchesQ = useQuery({
    queryKey: ["store", "dispatch", "batches"],
    queryFn: () => api.get<BatchRow[]>("/store/dispatch/batches", { status: "active" }),
    refetchInterval: 30_000,
  });

  const invalidate = () => {
    qc.invalidateQueries({ queryKey: ["store", "dispatch"] });
    setSelected(new Set());
  };

  const autoAssign = useApiMutation<void, { batches: number; assigned: number; queued: number; orders: number }>(
    () => api.post("/store/dispatch/auto-assign", {}),
    {
      onDone: (r) => {
        invalidate();
        toast.success(`${r.assigned} batch(es) assigned · ${r.queued} still queued`);
      },
    },
  );
  const manualAssign = useApiMutation<void>(
    () => api.post("/store/dispatch/manual", { orderCodes: [...selected], agentId: manualAgent }),
    { successMessage: "Batch created", onDone: invalidate },
  );

  const q = queueQ.data;

  function toggle(code: string) {
    setSelected((s) => {
      const n = new Set(s);
      if (n.has(code)) n.delete(code); else n.add(code);
      return n;
    });
  }

  return (
    <div className="space-y-5">
      <PageHeader
        title="Dispatch"
        description="Plan, batch and assign delivery + collection routes to your agents."
        actions={
          canManage ? (
            <Button
              onClick={() => autoAssign.mutate()}
              disabled={autoAssign.isPending || (q?.kpis.readyOrders ?? 0) === 0}
            >
              {autoAssign.isPending ? <Loader2 className="size-4 animate-spin" /> : <Sparkles className="size-4" />}
              Auto Assign
            </Button>
          ) : null
        }
      />

      <div className="grid grid-cols-2 gap-3 sm:grid-cols-4">
        <StatCard label="Ready orders" value={q?.kpis.readyOrders ?? "—"} accent="teal" />
        <StatCard label="Available agents" value={q?.kpis.availableAgents ?? "—"} accent="green" />
        <StatCard label="Pending collections" value={q ? inr(q.kpis.collectionsValue) : "—"} accent="gold" />
        <StatCard label="Active batches" value={q?.kpis.activeBatches ?? "—"} accent="slate" />
      </div>

      {queueQ.isLoading ? (
        <LoadingState label="Loading dispatch…" />
      ) : queueQ.error || !q ? (
        <ErrorState message="Couldn't load the dispatch queue." onRetry={() => queueQ.refetch()} />
      ) : (
        <div className="grid gap-4 lg:grid-cols-[1fr_320px]">
          {/* Assignment queue */}
          <Card>
            <CardHeader className="flex-row items-center justify-between py-3">
              <CardTitle className="text-sm">Assignment queue ({q.queue.length})</CardTitle>
              {canManage && selected.size > 0 && (
                <div className="flex items-center gap-2">
                  <Select value={manualAgent} onValueChange={setManualAgent}>
                    <SelectTrigger className="h-8 w-[150px] text-xs"><SelectValue placeholder="Pick agent" /></SelectTrigger>
                    <SelectContent>
                      {q.agents.map((a) => <SelectItem key={a.id} value={a.id}>{a.name}</SelectItem>)}
                    </SelectContent>
                  </Select>
                  <Button size="sm" disabled={!manualAgent || manualAssign.isPending} onClick={() => manualAssign.mutate()}>
                    Assign {selected.size}
                  </Button>
                </div>
              )}
            </CardHeader>
            <CardContent className="pt-0">
              {q.queue.length === 0 ? (
                <p className="py-8 text-center text-sm text-muted-foreground">Queue is clear — everything's assigned.</p>
              ) : (
                <ul className="divide-y">
                  {q.queue.map((o) => (
                    <li key={o.code} className="flex items-center gap-3 py-2">
                      {canManage && (
                        <input type="checkbox" checked={selected.has(o.code)} onChange={() => toggle(o.code)} className="size-4 accent-primary" />
                      )}
                      <div className="min-w-0 flex-1">
                        <p className="truncate text-sm font-medium">{o.customer ?? o.code}</p>
                        <p className="text-xs text-muted-foreground">{o.code} · {o.items} items · {titleize(o.paymentMethod)}</p>
                      </div>
                      {o.priority !== "normal" && <Badge variant="warning" className="capitalize">{o.priority}</Badge>}
                      <span className="w-20 text-right text-sm font-semibold">{inr(o.value)}</span>
                    </li>
                  ))}
                </ul>
              )}
              {q.collections.length > 0 && (
                <div className="mt-3 rounded-lg bg-muted/40 p-3">
                  <p className="text-xs font-semibold uppercase tracking-wider text-muted-foreground">On-route collections ({q.collections.length})</p>
                  <p className="mt-1 text-xs text-muted-foreground">
                    {inr(q.kpis.collectionsValue)} pending — the engine folds nearby collections into delivery routes automatically.
                  </p>
                </div>
              )}
            </CardContent>
          </Card>

          {/* Agents */}
          <Card>
            <CardHeader className="py-3"><CardTitle className="text-sm">Agents ({q.agents.length})</CardTitle></CardHeader>
            <CardContent className="pt-0">
              {q.agents.length === 0 ? (
                <p className="py-6 text-center text-sm text-muted-foreground">No available agents.</p>
              ) : (
                <ul className="divide-y">
                  {q.agents.map((a) => (
                    <li key={a.id} className="py-2">
                      <div className="flex items-center justify-between">
                        <p className="text-sm font-medium">{a.name}</p>
                        <Badge variant={a.available ? "success" : "secondary"}>{a.available ? "available" : "off"}</Badge>
                      </div>
                      <p className="text-xs text-muted-foreground">
                        {titleize(a.vehicle || "bike")} · load {a.activeLoad}/{a.maxStops} · bag {a.bagCapacity} · ★ {a.rating}
                      </p>
                    </li>
                  ))}
                </ul>
              )}
            </CardContent>
          </Card>
        </div>
      )}

      {/* Batches board */}
      <Card>
        <CardHeader className="py-3"><CardTitle className="flex items-center gap-2 text-sm"><Route className="size-4" /> Active batches</CardTitle></CardHeader>
        <CardContent className="pt-0">
          {batchesQ.isLoading ? (
            <LoadingState label="Loading batches…" />
          ) : (batchesQ.data ?? []).length === 0 ? (
            <p className="py-8 text-center text-sm text-muted-foreground">No active batches. Run Auto Assign to build routes.</p>
          ) : (
            <ul className="divide-y">
              {(batchesQ.data ?? []).map((b) => (
                <li key={b.id}>
                  <button onClick={() => setOpenBatch(b.id)} className="flex w-full items-center gap-3 py-2.5 text-left hover:bg-accent/40">
                    <div className="flex size-9 items-center justify-center rounded-lg bg-primary/10 text-primary"><Truck className="size-4" /></div>
                    <div className="min-w-0 flex-1">
                      <p className="truncate text-sm font-medium">Batch #{b.id} · {b.agent ?? "unassigned"}</p>
                      <p className="text-xs text-muted-foreground">
                        {b.deliveries} deliveries{b.collections > 0 ? ` · ${b.collections} collections` : ""} · {b.distanceKm} km · ~{b.etaMinutes} min
                      </p>
                    </div>
                    {b.priority && b.priority !== "normal" && <Badge variant="warning" className="capitalize">{b.priority}</Badge>}
                    <StatusBadge status={b.status} />
                  </button>
                </li>
              ))}
            </ul>
          )}
        </CardContent>
      </Card>

      <BatchDetailSheet batchId={openBatch} onClose={() => setOpenBatch(null)} />
    </div>
  );
}

interface BatchDetail extends BatchRow {
  encodedPolyline: string;
  stopList: { sequence: number; kind: string; label: string; status: string; orderCode: string | null; amount: number }[];
}

function BatchDetailSheet({ batchId, onClose }: { batchId: number | null; onClose: () => void }) {
  const qc = useQueryClient();
  const { hasPerm } = useStore();
  const canManage = hasPerm("delivery.manage");
  const open = batchId !== null;
  const q = useQuery({
    queryKey: ["store", "dispatch", "batch", batchId],
    queryFn: () => api.get<BatchDetail>(`/store/dispatch/batches/${batchId}`),
    enabled: open,
  });
  const d = q.data;
  const done = () => {
    qc.invalidateQueries({ queryKey: ["store", "dispatch"] });
    onClose();
  };
  const reassign = useApiMutation<void>(
    () => api.post(`/store/dispatch/batches/${batchId}/reassign`, {}),
    { successMessage: "Batch reassigned", onDone: done },
  );
  const cancel = useApiMutation<void>(
    () => api.post(`/store/dispatch/batches/${batchId}/cancel`, {}),
    { successMessage: "Batch released", onDone: done },
  );
  const terminal = d ? ["completed", "cancelled", "failed"].includes(d.status) : true;

  return (
    <Dialog open={open} onOpenChange={(o) => !o && onClose()}>
      <DialogContent className={sheetClass}>
        <DialogHeader>
          <DialogTitle>Batch #{batchId}</DialogTitle>
          <DialogDescription>{d ? `${d.agent ?? "unassigned"} · ${d.distanceKm} km · ~${d.etaMinutes} min` : "Route detail"}</DialogDescription>
        </DialogHeader>
        {q.isLoading ? (
          <LoadingState label="Loading route…" />
        ) : q.error || !d ? (
          <ErrorState message="Couldn't load this batch." onRetry={() => q.refetch()} />
        ) : (
          <div className="space-y-5 text-sm">
            <div className="flex flex-wrap items-center gap-2">
              <StatusBadge status={d.status} />
              {d.pickupCode && <Badge variant="secondary">Pickup OTP {d.pickupCode}</Badge>}
            </div>
            {canManage && !terminal && (
              <div className="flex gap-2">
                <Button size="sm" variant="outline" disabled={reassign.isPending} onClick={() => reassign.mutate()}>
                  Reassign
                </Button>
                <Button size="sm" variant="outline" className="text-destructive" disabled={cancel.isPending} onClick={() => cancel.mutate()}>
                  Release / cancel
                </Button>
              </div>
            )}
            <Section title="Summary">
              <KV label="Agent" value={d.agent ?? "—"} />
              <KV label="Stops" value={`${d.deliveries} deliveries · ${d.collections} collections`} />
              <KV label="Distance / ETA" value={`${d.distanceKm} km · ~${d.etaMinutes} min`} />
            </Section>
            <Section title={`Route (${d.stopList.length} stops)`}>
              <ol className="space-y-2">
                {d.stopList.map((s) => (
                  <li key={s.sequence} className="flex gap-3">
                    <div className="flex size-6 shrink-0 items-center justify-center rounded-full bg-primary text-xs font-bold text-primary-foreground">{s.sequence}</div>
                    <div className="min-w-0 flex-1">
                      <p className="font-medium">
                        {s.kind === "collection" ? "Collect " : ""}{s.label}
                        {s.kind === "collection" && s.amount > 0 ? ` · ${inr(s.amount)}` : ""}
                      </p>
                      <p className="text-xs text-muted-foreground">
                        {s.kind === "delivery" ? `Deliver ${s.orderCode ?? ""}` : "Cash collection"} · {titleize(s.status)}
                      </p>
                    </div>
                  </li>
                ))}
              </ol>
            </Section>
          </div>
        )}
      </DialogContent>
    </Dialog>
  );
}
