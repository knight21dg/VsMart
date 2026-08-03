"use client";

import * as React from "react";
import { useQuery } from "@tanstack/react-query";
import type { ColumnDef } from "@tanstack/react-table";
import { Loader2 } from "lucide-react";
import { api, useApiMutation } from "@/lib/api/hooks";
import { useStore } from "@/lib/store/store-context";
import { PageHeader } from "@/components/page-header";
import { DataTable } from "@/components/data-table";
import { RequirePerm } from "@/components/permission-gate";
import { StatusBadge } from "@/components/status-badge";
import { Badge } from "@/components/ui/badge";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from "@/components/ui/select";
import {
  Dialog, DialogContent, DialogHeader, DialogTitle, DialogDescription, DialogFooter,
} from "@/components/ui/dialog";
import { Skeleton } from "@/components/ui/skeleton";
import { inr, fmtDate, titleize } from "@/lib/utils";

interface CollectionRow {
  id: string; customerId: string; customer: string | null; phone: string | null;
  amount: number; collectedAmount: number; status: string; agent: string | null;
  method: string | null; reference: string | null; createdAt: string; collectedAt: string | null;
  isPriority?: boolean; escalated?: boolean;
}

interface CollectionDetail extends CollectionRow {
  agentPhone: string | null;
  attemptNo: number;
  otpVerified: boolean;
  failureReason: string;
  disputeNote: string;
  timeline: {
    createdAt: string; assignedAt: string | null; acceptedAt: string | null;
    enRouteAt: string | null; reachedAt: string | null; failedAt: string | null;
    collectedAt: string | null;
  };
  assignmentHistory: {
    action: string; agent: string | null; by: string | null; reason: string; at: string;
  }[];
}

const METHODS = ["cash", "upi", "card", "netbanking"] as const;

export default function CollectionsPage() {
  return (
    <RequirePerm perm="collections.view">
      <CollectionsInner />
    </RequirePerm>
  );
}

