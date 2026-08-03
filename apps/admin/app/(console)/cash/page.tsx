"use client";

import * as React from "react";
import { keepPreviousData, useQuery, useQueryClient } from "@tanstack/react-query";
import { type ColumnDef } from "@tanstack/react-table";
import {
  AlertTriangle, Banknote, Check, Loader2, Wallet, X,
} from "lucide-react";
import { toast } from "sonner";
import { api } from "@/lib/api/client";
import { ApiError, type PageMeta } from "@/lib/types";
import { PageHeader } from "@/components/page-header";
import { DataTable } from "@/components/data-table";
import { StatusBadge } from "@/components/status-badge";
import { Button } from "@/components/ui/button";
import { Card } from "@/components/ui/card";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import { Textarea } from "@/components/ui/textarea";
import { Tabs, TabsContent, TabsList, TabsTrigger } from "@/components/ui/tabs";
import {
  Dialog, DialogContent, DialogFooter, DialogHeader, DialogTitle,
} from "@/components/ui/dialog";
import {
  Select, SelectContent, SelectItem, SelectTrigger, SelectValue,
} from "@/components/ui/select";
import { inr, titleize } from "@/lib/utils";

interface Deposit {
  id: string;
  agentName: string;
  agentPhone: string;
  amount: number | string;
  method: string;
  depositedOn: string;
  reference: string;
  status: string;
  verifiedAmount: number | string | null;
  verifiedByName: string | null;
  verifiedAt: string | null;
  shortfall: number | string;
  notes: string;
  collectionCount: number;
  createdAt: string;
}
interface DepositCollection {
  id: string; customerName: string; collectedAmount: number | string;
  collectedAt: string;
}
interface DepositDetail extends Deposit { collections: DepositCollection[] }
interface AgentCash {
  agentId: string | null; agent: string; phone: string;
  amount: number | string; collections: number;
}
interface Reconciliation {
  collected: number | string;
  declared: number | string;
  verified: number | string;
  shortfall: number | string;
  inHand: number | string;
  pendingDeposits: number;
  byAgent: AgentCash[];
}

const ANY = "__any__";
const STATUSES = ["pending", "verified", "short", "rejected"];

export default function CashPage() {
  const [tab, setTab] = React.useState("deposits");
  const [from, setFrom] = React.useState("");
  const [to, setTo] = React.useState("");

  const recon = useQuery({
    queryKey: ["admin", "cash", "reconciliation", from, to],
    queryFn: () => api.get<Reconciliation>("/admin/cash/reconciliation", {
      from: from || undefined, to: to || undefined,
    }),
  });
  const r = recon.data;

  return (
    <>
      <PageHeader
        title="Cash Book"
        description="Cash collected in the field, handed over, and counted — every rupee traceable from the customer to the bank."
      />

      <div className="flex flex-wrap items-end gap-2">
        <div className="space-y-1">
          <Label className="text-xs text-muted-foreground">From</Label>
          <Input type="date" value={from} onChange={(e) => setFrom(e.target.value)} className="w-[150px]" />
        </div>
        <div className="space-y-1">
          <Label className="text-xs text-muted-foreground">To</Label>
          <Input type="date" value={to} onChange={(e) => setTo(e.target.value)} className="w-[150px]" />
        </div>
      </div>

      <div className="grid gap-3 sm:grid-cols-2 lg:grid-cols-4">
        <Stat label="Collected" hint="Cash taken from customers"
              value={r ? inr(Number(r.collected)) : "—"}
              icon={<Banknote className="size-4 text-muted-foreground" />}
              loading={recon.isLoading} />
        <Stat label="Counted in" hint="Verified by finance"
              value={r ? inr(Number(r.verified)) : "—"}
              icon={<Check className="size-4 text-[var(--color-success)]" />}
              loading={recon.isLoading} />
        <Stat label="Still with agents" hint="Collected but not yet handed over"
              value={r ? inr(Number(r.inHand)) : "—"}
              icon={<Wallet className="size-4 text-[var(--color-warning)]" />}
              loading={recon.isLoading}
              tone={r && Number(r.inHand) > 0 ? "warn" : undefined} />
        <Stat label="Shortfall" hint="Declared more than was counted"
              value={r ? inr(Number(r.shortfall)) : "—"}
              icon={<AlertTriangle className="size-4 text-destructive" />}
              loading={recon.isLoading}
              tone={r && Number(r.shortfall) > 0 ? "bad" : undefined} />
      </div>

      <Tabs value={tab} onValueChange={setTab}>
        <TabsList>
          <TabsTrigger value="deposits">
            Deposits
            {(r?.pendingDeposits ?? 0) > 0 && (
              <span className="ml-2 rounded-full bg-[color-mix(in_oklab,var(--color-warning)_18%,transparent)] px-1.5 text-xs text-[var(--color-warning)]">
                {r!.pendingDeposits}
              </span>
            )}
          </TabsTrigger>
          <TabsTrigger value="inhand">Cash with agents</TabsTrigger>
        </TabsList>

        <TabsContent value="deposits">
          <DepositsTab from={from} to={to} />
        </TabsContent>
        <TabsContent value="inhand">
          <InHandTab rows={r?.byAgent ?? []} loading={recon.isLoading} />
        </TabsContent>
      </Tabs>
    </>
  );
}

