"use client";

import * as React from "react";
import Link from "next/link";
import { useQuery } from "@tanstack/react-query";
import type { ColumnDef } from "@tanstack/react-table";
import { ArrowLeft, Banknote, HandCoins, Loader2, ShieldAlert, Wallet } from "lucide-react";
import { api, useApiMutation } from "@/lib/api/hooks";
import { useStore } from "@/lib/store/store-context";
import { PageHeader } from "@/components/page-header";
import { DataTable } from "@/components/data-table";
import { RequirePerm } from "@/components/permission-gate";
import { StatCard } from "@/components/stat-card";
import { StatusBadge } from "@/components/status-badge";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import { Textarea } from "@/components/ui/textarea";
import {
  Dialog, DialogContent, DialogHeader, DialogTitle, DialogDescription, DialogFooter,
} from "@/components/ui/dialog";
import { inr, fmtDate, titleize } from "@/lib/utils";

interface AgentCashRow {
  agentId: string | null;
  agent: string;
  phone: string;
  amount: number;
  collections: number;
}

interface CashSummary {
  collected: number;
  declared: number;
  verified: number;
  shortfall: number;
  inHand: number;
  pendingDeposits: number;
  byAgent: AgentCashRow[];
}

interface DepositRow {
  id: string;
  agentName: string;
  agentPhone: string;
  amount: number;
  method: string;
  channel: "cash" | "online";
  depositedOn: string;
  reference: string;
  status: string;
  verifiedAmount: number | null;
  verifiedByName: string | null;
  verifiedAt: string | null;
  shortfall: number;
  notes: string;
  collectionCount: number;
  createdAt: string;
}

interface CashResponse {
  summary: CashSummary;
  deposits: DepositRow[];
}

export default function AgentsCashPage() {
  return (
    <RequirePerm perm="delivery.view">
      <AgentsCashInner />
    </RequirePerm>
  );
}

