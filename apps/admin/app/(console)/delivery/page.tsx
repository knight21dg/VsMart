"use client";

import * as React from "react";
import Link from "next/link";
import { keepPreviousData, useQuery } from "@tanstack/react-query";
import { type ColumnDef } from "@tanstack/react-table";
import { MapPin, MoreHorizontal, RotateCcw } from "lucide-react";
import { api } from "@/lib/api/client";
import { useApiMutation } from "@/lib/api/hooks";
import { PageHeader } from "@/components/page-header";
import { ConfirmDialog } from "@/components/confirm-dialog";
import { StatCard } from "@/components/stat-card";
import { DataTable } from "@/components/data-table";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";
import { Button } from "@/components/ui/button";
import { Label } from "@/components/ui/label";
import { StatusBadge } from "@/components/status-badge";
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from "@/components/ui/select";
import { DropdownMenu, DropdownMenuContent, DropdownMenuItem, DropdownMenuSeparator, DropdownMenuTrigger } from "@/components/ui/dropdown-menu";
import { Dialog, DialogContent, DialogFooter, DialogHeader, DialogTitle } from "@/components/ui/dialog";
import { fmtDate, titleize } from "@/lib/utils";
import { ApiError } from "@/lib/types";

interface DeliveryDash {
  activeDeliveries: number;
  pendingAcceptance: number;
  outForDelivery: number;
  deliveredToday: number;
  failedToday: number;
  agentsOnDuty: number;
  avgDeliveryMinutes: number;
  onTimeRate: number;
}
interface DeliveryRow {
  id: number;
  orderCode: string | null;
  customer: string | null;
  phone: string | null;
  store: string | null;
  zone: string | null;
  agent: string | null;
  status: string;
  assignedAt: string;
  startedAt: string | null;
  deliveredAt: string | null;
  distanceKm: number | null;
}
interface AgentLoad {
  id: string;
  name: string;
  onDuty: boolean;
  active: number;
  deliveredToday: number;
}
interface ReattemptRow {
  id: number;
  orderCode: string | null;
  agent: string | null;
  attemptNo: number;
  reason: string | null;
  note: string | null;
  failedAt: string | null;
}

const FILTERS = ["active", "pending", "started", "delivered", "failed"];

