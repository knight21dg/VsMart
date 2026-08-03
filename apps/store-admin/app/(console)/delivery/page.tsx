"use client";

import * as React from "react";
import { useQuery } from "@tanstack/react-query";
import type { ColumnDef } from "@tanstack/react-table";
import { Loader2, MapPin } from "lucide-react";
import { api, useApiMutation } from "@/lib/api/hooks";
import { useStore } from "@/lib/store/store-context";
import { PageHeader } from "@/components/page-header";
import { DataTable } from "@/components/data-table";
import { RequirePerm } from "@/components/permission-gate";
import { StatusBadge } from "@/components/status-badge";
import { AgentTrackDialog } from "@/components/agent-track-dialog";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";
import { Button } from "@/components/ui/button";
import { Badge } from "@/components/ui/badge";
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from "@/components/ui/select";
import {
  Dialog, DialogContent, DialogFooter, DialogHeader, DialogTitle,
} from "@/components/ui/dialog";
import { fmtDate } from "@/lib/utils";

// A rider is actually out and postable somewhere between these — matches the
// backend's LIVE_TASK_STATUSES (delivery/services.py). Before "assigned" or
// after "delivered" there's no live position to show.
const LIVE_STATUSES = new Set(["assigned", "accepted", "picked_up", "out_for_delivery", "reached"]);
// Closed tasks — mirrors DeliveryTask.TERMINAL on the backend. Reassign was
// gated only on "delivered", so it still rendered on cancelled, rejected,
// returned-to-store and already-reassigned rows.
const TERMINAL_STATUSES = new Set([
  "delivered", "rejected", "returned_to_store", "reassigned", "cancelled",
]);

interface DeliveryRow {
  id: number; orderCode: string | null; customer: string | null; phone: string | null;
  address: string | null; agent: string | null; agentId: string | null; status: string;
  assignedAt: string; distanceKm: number | null;
}
interface AgentRow { id: string; name: string; onDuty: boolean; active: number; deliveredToday: number; }

interface ReturnRow {
  taskId: number;
  orderCode: string;
  status: string;
  customer: string;
  agent: string;
  agentPhone: string;
  amount: number;
  failureReason: string;
  failedAt: string | null;
}

export default function DeliveryPage() {
  return (
    <RequirePerm perm="delivery.view">
      <DeliveryInner />
    </RequirePerm>
  );
}

