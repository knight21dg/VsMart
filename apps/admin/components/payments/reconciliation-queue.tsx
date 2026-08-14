"use client";

import * as React from "react";
import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";
import { AlertTriangle, Loader2, PackageX, ShieldCheck } from "lucide-react";
import { toast } from "sonner";
import { api } from "@/lib/api/client";
import { ApiError } from "@/lib/types";
import { Card } from "@/components/ui/card";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import { Badge } from "@/components/ui/badge";
import {
  Dialog, DialogContent, DialogDescription, DialogFooter, DialogHeader, DialogTitle,
} from "@/components/ui/dialog";
import { LoadingState, ErrorState } from "@/components/states";
import { inr, cn } from "@/lib/utils";

interface Row {
  id: number;
  amount: number;
  status: string;
  method: string;
  gateway: string;
  gatewayOrderId: string;
  gatewayPaymentId: string;
  customer: string;
  customerPhone: string;
  createdAt: string;
  ageMinutes: number;
  attempts: number;
  lastCheckedAt: string | null;
  lastGatewaySaid: string;
  orderCode: string | null;
  orderStatus: string | null;
  stockHeld: boolean;
  /** Capture on a cancelled order → the capture is recorded, then refunded. */
  refundOnCapture: boolean;
}
interface Queue { payments: Row[]; total: number; note: string }
interface Resolution {
  id: number; status: string; applied: boolean; alreadyFinal: boolean;
  orderCode: string | null; orderStatus: string | null;
  orderPaymentStatus: string | null; message: string;
}

function age(mins: number) {
  if (mins < 60) return `${mins}m`;
  const h = Math.floor(mins / 60);
  return h < 24 ? `${h}h` : `${Math.floor(h / 24)}d`;
}

/**
 * Payments the gateway could not settle for us.
 *
 * Every automated path has already run on these rows, so the only thing that can
 * resolve them is someone reading the provider's dashboard. The UI is built around
 * that: it shows what we asked and what came back, and the action names the fact
 * being asserted ("Confirm Captured") rather than the outcome someone wants
 * ("Mark Paid"). Clearing the queue is not the goal; recording the truth is.
 */
export function ReconciliationQueue() {
  const qc = useQueryClient();
  const [confirming, setConfirming] = React.useState<Row | null>(null);
  const [rejecting, setRejecting] = React.useState<Row | null>(null);

  const queue = useQuery({
    queryKey: ["admin", "payments", "reconciliation"],
    queryFn: () => api.get<Queue>("/admin/payments/reconciliation"),
    // The scheduler resolves these behind our back every ~10 minutes.
    refetchInterval: 60_000,
  });

  const rows = queue.data?.payments ?? [];

  if (queue.isLoading) return <LoadingState label="Loading reconciliation queue…" />;
  if (queue.isError) {
    return <ErrorState message="Couldn't load the queue." onRetry={() => queue.refetch()} />;
  }

  if (rows.length === 0) {
    return (
      <Card className="flex items-center gap-3 p-6 text-sm">
        <ShieldCheck className="size-5 text-[var(--color-success)]" />
        <div>
          <p className="font-medium">Nothing awaiting reconciliation.</p>
          <p className="text-muted-foreground">
            Every payment has either settled or been confirmed as not captured.
          </p>
        </div>
      </Card>
    );
  }

  const exposure = rows.reduce((s, r) => s + r.amount, 0);

  return (
    <div className="space-y-3">
      <Card className="flex flex-wrap items-center gap-x-6 gap-y-2 border-amber-300 bg-amber-50 p-4 text-sm text-amber-900">
        <AlertTriangle className="size-5 shrink-0" />
        <span>
          <span className="font-semibold">{rows.length}</span> payment
          {rows.length === 1 ? "" : "s"} unresolved ·{" "}
          <span className="font-semibold tabular-nums">{inr(exposure)}</span> exposure
        </span>
        <span className="text-amber-800">{queue.data?.note}</span>
      </Card>

      <div className="space-y-3">
        {rows.map((r) => (
          <Card key={r.id} className="p-4">
            <div className="flex flex-wrap items-start justify-between gap-4">
              <div className="min-w-0 space-y-1.5">
                <div className="flex flex-wrap items-center gap-2">
                  <span className="font-display text-lg font-bold tabular-nums">
                    {inr(r.amount)}
                  </span>
                  <Badge variant="secondary">payment #{r.id}</Badge>
                  {r.orderCode && <Badge variant="outline">{r.orderCode}</Badge>}
                  {r.orderStatus && (
                    <Badge variant="outline" className="capitalize">{r.orderStatus}</Badge>
                  )}
                  {r.stockHeld && (
                    <Badge className="bg-amber-100 text-amber-900">
                      <PackageX className="size-3" /> stock held
                    </Badge>
                  )}
                  {r.refundOnCapture && (
                    <Badge className="bg-destructive/10 text-destructive">
                      refund on capture
                    </Badge>
                  )}
                </div>
                <p className="text-sm text-muted-foreground">
                  {r.customer} · {r.customerPhone} · {r.method}/{r.gateway}
                </p>
                <dl className="grid grid-cols-2 gap-x-6 gap-y-0.5 text-xs text-muted-foreground sm:grid-cols-4">
                  <Fact label="Created" value={new Date(r.createdAt).toLocaleString("en-IN")} />
                  <Fact label="Unresolved for" value={age(r.ageMinutes)} />
                  <Fact label="Checks" value={String(r.attempts)} />
                  <Fact
                    label="Gateway ref"
                    value={r.gatewayOrderId || "—"}
                  />
                </dl>
                {/* What the provider actually said, verbatim — the operator is
                    about to override it, so they should see it. */}
                <p className="text-xs">
                  <span className="text-muted-foreground">Last gateway response: </span>
                  <span className="font-medium">{r.lastGatewaySaid || "—"}</span>
                </p>
              </div>

              <div className="flex shrink-0 gap-2">
                <Button size="sm" onClick={() => setConfirming(r)}>
                  Confirm Captured
                </Button>
                <Button size="sm" variant="outline" onClick={() => setRejecting(r)}>
                  Not Captured
                </Button>
              </div>
            </div>
          </Card>
        ))}
      </div>

      <ConfirmCapturedDialog
        row={confirming}
        onClose={() => setConfirming(null)}
        onResolved={() => qc.invalidateQueries({ queryKey: ["admin", "payments"] })}
      />
      <NotCapturedDialog
        row={rejecting}
        onClose={() => setRejecting(null)}
        onResolved={() => qc.invalidateQueries({ queryKey: ["admin", "payments"] })}
      />
    </div>
  );
}