function AgentsCashInner() {
  const { hasPerm } = useStore();
  const canManage = hasPerm("delivery.manage");
  const [verifyTarget, setVerifyTarget] = React.useState<DepositRow | null>(null);
  const [rejectTarget, setRejectTarget] = React.useState<DepositRow | null>(null);

  const q = useQuery({
    queryKey: ["store", "agents", "cash"],
    queryFn: () => api.get<CashResponse>("/store/agents/cash"),
  });

  const summary = q.data?.summary;

  const byAgentColumns: ColumnDef<AgentCashRow, unknown>[] = [
    { header: "Agent", cell: ({ row }) => <span className="font-medium">{row.original.agent}</span> },
    { header: "Phone", cell: ({ row }) => <span className="tabular-nums text-muted-foreground">{row.original.phone || "—"}</span> },
    { header: "Collections", cell: ({ row }) => <span className="tabular-nums">{row.original.collections}</span> },
    { header: "Cash in hand", cell: ({ row }) => <span className="font-semibold">{inr(row.original.amount)}</span> },
  ];

  const depositColumns: ColumnDef<DepositRow, unknown>[] = [
    {
      header: "Agent",
      cell: ({ row }) => (
        <div>
          <div className="font-medium">{row.original.agentName}</div>
          <div className="text-xs text-muted-foreground">{row.original.agentPhone}</div>
        </div>
      ),
    },
    { header: "Amount", cell: ({ row }) => <span className="font-semibold">{inr(row.original.amount)}</span> },
    {
      header: "Via",
      cell: ({ row }) => (
        <div className="text-xs">
          <div className="font-medium">{row.original.channel === "online" ? "Online" : titleize(row.original.method)}</div>
          {row.original.reference && <div className="text-muted-foreground">{row.original.reference}</div>}
        </div>
      ),
    },
    { header: "Deposited on", cell: ({ row }) => <span className="text-xs text-muted-foreground">{fmtDate(row.original.depositedOn)}</span> },
    { header: "Status", cell: ({ row }) => <StatusBadge status={row.original.status} /> },
    {
      header: "Reviewed by",
      cell: ({ row }) => {
        const d = row.original;
        if (d.verifiedAmount == null && !d.verifiedByName) {
          return <span className="text-xs text-muted-foreground">— awaiting count —</span>;
        }
        return (
          <div className="text-xs">
            {d.verifiedAmount != null && (
              <div>
                {inr(d.verifiedAmount)} counted
                {d.shortfall > 0 && (
                  <span className="text-[var(--color-danger)]"> · short {inr(d.shortfall)}</span>
                )}
              </div>
            )}
            {d.verifiedByName && <div className="text-muted-foreground">by {d.verifiedByName}{d.verifiedAt ? ` · ${fmtDate(d.verifiedAt)}` : ""}</div>}
            {d.notes && d.status === "rejected" && (
              <div className="text-muted-foreground">&ldquo;{d.notes}&rdquo;</div>
            )}
          </div>
        );
      },
    },
    {
      header: "", id: "actions",
      cell: ({ row }) => {
        if (!canManage || row.original.status !== "pending") return null;
        return (
          <div className="flex justify-end gap-1.5">
            <Button variant="outline" size="sm" onClick={() => setRejectTarget(row.original)}>
              Reject
            </Button>
            <Button size="sm" onClick={() => setVerifyTarget(row.original)}>
              Verify
            </Button>
          </div>
        );
      },
    },
  ];

  return (
    <div className="space-y-5">
      <PageHeader
        title="Agent Cash"
        description="Cash your own agents have collected, what they're still holding, and their hand-over history."
        actions={
          <Button size="sm" variant="outline" asChild>
            <Link href="/agents">
              <ArrowLeft className="size-4" /> Agents
            </Link>
          </Button>
        }
      />

      <div className="grid grid-cols-2 gap-4 lg:grid-cols-4">
        <StatCard
          label="Collected"
          value={inr(summary?.collected)}
          icon={<HandCoins />}
          accent="teal"
          loading={q.isLoading}
          hint="Total cash your agents have collected"
        />
        <StatCard
          label="Cash in hand"
          value={inr(summary?.inHand)}
          icon={<Wallet />}
          accent={summary && summary.inHand > 0 ? "gold" : "green"}
          loading={q.isLoading}
          hint="Collected but not yet handed over"
        />
        <StatCard
          label="Verified"
          value={inr(summary?.verified)}
          icon={<Banknote />}
          accent="green"
          loading={q.isLoading}
          hint="Counted and confirmed"
        />
        <StatCard
          label="Shortfall"
          value={inr(summary?.shortfall)}
          icon={<ShieldAlert />}
          accent={summary && summary.shortfall > 0 ? "red" : "slate"}
          loading={q.isLoading}
          hint={`${summary?.pendingDeposits ?? 0} deposit(s) awaiting count`}
        />
      </div>

      <Card>
        <CardHeader>
          <CardTitle>Cash in hand, by agent</CardTitle>
        </CardHeader>
        <CardContent className="p-0">
          <DataTable
            columns={byAgentColumns}
            data={summary?.byAgent ?? []}
            loading={q.isLoading}
            error={q.error ? "Couldn't load agent cash." : null}
            onRetry={() => q.refetch()}
            emptyMessage="No agent is holding any uncollected cash right now."
          />
        </CardContent>
      </Card>

      <Card>
        <CardHeader>
          <CardTitle>Hand-over history</CardTitle>
        </CardHeader>
        <CardContent className="p-0">
          <DataTable
            columns={depositColumns}
            data={q.data?.deposits ?? []}
            loading={q.isLoading}
            error={q.error ? "Couldn't load hand-over history." : null}
            onRetry={() => q.refetch()}
            emptyMessage="No cash hand-overs recorded yet."
          />
        </CardContent>
      </Card>

      <VerifyDialog target={verifyTarget} onClose={() => setVerifyTarget(null)} />
      <RejectDialog target={rejectTarget} onClose={() => setRejectTarget(null)} />
    </div>
  );
}