function CollectionsInner() {
  const { hasPerm } = useStore();
  const canManage = hasPerm("collections.manage");
  const [filter, setFilter] = React.useState("pending");
  const [target, setTarget] = React.useState<CollectionRow | null>(null);
  const [retryTarget, setRetryTarget] = React.useState<CollectionRow | null>(null);
  const [detailId, setDetailId] = React.useState<string | null>(null);

  const q = useQuery({
    queryKey: ["store", "collections", filter],
    queryFn: () => api.get<CollectionRow[]>("/store/collections", filter === "all" ? {} : { status: filter }),
  });
  // Reused for the retry dialog's agent picker — same agent pool delivery
  // reassignment already draws from.
  const agentsQ = useQuery({
    queryKey: ["store", "delivery", "agents"],
    queryFn: () => api.get<{ id: string; name: string; onDuty: boolean }[]>("/store/delivery/agents"),
  });

  const columns: ColumnDef<CollectionRow, unknown>[] = [
    { header: "Customer", cell: ({ row }) => (
        <div>
          <div className="flex items-center gap-1.5 font-medium">
            {row.original.customer ?? "—"}
            {row.original.isPriority && <Badge variant="outline" className="text-[10px]">Priority</Badge>}
            {row.original.escalated && <Badge variant="destructive" className="text-[10px]">Escalated</Badge>}
          </div>
          <div className="text-xs text-muted-foreground">{row.original.phone}</div>
        </div>
      ) },
    { header: "Amount", cell: ({ row }) => <span className="font-semibold">{inr(row.original.amount)}</span> },
    { header: "Status", cell: ({ row }) => <StatusBadge status={row.original.status} /> },
    {
      header: "Settled",
      cell: ({ row }) =>
        row.original.method ? (
          <div className="text-xs">
            <div className="font-medium">{titleize(row.original.method)}</div>
            {row.original.reference && !row.original.reference.startsWith("cash_") && (
              <div className="text-muted-foreground">{row.original.reference}</div>
            )}
          </div>
        ) : <span className="text-xs text-muted-foreground">—</span>,
    },
    { header: "Agent", cell: ({ row }) => <span className="text-sm text-muted-foreground">{row.original.agent ?? "—"}</span> },
    { header: "Raised", cell: ({ row }) => <span className="text-xs text-muted-foreground">{fmtDate(row.original.createdAt)}</span> },
    {
      header: "", id: "actions",
      cell: ({ row }) => {
        if (!canManage || row.original.status === "collected") return null;
        return (
          <div className="flex justify-end gap-1.5">
            {row.original.status === "failed" && (
              <Button variant="outline" size="sm"
                onClick={(e) => { e.stopPropagation(); setRetryTarget(row.original); }}>
                Retry
              </Button>
            )}
            <Button variant="outline" size="sm"
              onClick={(e) => { e.stopPropagation(); setTarget(row.original); }}>
              Collect
            </Button>
          </div>
        );
      },
    },
  ];

  return (
    <div className="space-y-5">
      <PageHeader title="Collections" description="Credit recovery queue for your store's customers." />
      <OverdueCredit canManage={canManage} />
      <DataTable
        columns={columns}
        data={q.data ?? []}
        loading={q.isLoading}
        error={q.error ? "Couldn't load collections." : null}
        onRetry={() => q.refetch()}
        onRowClick={(row) => setDetailId(row.id)}
        emptyMessage="No collections in this view."
        toolbar={
          <div className="flex gap-2">
            {["pending", "failed", "collected", "all"].map((s) => (
              <button key={s} onClick={() => setFilter(s)}
                className={`rounded-full px-3 py-1 text-xs font-medium capitalize transition-colors ${filter === s ? "bg-primary text-primary-foreground" : "bg-muted text-muted-foreground hover:bg-accent"}`}>
                {s}
              </button>
            ))}
          </div>
        }
      />
      {retryTarget && (
        <RetryDialog
          row={retryTarget}
          agents={agentsQ.data ?? []}
          onClose={() => setRetryTarget(null)}
        />
      )}
      <CollectDialog target={target} onClose={() => setTarget(null)} />
      <CollectionDetailDialog id={detailId} onClose={() => setDetailId(null)} />
    </div>
  );
}

function CollectDialog({ target, onClose }: { target: CollectionRow | null; onClose: () => void }) {
  const open = target !== null;
  const [method, setMethod] = React.useState<(typeof METHODS)[number]>("cash");
  const [reference, setReference] = React.useState("");

  function close() {
    setMethod("cash");
    setReference("");
    onClose();
  }

  const collect = useApiMutation<void>(
    () => api.post(`/store/collections/${target?.id}/collect`, { method, reference: reference.trim() }),
    { invalidate: [["store", "collections"]], successMessage: "Collection recorded", onDone: close }
  );

  const needsRef = method !== "cash";

  return (
    <Dialog open={open} onOpenChange={(o) => !o && close()}>
      <DialogContent>
        <DialogHeader>
          <DialogTitle>Record collection</DialogTitle>
          <DialogDescription>
            {target ? `${target.customer ?? target.phone} · ${inr(target.amount)}` : ""}
          </DialogDescription>
        </DialogHeader>

        <div className="space-y-4">
          <div className="space-y-1.5">
            <Label>Payment method</Label>
            <Select value={method} onValueChange={(v) => setMethod(v as (typeof METHODS)[number])}>
              <SelectTrigger><SelectValue /></SelectTrigger>
              <SelectContent>
                {METHODS.map((m) => <SelectItem key={m} value={m}>{titleize(m)}</SelectItem>)}
              </SelectContent>
            </Select>
          </div>
          <div className="space-y-1.5">
            <Label>{needsRef ? "Reference / txn id" : "Reference (optional)"}</Label>
            <Input
              value={reference}
              onChange={(e) => setReference(e.target.value)}
              placeholder={needsRef ? "e.g. UPI txn / receipt no." : "Optional receipt no."}
            />
          </div>
        </div>

        <DialogFooter>
          <Button variant="outline" onClick={close}>Cancel</Button>
          <Button
            onClick={() => collect.mutate()}
            disabled={collect.isPending || (needsRef && reference.trim().length === 0)}
          >
            {collect.isPending && <Loader2 className="size-4 animate-spin" />}
            Record {target ? inr(target.amount) : ""}
          </Button>
        </DialogFooter>
      </DialogContent>
    </Dialog>
  );
}