function Stat({ label, value, hint, icon, loading, tone }: {
  label: string; value: string; hint: string; icon: React.ReactNode;
  loading: boolean; tone?: "warn" | "bad";
}) {
  const color = tone === "bad" ? "text-destructive"
    : tone === "warn" ? "text-[var(--color-warning)]" : "";
  return (
    <Card className="p-4">
      <div className="flex items-center gap-2 text-sm text-muted-foreground">{icon} {label}</div>
      <div className={`mt-1 text-2xl font-semibold tabular-nums ${color}`}>
        {loading ? <Loader2 className="size-5 animate-spin text-muted-foreground" /> : value}
      </div>
      <p className="mt-0.5 text-xs text-muted-foreground">{hint}</p>
    </Card>
  );
}

function DepositsTab({ from, to }: { from: string; to: string }) {
  const [status, setStatus] = React.useState("pending");
  const [page, setPage] = React.useState(1);
  const [openId, setOpenId] = React.useState<string | null>(null);

  const query = useQuery({
    queryKey: ["admin", "cash", "deposits", status, from, to, page],
    queryFn: () => api.getPaged<Deposit>("/admin/cash/deposits", {
      status: status || undefined, from: from || undefined,
      to: to || undefined, page,
    }),
    placeholderData: keepPreviousData,
  });

  const columns: ColumnDef<Deposit, unknown>[] = [
    {
      accessorKey: "depositedOn", header: "Date",
      cell: ({ row }) => (
        <span className="whitespace-nowrap text-xs">
          {new Date(row.original.depositedOn).toLocaleDateString("en-IN", {
            day: "2-digit", month: "short", year: "numeric",
          })}
        </span>
      ),
    },
    {
      accessorKey: "agentName", header: "Agent",
      cell: ({ row }) => (
        <div className="flex flex-col">
          <span className="font-medium">{row.original.agentName}</span>
          <span className="text-xs text-muted-foreground">{row.original.agentPhone}</span>
        </div>
      ),
    },
    {
      accessorKey: "amount", header: "Declared",
      cell: ({ row }) => <span className="tabular-nums font-medium">{inr(Number(row.original.amount))}</span>,
    },
    {
      accessorKey: "verifiedAmount", header: "Counted",
      cell: ({ row }) => (
        <span className="tabular-nums">
          {row.original.verifiedAmount == null ? "—" : inr(Number(row.original.verifiedAmount))}
        </span>
      ),
    },
    {
      accessorKey: "shortfall", header: "Short by",
      cell: ({ row }) => {
        const s = Number(row.original.shortfall);
        return s > 0
          ? <span className="tabular-nums font-medium text-destructive">{inr(s)}</span>
          : <span className="text-xs text-muted-foreground">—</span>;
      },
    },
    { accessorKey: "method", header: "Via", cell: ({ row }) => titleize(row.original.method) },
    {
      accessorKey: "collectionCount", header: "Collections",
      cell: ({ row }) => <span className="tabular-nums">{row.original.collectionCount}</span>,
    },
    { accessorKey: "status", header: "Status", cell: ({ row }) => <StatusBadge status={row.original.status} /> },
  ];

  return (
    <>
      <div className="mb-3">
        <Select value={status || ANY} onValueChange={(v) => { setStatus(v === ANY ? "" : v); setPage(1); }}>
          <SelectTrigger className="w-[190px]"><SelectValue /></SelectTrigger>
          <SelectContent>
            <SelectItem value={ANY}>All deposits</SelectItem>
            {STATUSES.map((s) => (
              <SelectItem key={s} value={s}>
                {s === "pending" ? "Awaiting count" : titleize(s)}
              </SelectItem>
            ))}
          </SelectContent>
        </Select>
      </div>

      <DataTable
        columns={columns}
        data={query.data?.rows ?? []}
        loading={query.isLoading}
        error={query.isError ? "Failed to load deposits." : null}
        onRetry={() => query.refetch()}
        emptyMessage={status === "pending" ? "Nothing waiting to be counted." : "No deposits match this filter."}
        pageMeta={query.data?.meta as PageMeta | undefined}
        page={page}
        onPageChange={setPage}
        onRowClick={(row) => setOpenId(row.id)}
      />

      {openId && <DepositDialog depositId={openId} onClose={() => setOpenId(null)} />}
    </>
  );
}