function Fact({ label, value }: { label: string; value: string }) {
  return (
    <div>
      <dt className="uppercase tracking-wide opacity-70">{label}</dt>
      <dd className="text-foreground">{value}</dd>
    </div>
  );
}

/** Reports an outcome, including "someone else got there first". */
function useResolve(path: string, onResolved: () => void, onClose: () => void) {
  return useMutation({
    mutationFn: (body: Record<string, unknown>) =>
      api.post<Resolution>(path, body),
    onSuccess: (res) => {
      if (res.alreadyFinal) {
        // The scheduler settled it while the dialog was open. Not an error — show
        // where it actually landed rather than pretending this click did it.
        toast.info(`Already resolved elsewhere — now ${res.status}.`);
      } else {
        toast.success(
          res.status === "success"
            ? `Recorded as captured${res.orderCode ? ` · ${res.orderCode}` : ""}.`
            : "Recorded as not captured.",
        );
      }
      onResolved();
      onClose();
    },
    onError: (e) => toast.error(e instanceof ApiError ? e.message : "Couldn't record that."),
  });
}

function ConfirmCapturedDialog({
  row, onClose, onResolved,
}: { row: Row | null; onClose: () => void; onResolved: () => void }) {
  const [amount, setAmount] = React.useState("");
  const [ref, setRef] = React.useState("");
  const [reason, setReason] = React.useState("");
  const [attested, setAttested] = React.useState(false);

  // Reset every time a different row is opened, so one row's attestation can never
  // carry over to the next.
  React.useEffect(() => {
    setAmount(row ? String(row.amount) : "");
    setRef(row?.gatewayPaymentId ?? "");
    setReason("");
    setAttested(false);
  }, [row]);

  const resolve = useResolve(
    row ? `/admin/payments/${row.id}/confirm-captured` : "", onResolved, onClose);

  if (!row) return null;
  const mismatch = amount !== "" && Number(amount) !== row.amount;

  return (
    <Dialog open onOpenChange={(o) => { if (!o && !resolve.isPending) onClose(); }}>
      <DialogContent className="max-w-md">
        <DialogHeader>
          <DialogTitle>Confirm captured — {inr(row.amount)}</DialogTitle>
          <DialogDescription>
            {row.orderCode ? `${row.orderCode} · ` : ""}payment #{row.id} ·{" "}
            {row.gatewayOrderId || "no gateway ref"}
          </DialogDescription>
        </DialogHeader>

        <div className="space-y-3 py-1 text-sm">
          {row.refundOnCapture && (
            <div className="rounded-lg border border-destructive/30 bg-destructive/5 p-3 text-destructive">
              This order is <strong>cancelled</strong>. Confirming the capture records
              it and then raises a refund — the customer gets their money back. It does
              not mark the cancelled order as paid.
            </div>
          )}

          <div className="space-y-1.5">
            <Label htmlFor="cap-amount">Amount the provider captured</Label>
            <Input
              id="cap-amount" inputMode="decimal" value={amount}
              onChange={(e) => setAmount(e.target.value)}
            />
            {mismatch && (
              <p className="text-xs text-destructive">
                This differs from the {inr(row.amount)} due. A partial capture will be
                refused — it must not be settled as a full payment.
              </p>
            )}
          </div>

          <div className="space-y-1.5">
            <Label htmlFor="cap-ref">Provider payment id (optional)</Label>
            <Input id="cap-ref" value={ref} onChange={(e) => setRef(e.target.value)}
                   placeholder="pay_..." />
          </div>

          <div className="space-y-1.5">
            <Label htmlFor="cap-reason">Note (optional)</Label>
            <Input id="cap-reason" value={reason} onChange={(e) => setReason(e.target.value)}
                   placeholder="e.g. dashboard reference / who checked" />
          </div>

          <label className="flex cursor-pointer items-start gap-2 rounded-lg border bg-muted/40 p-3">
            <input
              type="checkbox" className="mt-0.5 size-4 accent-[var(--color-primary)]"
              checked={attested} onChange={(e) => setAttested(e.target.checked)}
            />
            <span className="text-sm">
              I have verified this payment was captured by the payment provider.
            </span>
          </label>
        </div>

        <DialogFooter>
          <Button variant="outline" onClick={onClose} disabled={resolve.isPending}>
            Cancel
          </Button>
          <Button
            // Attestation is not a formality: without it the server refuses.
            disabled={!attested || amount === "" || resolve.isPending}
            onClick={() => resolve.mutate({
              capturedAmount: amount, attested, gatewayPaymentId: ref, reason,
            })}
          >
            {resolve.isPending && <Loader2 className="size-4 animate-spin" />}
            Confirm Captured
          </Button>
        </DialogFooter>
      </DialogContent>
    </Dialog>
  );
}