function RetryDialog({
  row, agents, onClose,
}: { row: CollectionRow; agents: { id: string; name: string; onDuty: boolean }[]; onClose: () => void }) {
  const [agentId, setAgentId] = React.useState("");
  const m = useApiMutation<void>(
    () => api.post(`/store/collections/${row.id}/reassign`, { agentId }),
    { invalidate: [["store", "collections"]], successMessage: "Sent to a new agent", onDone: onClose }
  );
  return (
    <Dialog open onOpenChange={(o) => !o && onClose()}>
      <DialogContent className="max-w-md">
        <DialogHeader>
          <DialogTitle>Retry collection — {row.customer || row.phone}</DialogTitle>
          <DialogDescription>{inr(row.amount)} · previous attempt failed</DialogDescription>
        </DialogHeader>
        <Select value={agentId} onValueChange={setAgentId}>
          <SelectTrigger><SelectValue placeholder="Pick an agent" /></SelectTrigger>
          <SelectContent>
            {agents.map((a) => (
              <SelectItem key={a.id} value={a.id}>
                {a.name}{!a.onDuty && " (off duty)"}
              </SelectItem>
            ))}
          </SelectContent>
        </Select>
        <DialogFooter>
          <Button variant="outline" onClick={onClose} disabled={m.isPending}>Cancel</Button>
          <Button onClick={() => m.mutate()} disabled={m.isPending || !agentId}>
            {m.isPending && <Loader2 className="size-4 animate-spin" />} Retry
          </Button>
        </DialogFooter>
      </DialogContent>
    </Dialog>
  );
}


interface OverdueRow {
  statementId: number;
  customerId: string;
  customer: string;
  phone: string;
  periodEnd: string;   // billing-cycle close date
  dueDate: string;     // payment end date
  daysOverdue: number;
  outstanding: number;
  status: string;
  collectionStatus: string;
  collectionAgent: string;
}

interface OverdueAgent { id: string; name: string; onDuty: boolean }

/** Customers with unpaid credit past (or approaching) the due date — the
 *  store's dunning book, with one-tap auto/manual agent assignment. */
