"use client";

import * as React from "react";
import { useQuery } from "@tanstack/react-query";
import { type ColumnDef } from "@tanstack/react-table";
import { Loader2, Star, UserCheck, Zap } from "lucide-react";
import { api } from "@/lib/api/client";
import { useApiMutation } from "@/lib/api/hooks";
import { PageHeader } from "@/components/page-header";
import { StatCard } from "@/components/stat-card";
import { DataTable } from "@/components/data-table";
import { StatusBadge } from "@/components/status-badge";
import { StoreZone, StoreZoneFilter } from "@/components/store-zone";
import { Button } from "@/components/ui/button";
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from "@/components/ui/select";
import { cn, fmtDate, inr } from "@/lib/utils";
import { type PageMeta } from "@/lib/types";

interface Collection {
  id: string; userName: string; userPhone: string; storeName: string | null; zoneName: string | null;
  amount: number; status: string; isPriority: boolean; agentId: string | null; agentName: string | null; createdAt: string;
}
interface Metrics {
  collectedToday: number; pendingAmount: number; pendingCount: number; priorityCount: number; overdueAmount: number;
  agentPerformance: { agentId: string; name: string; collected: number }[];
  byZone: { zone: string; collected: number; pending: number }[];
}
interface Agent { id: string; name: string }
interface AgingBucket { bucket: string; count: number; amount: number }
interface CommandCenter {
  kpis: { collectedToday: number; pendingAmount: number; openCount: number; disputed: number; escalated: number };
  aging: AgingBucket[];
}

const FILTERS = [{ key: "open", label: "Open" }, { key: "collected", label: "Collected" }, { key: "", label: "All" }];