export default function DeliveryPage() {
  const [status, setStatus] = React.useState("active");
  const [reassign, setReassign] = React.useState<DeliveryRow | null>(null);
  const [pickAgent, setPickAgent] = React.useState("");
  // Irreversible actions (mark-failed, return-to-store) route through here so a
  // stray click on a dropdown item can't terminate a live delivery.
  const [confirm, setConfirm] = React.useState<
    { title: string; description: string; confirmLabel: string; run: () => void } | null
  >(null);

  const dash = useQuery({ queryKey: ["admin", "delivery", "dashboard"], queryFn: () => api.get<DeliveryDash>("/admin/delivery/dashboard"), refetchInterval: 30000 });
  const agentsQ = useQuery({ queryKey: ["admin", "delivery", "agents"], queryFn: () => api.get<AgentLoad[]>("/admin/delivery/agents") });
  const list = useQuery({
    queryKey: ["admin", "delivery", { status }],
    queryFn: () => api.get<DeliveryRow[]>("/admin/delivery", { status, limit: 300 }),
    placeholderData: keepPreviousData,
    refetchInterval: 30000,
  });

  const d = dash.data;
  const rows = list.data ?? [];
  const agents = agentsQ.data ?? [];
  const invalidate = [["admin", "delivery"]];

  const setStatusMut = useApiMutation(
    (v: { id: number; status: string }) => api.post(`/admin/delivery/${v.id}/status`, { status: v.status }),
    { invalidate, successMessage: "Delivery updated.", onDone: () => setConfirm(null) }
  );
  const reassignMut = useApiMutation(
    (v: { id: number; agentId: string }) => api.post(`/admin/delivery/${v.id}/reassign`, { agentId: v.agentId }),
    { invalidate, successMessage: "Reassigned.", onDone: () => { setReassign(null); setPickAgent(""); } }
  );

  // Failed-delivery recovery queue — the backend has always exposed these actions
  // (reattempt / return-to-store / manual OTP override); nothing surfaced them.
  const reattemptQ = useQuery({
    queryKey: ["admin", "delivery", "reattempt-queue"],
    queryFn: () => api.get<ReattemptRow[]>("/admin/delivery/reattempt-queue"),
    refetchInterval: 30000,
  });
  const reattemptMut = useApiMutation(
    (v: { id: number; mode: string }) => api.post(`/admin/delivery/${v.id}/reattempt`, { mode: v.mode }),
    { invalidate, successMessage: "Reattempt scheduled." },
  );
  const returnMut = useApiMutation(
    (id: number) => api.post(`/admin/delivery/${id}/return`),
    { invalidate, successMessage: "Returned to store.", onDone: () => setConfirm(null) },
  );
  const manualVerifyMut = useApiMutation(
    (id: number) => api.post(`/admin/delivery/${id}/manual-verify`),
    { invalidate, successMessage: "OTP lock overridden — customer manually verified." },
  );
  const reattemptRows = reattemptQ.data ?? [];

  const columns: ColumnDef<DeliveryRow, unknown>[] = [
    {
      accessorKey: "orderCode",
      header: "Order",
      cell: ({ row }) => (
        <div>
          <p className="font-mono text-xs font-medium">{row.original.orderCode}</p>
          <p className="text-xs text-muted-foreground">{fmtDate(row.original.assignedAt, true)}</p>
        </div>
      ),
    },
    {
      accessorKey: "customer",
      header: "Customer",
      cell: ({ row }) => (
        <div className="min-w-0">
          <p className="truncate font-medium">{row.original.customer || "—"}</p>
          <p className="font-mono text-xs text-muted-foreground">{row.original.phone}</p>
        </div>
      ),
    },
    {
      accessorKey: "store",
      header: "Store / Zone",
      cell: ({ row }) => (
        <div className="text-xs">
          <p>{row.original.store || "—"}</p>
          <p className="text-muted-foreground">{row.original.zone || "—"}</p>
        </div>
      ),
    },
    { accessorKey: "agent", header: "Agent", cell: ({ row }) => <span className="text-sm">{row.original.agent || "Unassigned"}</span> },
    { accessorKey: "distanceKm", header: "Distance", cell: ({ row }) => <span className="tabular-nums">{row.original.distanceKm != null ? `${row.original.distanceKm} km` : "—"}</span> },
    { accessorKey: "status", header: "Status", cell: ({ row }) => <StatusBadge status={row.original.status} /> },
    {
      id: "actions",
      header: "",
      cell: ({ row }) => (
        <DropdownMenu>
          <DropdownMenuTrigger asChild>
            <Button variant="ghost" size="icon"><MoreHorizontal /></Button>
          </DropdownMenuTrigger>
          <DropdownMenuContent align="end">
            <DropdownMenuItem onSelect={() => setStatusMut.mutate({ id: row.original.id, status: "started" })}>Mark Out for Delivery</DropdownMenuItem>
            <DropdownMenuItem
              destructive
              onSelect={() =>
                setConfirm({
                  title: `Mark ${row.original.orderCode ?? "this delivery"} as failed?`,
                  description:
                    `${row.original.customer || "The customer"} will not receive this order today. Marking failed is ` +
                    `terminal — the backend refuses to move a failed delivery back to out-for-delivery. Recovery is ` +
                    `only possible from the reattempt queue.`,
                  confirmLabel: "Mark failed",
                  run: () => setStatusMut.mutate({ id: row.original.id, status: "failed" }),
                })
              }
            >
              Mark Failed
            </DropdownMenuItem>
            {/* No "Mark Delivered" here — only the agent's own OTP + photo
                verification can complete a delivery (delivery.services.
                complete_delivery). The backend now rejects this status from
                this panel outright. */}
            <DropdownMenuSeparator />
            <DropdownMenuItem onSelect={() => { setReassign(row.original); setPickAgent(""); }}>Reassign Agent…</DropdownMenuItem>
          </DropdownMenuContent>
        </DropdownMenu>
      ),
    },
  ];

  return (
    <>
      <PageHeader
        title="Delivery Control Center"
        description="Live dispatch, agent load, and the delivery queue."
        actions={
          <Button asChild variant="outline">
            <Link href="/delivery/command-center">
              <MapPin className="mr-2 size-4" /> Live Map
            </Link>
          </Button>
        }
      />

      <div className="grid grid-cols-2 gap-4 md:grid-cols-4">
        <StatCard label="Active Deliveries" value={d?.activeDeliveries ?? 0} loading={dash.isLoading} />
        <StatCard label="Pending Acceptance" value={d?.pendingAcceptance ?? 0} accent="gold" loading={dash.isLoading} />
        <StatCard label="Out for Delivery" value={d?.outForDelivery ?? 0} loading={dash.isLoading} />
        <StatCard label="Delivered Today" value={d?.deliveredToday ?? 0} accent="green" loading={dash.isLoading} />
        <StatCard label="Failed Today" value={d?.failedToday ?? 0} accent="red" loading={dash.isLoading} />
        <StatCard label="Agents On Duty" value={d?.agentsOnDuty ?? 0} loading={dash.isLoading} />
        <StatCard label="Avg Delivery" value={`${d?.avgDeliveryMinutes ?? 0} min`} loading={dash.isLoading} />
        <StatCard label="On-Time Rate" value={`${d?.onTimeRate ?? 0}%`} accent="green" loading={dash.isLoading} />
      </div>

      <Card>
        <CardHeader><CardTitle>Agents</CardTitle></CardHeader>
        <CardContent>
          {agents.length === 0 ? (
            <p className="text-sm text-muted-foreground">No agents.</p>
          ) : (
            <div className="grid grid-cols-2 gap-2 sm:grid-cols-3 lg:grid-cols-4">
              {agents.slice(0, 12).map((a) => (
                <div key={a.id} className="flex items-center justify-between rounded-lg border bg-card px-3 py-2">
                  <span className="flex items-center gap-2 truncate">
                    <span className={"size-2 shrink-0 rounded-full " + (a.onDuty ? "bg-[var(--color-success)]" : "bg-muted-foreground")} />
                    <span className="truncate text-sm font-medium">{a.name}</span>
                  </span>
                  <span className="shrink-0 text-xs text-muted-foreground">{a.active} active · {a.deliveredToday}✓</span>
                </div>
              ))}
            </div>
          )}
        </CardContent>
      </Card>

      {reattemptRows.length > 0 && (
        <Card>
          <CardHeader>
            <CardTitle className="flex items-center gap-2 text-[var(--color-danger)]">
              <RotateCcw className="size-4" /> Failed deliveries — reattempt queue ({reattemptRows.length})
            </CardTitle>
          </CardHeader>
          <CardContent className="space-y-2">
            {reattemptRows.map((r) => {
              const busy = reattemptMut.isPending || returnMut.isPending || manualVerifyMut.isPending;
              return (
                <div key={r.id} className="flex flex-wrap items-center gap-2 rounded-lg border p-2.5">
                  <div className="min-w-0 flex-1">
                    <p className="font-mono text-xs font-medium">{r.orderCode} · attempt {r.attemptNo}</p>
                    <p className="truncate text-xs text-muted-foreground">
                      {r.agent || "Unassigned"} · {r.reason || "failed"}{r.note ? ` — ${r.note}` : ""} · {r.failedAt ? fmtDate(r.failedAt, true) : ""}
                    </p>
                  </div>
                  <div className="flex flex-wrap gap-1.5">
                    <Button size="sm" variant="outline" disabled={busy} onClick={() => reattemptMut.mutate({ id: r.id, mode: "today" })}>Retry today</Button>
                    <Button size="sm" variant="outline" disabled={busy} onClick={() => reattemptMut.mutate({ id: r.id, mode: "tomorrow" })}>Tomorrow</Button>
                    <Button size="sm" variant="outline" disabled={busy} onClick={() => manualVerifyMut.mutate(r.id)}>Manual verify</Button>
                    <Button
                      size="sm"
                      variant="outline"
                      disabled={busy}
                      onClick={() =>
                        setConfirm({
                          title: `Return ${r.orderCode ?? "this order"} to store?`,
                          description:
                            `This closes the delivery for good: the items go back into store stock and the customer's ` +
                            `credit charge for this order is reversed. The order cannot be re-dispatched afterwards — ` +
                            `use "Retry today" or "Tomorrow" instead if another attempt is possible.`,
                          confirmLabel: "Return to store",
                          run: () => returnMut.mutate(r.id),
                        })
                      }
                    >
                      Return to store
                    </Button>
                  </div>
                </div>
              );
            })}
          </CardContent>
        </Card>
      )}

      <DataTable
        columns={columns}
        data={rows}
        loading={list.isLoading}
        error={list.isError ? (list.error as ApiError)?.message ?? "Failed to load deliveries." : null}
        onRetry={() => list.refetch()}
        emptyMessage="No deliveries in this view."
        toolbar={
          <div className="flex items-center gap-2">
            <Select value={status} onValueChange={setStatus}>
              <SelectTrigger className="w-[160px]"><SelectValue placeholder="Status" /></SelectTrigger>
              <SelectContent>
                {FILTERS.map((f) => <SelectItem key={f} value={f}>{titleize(f)}</SelectItem>)}
              </SelectContent>
            </Select>
            <span className="ml-auto text-xs text-muted-foreground">{rows.length} deliveries</span>
          </div>
        }
      />

      <Dialog open={!!reassign} onOpenChange={(o) => !o && setReassign(null)}>
        <DialogContent className="max-w-md">
          <DialogHeader>
            <DialogTitle>Reassign {reassign?.orderCode}</DialogTitle>
          </DialogHeader>
          <div className="space-y-1.5">
            <Label>Delivery agent</Label>
            <Select value={pickAgent} onValueChange={setPickAgent}>
              <SelectTrigger><SelectValue placeholder="Choose an agent…" /></SelectTrigger>
              <SelectContent>
                {agents.map((a) => (
                  <SelectItem key={a.id} value={a.id}>{a.name}{a.onDuty ? " · on duty" : ""} ({a.active} active)</SelectItem>
                ))}
              </SelectContent>
            </Select>
          </div>
          <DialogFooter className="gap-2">
            <Button variant="outline" onClick={() => setReassign(null)}>Cancel</Button>
            <Button disabled={!pickAgent || reassignMut.isPending} onClick={() => reassign && reassignMut.mutate({ id: reassign.id, agentId: pickAgent })}>
              Reassign
            </Button>
          </DialogFooter>
        </DialogContent>
      </Dialog>

      {confirm && (
        <ConfirmDialog
          open
          onOpenChange={(o) => !o && setConfirm(null)}
          title={confirm.title}
          description={confirm.description}
          confirmLabel={confirm.confirmLabel}
          destructive
          loading={setStatusMut.isPending || returnMut.isPending}
          onConfirm={confirm.run}
        />
      )}
    </>
  );
}