function OverdueCredit({ canManage }: { canManage: boolean }) {
  const q = useQuery({
    queryKey: ["store", "credit", "overdue"],
    queryFn: () => api.get<OverdueRow[]>("/store/credit/overdue"),
  });
  const agentsQ = useQuery({
    queryKey: ["store", "delivery", "agents"],
    queryFn: () => api.get<OverdueAgent[]>("/store/delivery/agents"),
  });
  const assign = useApiMutation(
    ({ statementId, agentId }: { statementId: number; agentId?: string }) =>
      api.post("/store/credit/overdue/assign", { statementId, agentId }),
    {
      invalidate: [["store", "credit", "overdue"], ["store", "collections"]],
      successMessage: "Collection assigned",
    }
  );

  const rows = q.data ?? [];
  // Only hide the section when the API genuinely reported nobody overdue. This
  // used to return before the DataTable below, which made its `error` prop and
  // `emptyMessage` unreachable — a failing endpoint rendered as a clean dunning
  // book, so a broken API looked exactly like "no overdue customers".
  if (!q.isLoading && !q.error && rows.length === 0) return null;

  const columns: ColumnDef<OverdueRow, unknown>[] = [
    { header: "Customer", cell: ({ row }) => (
        <div><div className="font-medium">{row.original.customer || "—"}</div>
        <div className="text-xs text-muted-foreground">{row.original.phone}</div></div>) },
    { header: "Outstanding", cell: ({ row }) => (
        <span className="font-semibold">{inr(row.original.outstanding)}</span>) },
    { header: "Cycle closed", cell: ({ row }) => (
        <span className="text-xs text-muted-foreground">{fmtDate(row.original.periodEnd)}</span>) },
    { header: "Due date", cell: ({ row }) => (
        <div className="text-xs">
          <div>{fmtDate(row.original.dueDate)}</div>
          {row.original.daysOverdue > 0 && (
            <div className="font-medium text-[var(--color-danger)]">
              {row.original.daysOverdue}d overdue
            </div>
          )}
        </div>) },
    { header: "Status", cell: ({ row }) => <StatusBadge status={row.original.status} /> },
    { header: "Collection", cell: ({ row }) =>
        row.original.collectionStatus ? (
          <div className="text-xs">
            <StatusBadge status={row.original.collectionStatus} />
            {row.original.collectionAgent && (
              <div className="text-muted-foreground">{row.original.collectionAgent}</div>
            )}
          </div>
        ) : <span className="text-xs text-muted-foreground">—</span> },
    { header: "", id: "assign",
      cell: ({ row }) => {
        if (!canManage || row.original.collectionStatus) return null;
        return (
          <div className="flex items-center gap-1.5">
            <Button variant="outline" size="sm" disabled={assign.isPending}
              onClick={() => assign.mutate({ statementId: row.original.statementId })}>
              Auto-assign
            </Button>
            <Select onValueChange={(agentId) =>
                assign.mutate({ statementId: row.original.statementId, agentId })}>
              <SelectTrigger className="h-8 w-[130px] text-xs">
                <SelectValue placeholder="Pick agent…" />
              </SelectTrigger>
              <SelectContent>
                {(agentsQ.data ?? []).map((a) => (
                  <SelectItem key={a.id} value={a.id}>{a.name}</SelectItem>
                ))}
              </SelectContent>
            </Select>
          </div>
        );
      } },
  ];

  return (
    <DataTable
      columns={columns}
      data={rows}
      loading={q.isLoading}
      error={q.error ? "Couldn't load overdue credit." : null}
      onRetry={() => q.refetch()}
      emptyMessage="Nobody is overdue."
      toolbar={<span className="text-sm font-semibold">Overdue credit</span>}
    />
  );
}

const TIMELINE_STEPS: { key: keyof CollectionDetail["timeline"]; label: string }[] = [
  { key: "createdAt", label: "Requested" },
  { key: "assignedAt", label: "Assigned" },
  { key: "acceptedAt", label: "Accepted" },
  { key: "enRouteAt", label: "En route" },
  { key: "reachedAt", label: "Reached" },
  { key: "collectedAt", label: "Collected" },
];

const HISTORY_ACTION_LABEL: Record<string, string> = {
  auto_assigned: "Auto-assigned",
  manual_assigned: "Manually assigned",
  reassigned: "Reassigned",
  accepted: "Accepted",
  rejected: "Rejected",
};

/** Row-click drill-down — the collections table used to be a flat list with
 *  no way to see WHY something is stuck or WHO handled it short of a DB
 *  query: full timeline, OTP/dispute state, and the append-only assignment
 *  history (auto/manual assign, reassigns, accept/reject). */