function DeliveryInner() {
  const { hasPerm } = useStore();
  const canManage = hasPerm("delivery.manage");
  const [reassign, setReassign] = React.useState<DeliveryRow | null>(null);
  const [trackOrderCode, setTrackOrderCode] = React.useState<string | null>(null);

  const listQ = useQuery({ queryKey: ["store", "delivery"], queryFn: () => api.get<DeliveryRow[]>("/store/delivery"), refetchInterval: 30_000 });
  const agentsQ = useQuery({ queryKey: ["store", "delivery", "agents"], queryFn: () => api.get<AgentRow[]>("/store/delivery/agents") });

  // Goods coming BACK: failed deliveries the agent is returning. Confirming
  // receipt here is what restores stock and closes the order.
  const returnsQ = useQuery({
    queryKey: ["store", "delivery", "returns"],
    queryFn: () => api.get<ReturnRow[]>("/store/delivery/returns"),
    refetchInterval: 30_000,
  });
  const receiveReturn = useApiMutation(
    (taskId: number) => api.post(`/store/delivery/${taskId}/receive-return`),
    {
      invalidate: [["store", "delivery"], ["store", "delivery", "returns"]],
      successMessage: "Return received — stock restored, order closed",
    }
  );

  // Failed deliveries get their own "needs retry" section below (like
  // Returns) instead of sitting mixed into the main list looking like just
  // another still-in-progress row — a failed delivery isn't "pending",
  // it's stalled and needs an explicit decision.
  const allRows = listQ.data ?? [];
  const activeRows = allRows.filter((r) => r.status !== "failed");
  const failedRows = allRows.filter((r) => r.status === "failed");

  const columns: ColumnDef<DeliveryRow, unknown>[] = [
    { header: "Order", cell: ({ row }) => <span className="font-mono text-sm">{row.original.orderCode ?? "—"}</span> },
    { header: "Customer", cell: ({ row }) => <div><div className="text-sm">{row.original.customer ?? "—"}</div><div className="text-xs text-muted-foreground">{row.original.phone}</div></div> },
    { header: "Agent", cell: ({ row }) => <span className="text-sm">{row.original.agent ?? <span className="text-muted-foreground">Unassigned</span>}</span> },
    { header: "Distance", cell: ({ row }) => <span className="text-sm text-muted-foreground">{row.original.distanceKm != null ? `${row.original.distanceKm} km` : "—"}</span> },
    { header: "Status", cell: ({ row }) => <StatusBadge status={row.original.status} /> },
    { header: "Assigned", cell: ({ row }) => <span className="text-xs text-muted-foreground">{fmtDate(row.original.assignedAt, true)}</span> },
    {
      // The agent owns this status from here — matches the "with agent" state
      // on the Orders page. The store's only lever is who's carrying it.
      header: "", id: "actions",
      cell: ({ row }) => (
        <div className="flex justify-end gap-1.5">
          {LIVE_STATUSES.has(row.original.status) && row.original.orderCode && (
            <Button variant="outline" size="sm" onClick={() => setTrackOrderCode(row.original.orderCode)}>
              <MapPin className="size-4" /> Track
            </Button>
          )}
          {canManage && !TERMINAL_STATUSES.has(row.original.status) && (
            <Button variant="outline" size="sm" onClick={() => setReassign(row.original)}>Reassign</Button>
          )}
        </div>
      ),
    },
  ];

  return (
    <div className="space-y-5">
      <PageHeader
        title="Delivery"
        description="Track your store's deliveries — the assigned agent owns their status from out for delivery onward."
      />

      <Card>
        <CardHeader><CardTitle className="text-sm">Delivery agents</CardTitle></CardHeader>
        <CardContent className="flex flex-wrap gap-2 pt-0">
          {(agentsQ.data ?? []).length === 0 && <span className="text-sm text-muted-foreground">No agents available.</span>}
          {(agentsQ.data ?? []).map((a) => (
            <div key={a.id} className="flex items-center gap-2 rounded-lg border px-3 py-1.5 text-sm">
              <span className={`size-2 rounded-full ${a.onDuty ? "bg-[var(--color-success)]" : "bg-muted-foreground/40"}`} />
              <span className="font-medium">{a.name}</span>
              <Badge variant="secondary">{a.active} active</Badge>
              <span className="text-xs text-muted-foreground">{a.deliveredToday} today</span>
            </div>
          ))}
        </CardContent>
      </Card>

      {failedRows.length > 0 && (
        <Card className="border-destructive/30">
          <CardHeader>
            <CardTitle className="text-sm">Failed — needs a decision</CardTitle>
          </CardHeader>
          <CardContent className="space-y-2 pt-0">
            {failedRows.map((r) => (
              <div key={r.id}
                   className="flex flex-wrap items-center justify-between gap-2 rounded-lg border px-3 py-2">
                <div>
                  <span className="font-mono text-sm">{r.orderCode ?? "—"}</span>
                  <span className="ml-2 text-sm">{r.customer ?? "—"}</span>
                  <div className="text-xs text-muted-foreground">
                    {r.agent ?? "Unassigned"} · <StatusBadge status={r.status} />
                  </div>
                </div>
                {canManage && (
                  <Button variant="outline" size="sm" onClick={() => setReassign(r)}>
                    Retry with another agent
                  </Button>
                )}
              </div>
            ))}
          </CardContent>
        </Card>
      )}

      {(returnsQ.data ?? []).length > 0 && (
        <Card>
          <CardHeader>
            <CardTitle className="text-sm">Returns to receive</CardTitle>
          </CardHeader>
          <CardContent className="space-y-2 pt-0">
            {(returnsQ.data ?? []).map((r) => (
              <div key={r.taskId}
                   className="flex flex-wrap items-center justify-between gap-2 rounded-lg border px-3 py-2">
                <div>
                  <span className="font-mono text-sm">{r.orderCode}</span>
                  <span className="ml-2 text-sm">{r.customer}</span>
                  <div className="text-xs text-muted-foreground">
                    {r.agent} · {r.failureReason || "failed"} ·
                    <StatusBadge status={r.status} />
                  </div>
                </div>
                {canManage && (
                  <Button size="sm" disabled={receiveReturn.isPending}
                          onClick={() => receiveReturn.mutate(r.taskId)}>
                    Confirm received
                  </Button>
                )}
              </div>
            ))}
          </CardContent>
        </Card>
      )}

      <DataTable columns={columns} data={activeRows} loading={listQ.isLoading} error={listQ.error ? "Couldn't load deliveries." : null} onRetry={() => listQ.refetch()} emptyMessage="No deliveries yet." />

      {reassign && <ReassignDialog row={reassign} agents={agentsQ.data ?? []} onClose={() => setReassign(null)} />}
      <AgentTrackDialog orderCode={trackOrderCode} onClose={() => setTrackOrderCode(null)} />
    </div>
  );
}

function ReassignDialog({ row, agents, onClose }: { row: DeliveryRow; agents: AgentRow[]; onClose: () => void }) {
  const [agentId, setAgentId] = React.useState(row.agentId ?? "");
  const m = useApiMutation<void>(
    () => api.post(`/store/delivery/${row.id}/reassign`, { agentId }),
    { invalidate: [["store", "delivery"]], successMessage: "Reassigned", onDone: onClose }
  );
  return (
    <Dialog open onOpenChange={(o) => !o && onClose()}>
      <DialogContent className="max-w-md">
        <DialogHeader><DialogTitle>Reassign delivery — {row.orderCode}</DialogTitle></DialogHeader>
        <Select value={agentId} onValueChange={setAgentId}>
          <SelectTrigger><SelectValue placeholder="Pick an agent" /></SelectTrigger>
          <SelectContent>{agents.map((a) => <SelectItem key={a.id} value={a.id}>{a.name}</SelectItem>)}</SelectContent>
        </Select>
        <DialogFooter>
          <Button variant="outline" onClick={onClose} disabled={m.isPending}>Cancel</Button>
          <Button onClick={() => m.mutate()} disabled={m.isPending || !agentId}>
            {m.isPending && <Loader2 className="size-4 animate-spin" />} Assign
          </Button>
        </DialogFooter>
      </DialogContent>
    </Dialog>
  );
}