function InHandTab({ rows, loading }: { rows: AgentCash[]; loading: boolean }) {
  const columns: ColumnDef<AgentCash, unknown>[] = [
    { accessorKey: "agent", header: "Agent" },
    { accessorKey: "phone", header: "Phone", cell: ({ row }) => <span className="text-xs text-muted-foreground">{row.original.phone || "—"}</span> },
    {
      accessorKey: "amount", header: "Holding",
      cell: ({ row }) => <span className="tabular-nums font-medium">{inr(Number(row.original.amount))}</span>,
    },
    { accessorKey: "collections", header: "Collections", cell: ({ row }) => <span className="tabular-nums">{row.original.collections}</span> },
  ];
  return (
    <>
      <p className="mb-3 text-sm text-muted-foreground">
        Cash an agent has taken from customers but not yet handed over. This is your
        live exposure in the field.
      </p>
      <DataTable
        columns={columns} data={rows} loading={loading}
        emptyMessage="Every collection has been handed over."
      />
    </>
  );
}

/** Count a deposit in, or reject it. */
function DepositDialog({ depositId, onClose }: { depositId: string; onClose: () => void }) {
  const detail = useQuery({
    queryKey: ["admin", "cash", "deposit", depositId],
    queryFn: () => api.get<DepositDetail>(`/admin/cash/deposits/${depositId}`),
  });
  return (
    <Dialog open onOpenChange={(o) => !o && onClose()}>
      <DialogContent className="max-h-[90vh] max-w-lg overflow-y-auto">
        {detail.isLoading && (
          <>
            <DialogHeader><DialogTitle>Deposit</DialogTitle></DialogHeader>
            <div className="grid place-items-center py-10">
              <Loader2 className="size-5 animate-spin text-muted-foreground" />
            </div>
          </>
        )}
        {detail.isError && (
          <>
            <DialogHeader><DialogTitle>Deposit</DialogTitle></DialogHeader>
            <p className="py-6 text-center text-sm text-destructive">Failed to load.</p>
            <DialogFooter><Button variant="outline" onClick={onClose}>Close</Button></DialogFooter>
          </>
        )}
        {detail.data && <DepositBody d={detail.data} onClose={onClose} />}
      </DialogContent>
    </Dialog>
  );
}