function CollectionDetailDialog({ id, onClose }: { id: string | null; onClose: () => void }) {
  const open = id !== null;
  const q = useQuery({
    queryKey: ["store", "collections", "detail", id],
    queryFn: () => api.get<CollectionDetail>(`/store/collections/${id}`),
    enabled: open,
  });
  const d = q.data;

  return (
    <Dialog open={open} onOpenChange={(o) => !o && onClose()}>
      <DialogContent className="max-w-lg">
        <DialogHeader>
          <DialogTitle>Collection detail</DialogTitle>
          <DialogDescription>
            {d ? `${d.customer || d.phone} · ${inr(d.amount)}` : "Loading…"}
          </DialogDescription>
        </DialogHeader>

        {q.isLoading && (
          <div className="space-y-2">
            <Skeleton className="h-4 w-full" />
            <Skeleton className="h-4 w-3/4" />
            <Skeleton className="h-4 w-1/2" />
          </div>
        )}
        {q.error && <p className="text-sm text-destructive">Couldn&apos;t load this collection.</p>}

        {d && (
          <div className="space-y-5">
            <div className="flex flex-wrap items-center gap-1.5">
              <StatusBadge status={d.status} />
              {d.isPriority && <Badge variant="outline">Priority</Badge>}
              {d.escalated && <Badge variant="destructive">Escalated</Badge>}
              {d.otpVerified && <Badge variant="success">OTP verified</Badge>}
              {d.attemptNo > 1 && <Badge variant="secondary">Attempt {d.attemptNo}</Badge>}
            </div>

            <div className="grid grid-cols-2 gap-x-4 gap-y-2 text-sm">
              <div><span className="text-muted-foreground">Agent</span><div className="font-medium">{d.agent ?? "— unassigned —"}</div></div>
              <div><span className="text-muted-foreground">Agent phone</span><div className="font-medium">{d.agentPhone ?? "—"}</div></div>
              <div><span className="text-muted-foreground">Amount due</span><div className="font-medium">{inr(d.amount)}</div></div>
              <div><span className="text-muted-foreground">Collected</span><div className="font-medium">{inr(d.collectedAmount)}</div></div>
              {d.method && (
                <div><span className="text-muted-foreground">Method</span><div className="font-medium">{titleize(d.method)}</div></div>
              )}
              {d.reference && !d.reference.startsWith("cash_") && (
                <div><span className="text-muted-foreground">Reference</span><div className="font-medium">{d.reference}</div></div>
              )}
            </div>

            {(d.failureReason || d.disputeNote) && (
              <div className="rounded-md border border-destructive/30 bg-destructive/5 p-2.5 text-xs">
                {d.failureReason && <div><span className="font-medium">Failure: </span>{titleize(d.failureReason)}</div>}
                {d.disputeNote && <div><span className="font-medium">Dispute: </span>{d.disputeNote}</div>}
              </div>
            )}

            <div>
              <p className="mb-2 text-xs font-semibold uppercase text-muted-foreground">Timeline</p>
              <ul className="space-y-1.5 text-sm">
                {TIMELINE_STEPS.map((step) => {
                  const at = d.timeline[step.key];
                  return (
                    <li key={step.key} className="flex items-center justify-between">
                      <span className={at ? "font-medium" : "text-muted-foreground"}>{step.label}</span>
                      <span className="text-xs text-muted-foreground">{at ? fmtDate(at, true) : "—"}</span>
                    </li>
                  );
                })}
              </ul>
            </div>

            {d.assignmentHistory.length > 0 && (
              <div>
                <p className="mb-2 text-xs font-semibold uppercase text-muted-foreground">Assignment history</p>
                <ul className="space-y-2 text-sm">
                  {d.assignmentHistory.map((h, i) => (
                    <li key={i} className="border-l-2 border-muted pl-3">
                      <div className="font-medium">
                        {HISTORY_ACTION_LABEL[h.action] ?? titleize(h.action)}
                        {h.agent && <> — {h.agent}</>}
                      </div>
                      <div className="text-xs text-muted-foreground">
                        {fmtDate(h.at, true)}
                        {h.by && <> · by {h.by}</>}
                        {h.reason && <> · {h.reason}</>}
                      </div>
                    </li>
                  ))}
                </ul>
              </div>
            )}
          </div>
        )}
      </DialogContent>
    </Dialog>
  );
}