/** Counting in a declared hand-over — defaults the counted amount to what the
 * agent declared; changing it below that amount records a shortfall rather
 * than silently rounding the deposit down. */
function VerifyDialog({ target, onClose }: { target: DepositRow | null; onClose: () => void }) {
  const open = target !== null;
  const [counted, setCounted] = React.useState("");

  React.useEffect(() => {
    if (target) setCounted(String(target.amount));
  }, [target]);

  function close() {
    setCounted("");
    onClose();
  }

  const verify = useApiMutation<void>(
    () => api.post(`/store/agents/cash/deposits/${target?.id}/verify`, { countedAmount: counted }),
    { invalidate: [["store", "agents", "cash"]], successMessage: "Deposit counted in", onDone: close }
  );

  const countedNum = Number(counted);
  const short = target && countedNum < target.amount;

  return (
    <Dialog open={open} onOpenChange={(o) => !o && close()}>
      <DialogContent>
        <DialogHeader>
          <DialogTitle>Verify hand-over</DialogTitle>
          <DialogDescription>
            {target ? `${target.agentName} declared ${inr(target.amount)}` : ""}
          </DialogDescription>
        </DialogHeader>

        <div className="space-y-1.5">
          <Label>Amount actually counted</Label>
          <Input
            type="number"
            inputMode="decimal"
            value={counted}
            onChange={(e) => setCounted(e.target.value)}
          />
          {short && (
            <p className="text-xs text-[var(--color-danger)]">
              This is less than declared — a shortfall of {inr(target.amount - countedNum)} will be recorded against {target.agentName}.
            </p>
          )}
        </div>

        <DialogFooter>
          <Button variant="outline" onClick={close}>Cancel</Button>
          <Button
            onClick={() => verify.mutate()}
            disabled={verify.isPending || counted.trim().length === 0 || Number.isNaN(countedNum) || countedNum < 0}
          >
            {verify.isPending && <Loader2 className="size-4 animate-spin" />}
            {short ? "Record with shortfall" : "Verify"}
          </Button>
        </DialogFooter>
      </DialogContent>
    </Dialog>
  );
}

/** Rejects a declared hand-over (e.g. the money never actually arrived) — the
 * collections it covered go back to "undeposited" rather than vanishing. */
function RejectDialog({ target, onClose }: { target: DepositRow | null; onClose: () => void }) {
  const open = target !== null;
  const [reason, setReason] = React.useState("");

  function close() {
    setReason("");
    onClose();
  }

  const reject = useApiMutation<void>(
    () => api.post(`/store/agents/cash/deposits/${target?.id}/reject`, { reason: reason.trim() }),
    { invalidate: [["store", "agents", "cash"]], successMessage: "Deposit rejected", onDone: close }
  );

  return (
    <Dialog open={open} onOpenChange={(o) => !o && close()}>
      <DialogContent>
        <DialogHeader>
          <DialogTitle>Reject hand-over</DialogTitle>
          <DialogDescription>
            {target ? `${target.agentName} · ${inr(target.amount)}` : ""}
          </DialogDescription>
        </DialogHeader>

        <div className="space-y-1.5">
          <Label>Reason</Label>
          <Textarea
            value={reason}
            onChange={(e) => setReason(e.target.value)}
            placeholder="e.g. Cash never handed over, reference doesn't match…"
            rows={3}
          />
        </div>

        <DialogFooter>
          <Button variant="outline" onClick={close}>Cancel</Button>
          <Button
            variant="destructive"
            onClick={() => reject.mutate()}
            disabled={reject.isPending || reason.trim().length === 0}
          >
            {reject.isPending && <Loader2 className="size-4 animate-spin" />}
            Reject
          </Button>
        </DialogFooter>
      </DialogContent>
    </Dialog>
  );
}