export default function CollectionsPage() {
  const [status, setStatus] = React.useState("open");
  const [store, setStore] = React.useState("");
  const [zone, setZone] = React.useState("");
  const metrics = useQuery({ queryKey: ["collections", "metrics"], queryFn: () => api.get<Metrics>("/admin/collections/metrics") });
  const agents = useQuery({ queryKey: ["collections", "agents"], queryFn: () => api.get<Agent[]>("/admin/collections/agents") });
  const [page, setPage] = React.useState(1);
  // Reset to page 1 whenever the filters change, so a filter applied on page 4
  // can't land the operator on an empty page.
  React.useEffect(() => { setPage(1); }, [status, store, zone]);
  const list = useQuery({
    queryKey: ["collections", "list", status, store, zone, page],
    queryFn: () => api.getPaged<Collection>("/admin/collections", { status: status || undefined, store: store || undefined, zone: zone || undefined, page }),
  });
  const pageMeta = list.data?.meta as PageMeta | undefined;

  const update = useApiMutation(
    (vars: { id: string; body: Record<string, unknown> }) => api.patch(`/admin/collections/${vars.id}`, vars.body),
    { invalidate: [["collections", "list"], ["collections", "metrics"]], successMessage: "Updated." }
  );

  // Assigning MUST go through the dedicated endpoint, not a PATCH of the agent
  // field: only this path runs manual_assign, which writes assignment history
  // and pushes the job to the rider's app. Setting the column directly left the
  // agent with no notification and nothing new on their list.
  const assign = useApiMutation(
    (vars: { id: string; agentId: string }) =>
      api.post(`/admin/collections/${vars.id}/assign`, { agentId: vars.agentId }),
    {
      invalidate: [["collections", "list"], ["collections", "metrics"], ["collections", "command-center"]],
      successMessage: "Assigned — the agent has been notified.",
    }
  );

  // Recovery command center: aging buckets + the dunning-sweep and auto-assign
  // actions the backend has always exposed but no page ever called.
  const cc = useQuery({ queryKey: ["collections", "command-center"], queryFn: () => api.get<CommandCenter>("/admin/collections/command-center") });
  const INVALIDATE = [["collections", "list"], ["collections", "metrics"], ["collections", "command-center"]];
  const runDunning = useApiMutation(
    () => api.post("/admin/collections/dunning"),
    { invalidate: INVALIDATE, successMessage: "Dunning sweep complete — aged dues escalated." },
  );
  const autoAssign = useApiMutation(
    () => api.post("/admin/collections/auto-assign"),
    { invalidate: INVALIDATE, successMessage: "Unassigned collections routed to available agents." },
  );

  const m = metrics.data;
  const columns: ColumnDef<Collection, unknown>[] = [
    {
      id: "priority",
      header: "",
      cell: ({ row }) => (
        <button onClick={() => update.mutate({ id: row.original.id, body: { isPriority: !row.original.isPriority } })} title="Toggle priority">
          <Star className={cn("size-4", row.original.isPriority ? "fill-[var(--color-warning)] text-[var(--color-warning)]" : "text-muted-foreground")} />
        </button>
      ),
    },
    { id: "cust", header: "Customer", cell: ({ row }) => <div><p className="font-medium">{row.original.userName}</p><p className="font-mono text-xs text-muted-foreground">{row.original.userPhone}</p></div> },
    { id: "loc", header: "Store / Zone", cell: ({ row }) => <StoreZone store={row.original.storeName} zone={row.original.zoneName} /> },
    { accessorKey: "amount", header: "Amount", cell: ({ row }) => <span className="font-medium">{inr(row.original.amount)}</span> },
    { accessorKey: "status", header: "Status", cell: ({ row }) => <StatusBadge status={row.original.status} /> },
    {
      id: "agent",
      header: "Agent",
      cell: ({ row }) =>
        row.original.status === "collected" ? (
          <span className="text-sm text-muted-foreground">{row.original.agentName ?? "—"}</span>
        ) : (
          <Select value={row.original.agentId ?? ""} onValueChange={(v) => assign.mutate({ id: row.original.id, agentId: v })}>
            <SelectTrigger className="h-8 w-40"><SelectValue placeholder="Assign agent" /></SelectTrigger>
            <SelectContent>{(agents.data ?? []).map((a) => <SelectItem key={a.id} value={a.id}>{a.name}</SelectItem>)}</SelectContent>
          </Select>
        ),
    },
    { accessorKey: "createdAt", header: "Requested", cell: ({ row }) => <span className="text-xs text-muted-foreground">{fmtDate(row.original.createdAt)}</span> },
  ];

  const maxZone = Math.max(...(m?.byZone ?? []).map((z) => z.collected + z.pending), 1);

  return (
    <>
      <PageHeader title="Collections" description="Credit-recovery operations across stores and zones." />
      <div className="grid grid-cols-2 gap-4 md:grid-cols-4">
        <StatCard label="Collected Today" value={inr(m?.collectedToday)} accent="green" loading={metrics.isLoading} />
        <StatCard label="Pending Amount" value={inr(m?.pendingAmount)} accent="gold" loading={metrics.isLoading} hint={`${m?.pendingCount ?? 0} requests`} />
        <StatCard label="Overdue Exposure" value={inr(m?.overdueAmount)} accent="red" loading={metrics.isLoading} />
        <StatCard label="Priority" value={m?.priorityCount ?? 0} accent={m?.priorityCount ? "red" : "slate"} loading={metrics.isLoading} />
      </div>

      {/* Per-zone recovery */}
      {(m?.byZone?.length ?? 0) > 0 && (
        <div>
          <h2 className="mb-2 text-sm font-semibold">Recovery by Zone</h2>
          <div className="grid grid-cols-1 gap-3 sm:grid-cols-2 lg:grid-cols-3">
            {m!.byZone.map((z) => (
              <div key={z.zone} className="rounded-lg border bg-card p-3">
                <div className="mb-1 flex items-center justify-between text-sm"><span className="font-medium">{z.zone}</span><span className="text-muted-foreground">{inr(z.collected + z.pending)}</span></div>
                <div className="flex h-2 overflow-hidden rounded-full bg-muted">
                  <div className="h-full bg-[var(--color-success)]" style={{ width: `${(z.collected / maxZone) * 100}%` }} />
                  <div className="h-full bg-[var(--color-warning)]" style={{ width: `${(z.pending / maxZone) * 100}%` }} />
                </div>
                <p className="mt-1 text-xs text-muted-foreground">{inr(z.collected)} collected · {inr(z.pending)} pending</p>
              </div>
            ))}
          </div>
        </div>
      )}

      {/* Recovery command center: aging + dunning sweep + auto-assign. */}
      <div className="rounded-lg border bg-card p-4">
        <div className="mb-3 flex flex-wrap items-center justify-between gap-2">
          <h2 className="text-sm font-semibold">Recovery command center</h2>
          <div className="flex gap-2">
            <Button size="sm" variant="outline" disabled={autoAssign.isPending}
              onClick={() => autoAssign.mutate(undefined)}>
              {autoAssign.isPending ? <Loader2 className="size-3.5 animate-spin" /> : <UserCheck className="size-3.5" />}
              Auto-assign unassigned
            </Button>
            <Button size="sm" variant="outline" disabled={runDunning.isPending}
              onClick={() => runDunning.mutate(undefined)}>
              {runDunning.isPending ? <Loader2 className="size-3.5 animate-spin" /> : <Zap className="size-3.5" />}
              Run dunning sweep
            </Button>
          </div>
        </div>
        {cc.data && (
          <div className="mb-3 grid grid-cols-2 gap-2 sm:grid-cols-5">
            <MiniStat label="Collected today" value={inr(cc.data.kpis.collectedToday)} />
            <MiniStat label="Pending" value={inr(cc.data.kpis.pendingAmount)} />
            <MiniStat label="Open" value={cc.data.kpis.openCount} />
            <MiniStat label="Disputed" value={cc.data.kpis.disputed} />
            <MiniStat label="Escalated" value={cc.data.kpis.escalated} accent={cc.data.kpis.escalated ? "red" : undefined} />
          </div>
        )}
        <div className="grid grid-cols-2 gap-2 sm:grid-cols-4">
          {(cc.data?.aging ?? []).map((b) => (
            <div key={b.bucket} className={cn("rounded-md border p-2.5", (b.bucket === "61-90" || b.bucket === "90+") && b.count > 0 && "border-[var(--color-danger)]/40")}>
              <p className="text-xs text-muted-foreground">{b.bucket} days</p>
              <p className="text-lg font-semibold tabular-nums">{inr(b.amount)}</p>
              <p className="text-xs text-muted-foreground">{b.count} account{b.count === 1 ? "" : "s"}</p>
            </div>
          ))}
        </div>
      </div>

      <div className="flex flex-wrap items-center gap-2">
        {FILTERS.map((f) => (
          <button key={f.key} onClick={() => setStatus(f.key)} className={cn("rounded-full border px-3.5 py-1.5 text-sm transition-colors", status === f.key ? "border-primary bg-primary text-primary-foreground" : "bg-card hover:bg-accent")}>{f.label}</button>
        ))}
        <div className="ml-auto"><StoreZoneFilter store={store} zone={zone} onStore={setStore} onZone={setZone} /></div>
      </div>

      <DataTable
        columns={columns}
        data={list.data?.rows ?? []}
        loading={list.isLoading}
        error={list.isError ? "Failed to load collections." : null}
        onRetry={() => list.refetch()}
        emptyMessage="No collection requests."
        pageMeta={pageMeta}
        page={page}
        onPageChange={setPage}
      />

      {(m?.agentPerformance?.length ?? 0) > 0 && (
        <div>
          <h2 className="mb-2 text-sm font-semibold">Agent Performance</h2>
          <div className="grid grid-cols-2 gap-3 sm:grid-cols-3 lg:grid-cols-5">
            {m!.agentPerformance.map((a) => (
              <div key={a.agentId} className="rounded-lg border bg-card p-3">
                <p className="truncate text-sm font-medium">{a.name}</p>
                <p className="text-lg font-bold">{inr(a.collected)}</p>
                <p className="text-xs text-muted-foreground">collected</p>
              </div>
            ))}
          </div>
        </div>
      )}
    </>
  );
}

function MiniStat({ label, value, accent }: { label: string; value: string | number; accent?: "red" }) {
  return (
    <div className="rounded-md border p-2.5">
      <p className="text-xs text-muted-foreground">{label}</p>
      <p className={cn("text-lg font-semibold tabular-nums", accent === "red" && "text-[var(--color-danger)]")}>{value}</p>
    </div>
  );
}