function NotCapturedDialog({
  row, onClose, onResolved,
}: { row: Row | null; onClose: () => void; onResolved: () => void }) {
  const [reason, setReason] = React.useState("");
  React.useEffect(() => { setReason(""); }, [row]);

  const resolve = useResolve(
    row ? `/admin/payments/${row.id}/confirm-not-captured` : "", onResolved, onClose);

  if (!row) return null;
  return (
    <Dialog open onOpenChange={(o) => { if (!o && !resolve.isPending) onClose(); }}>
      <DialogContent className="max-w-md">
        <DialogHeader>
          <DialogTitle>Provider took nothing — {inr(row.amount)}</DialogTitle>
          <DialogDescription>
            Only when the provider&apos;s own record shows no capture. This marks the
            payment failed{row.stockHeld ? " and releases the order's stock" : ""}.
          </DialogDescription>
        </DialogHeader>
        <div className="space-y-1.5 py-1">
          <Label htmlFor="nc-reason">What did you check?</Label>
          <Input id="nc-reason" value={reason} onChange={(e) => setReason(e.target.value)}
                 placeholder="e.g. no matching capture in the dashboard" />
        </div>
        <DialogFooter>
          <Button variant="outline" onClick={onClose} disabled={resolve.isPending}>
            Cancel
          </Button>
          <Button
            variant="destructive"
            disabled={resolve.isPending}
            onClick={() => resolve.mutate({ reason })}
          >
            {resolve.isPending && <Loader2 className="size-4 animate-spin" />}
            Confirm Not Captured
          </Button>
        </DialogFooter>
      </DialogContent>
    </Dialog>
  );
}

export function ReconciliationBadge({ count }: { count: number }) {
  if (!count) return null;
  return (
    <span className={cn(
      "ml-1.5 rounded-full bg-destructive px-1.5 py-0.5 text-[10px] font-semibold text-white",
    )}>
      {count}
    </span>
  );
}