function DepositBody({ d, onClose }: { d: DepositDetail; onClose: () => void }) {
  const qc = useQueryClient();
  // Seeded with the declared amount — the common case is that it matches.
  const [counted, setCounted] = React.useState(String(Number(d.amount)));
  const [notes, setNotes] = React.useState("");
  const [reason, setReason] = React.useState("");
  const [mode, setMode] = React.useState<"idle" | "reject">("idle");
  const [busy, setBusy] = React.useState(false);

  const pending = d.status === "pending";
  const diff = Number(d.amount) - Number(counted || 0);

  async function act(action: "verify" | "reject") {
    setBusy(true);
    try {
      await api.post(`/admin/cash/deposits/${d.id}/${action}`,
        action === "verify" ? { countedAmount: Number(counted), notes } : { reason });
      toast.success(action === "verify"
        ? (diff > 0 ? "Counted in — shortfall recorded." : "Deposit counted in.")
        : "Deposit rejected; the cash is back against the agent.");
      qc.invalidateQueries({ queryKey: ["admin", "cash"] });
      onClose();
    } catch (e) {
      toast.error(e instanceof ApiError ? e.message : "Could not save.");
    } finally {
      setBusy(false);
    }
  }

  return (
    <>
      <DialogHeader>
        <DialogTitle className="flex items-center gap-2">
          Deposit from {d.agentName}
          <StatusBadge status={d.status} />
        </DialogTitle>
      </DialogHeader>

      <div className="space-y-4">
        <div className="divide-y rounded-md border">
          <Row label="Declared" value={inr(Number(d.amount))} />
          <Row label="Handed over via" value={titleize(d.method)} />
          <Row label="On" value={new Date(d.depositedOn).toLocaleDateString("en-IN")} />
          {d.reference && <Row label="Reference" value={d.reference} />}
          {d.verifiedAmount != null && <Row label="Counted" value={inr(Number(d.verifiedAmount))} />}
          {Number(d.shortfall) > 0 && <Row label="Short by" value={inr(Number(d.shortfall))} />}
          {d.verifiedByName && <Row label="Reviewed by" value={d.verifiedByName} />}
          {d.notes && <Row label="Note" value={d.notes} />}
        </div>

        <div>
          <p className="mb-2 text-xs font-medium uppercase tracking-wide text-muted-foreground">
            Covers {d.collections.length} collection{d.collections.length === 1 ? "" : "s"}
          </p>
          {d.collections.length === 0 ? (
            <p className="text-sm text-muted-foreground">
              No collections were attached — this is a bulk hand-over.
            </p>
          ) : (
            <div className="divide-y rounded-md border">
              {d.collections.map((c) => (
                <Row key={c.id} label={c.customerName || "—"}
                     value={inr(Number(c.collectedAmount))} />
              ))}
            </div>
          )}
        </div>

        {pending && mode === "idle" && (
          <div className="space-y-3 rounded-md border p-3">
            <div className="space-y-1.5">
              <Label className="text-xs text-muted-foreground">
                Amount actually counted (₹)
              </Label>
              <Input type="number" min={0} value={counted}
                     onChange={(e) => setCounted(e.target.value)} />
              {diff > 0 && (
                <p className="text-xs text-destructive">
                  {inr(diff)} short of what was declared. This will be recorded
                  against {d.agentName}.
                </p>
              )}
            </div>
            <div className="space-y-1.5">
              <Label className="text-xs text-muted-foreground">Note (optional)</Label>
              <Textarea rows={2} value={notes} maxLength={300}
                        onChange={(e) => setNotes(e.target.value)} />
            </div>
          </div>
        )}

        {pending && mode === "reject" && (
          <div className="space-y-1.5 rounded-md border p-3">
            <Label className="text-xs text-muted-foreground">
              Why is this being rejected?
            </Label>
            <Textarea rows={2} value={reason} maxLength={300}
                      onChange={(e) => setReason(e.target.value)}
                      placeholder="e.g. The money never reached the bank." />
            <p className="text-xs text-muted-foreground">
              The collections go back to showing as cash still with the agent.
            </p>
          </div>
        )}
      </div>

      <DialogFooter className="gap-2">
        {!pending ? (
          <Button variant="outline" onClick={onClose}>Close</Button>
        ) : mode === "reject" ? (
          <>
            <Button variant="outline" onClick={() => setMode("idle")} disabled={busy}>Back</Button>
            <Button variant="destructive" disabled={busy || !reason.trim()}
                    onClick={() => act("reject")}>
              {busy && <Loader2 className="size-4 animate-spin" />} Confirm rejection
            </Button>
          </>
        ) : (
          <>
            <Button variant="ghost" disabled={busy}
                    className="mr-auto text-destructive hover:text-destructive"
                    onClick={() => setMode("reject")}>
              <X className="size-4" /> Reject
            </Button>
            <Button variant="outline" onClick={onClose} disabled={busy}>Cancel</Button>
            <Button disabled={busy || counted === ""} onClick={() => act("verify")}>
              {busy ? <Loader2 className="size-4 animate-spin" /> : <Check className="size-4" />}
              Count in
            </Button>
          </>
        )}
      </DialogFooter>
    </>
  );
}

function Row({ label, value }: { label: string; value: string }) {
  return (
    <div className="flex items-start justify-between gap-4 px-3 py-2 text-sm">
      <span className="text-muted-foreground">{label}</span>
      <span className="text-right font-medium">{value}</span>
    </div>
  );
}
