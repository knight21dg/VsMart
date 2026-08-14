"use client";

import * as React from "react";
import { useQuery } from "@tanstack/react-query";
import { api, API_BASE } from "@/lib/api/client";
import { AuthImage } from "@/components/auth-image";
import { StatusBadge } from "@/components/status-badge";
import { ErrorState, LoadingState } from "@/components/states";
import {
  Dialog,
  DialogContent,
  DialogDescription,
  DialogHeader,
  DialogTitle,
} from "@/components/ui/dialog";
import { inr, fmtDate, titleize } from "@/lib/utils";

interface ReturnEvidenceRow {
  id: string;
  source: "customer" | "agent";
  url: string;
  capturedAt: string | null;
}

interface ReturnDetail {
  code: string;
  status: string;
  reason: string;
  description: string;
  refundAmount: number;
  createdAt: string;
  resolvedAt: string | null;
  decisionNote: string;
  decidedBy: string | null;
  order: {
    code: string | null;
    total: number;
    paymentMethod: string | null;
    paymentStatus: string | null;
    status: string | null;
  };
  customer: { id: string | null; name: string | null; phone: string | null };
  items: {
    name: string;
    quantity: number;
    amount: number;
    acceptedQuantity: number | null;
    acceptedAmount: number | null;
    settledQuantity: number;
    settledAmount: number;
  }[];
  evidence: ReturnEvidenceRow[];
}

/**
 * Read-only review of a return before deciding it.
 *
 * The console had no detail view at all: an admin approved or rejected straight
 * from a table row, seeing only a reason word and an item count — not the
 * customer's note, not what the agent actually accepted at the door, and not the
 * photos the customer was required to upload. The decision buttons stay on the
 * list; this is the evidence behind them.
 */
export function ReturnDetailDialog({
  code,
  onClose,
}: {
  code: string | null;
  onClose: () => void;
}) {
  const open = code !== null;
  const q = useQuery({
    queryKey: ["admin", "returns", "detail", code],
    queryFn: () => api.get<ReturnDetail>(`/admin/returns/${code}`),
    enabled: open,
  });
  const d = q.data;

  return (
    <Dialog open={open} onOpenChange={(o) => !o && onClose()}>
      <DialogContent className="max-h-[85vh] max-w-2xl overflow-y-auto">
        <DialogHeader>
          <DialogTitle className="font-mono">{code}</DialogTitle>
          <DialogDescription>
            {d ? `${titleize(d.reason)} · raised ${fmtDate(d.createdAt)}` : "Return detail"}
          </DialogDescription>
        </DialogHeader>

        {q.isLoading ? (
          <LoadingState label="Loading return…" />
        ) : q.isError || !d ? (
          <ErrorState message="Couldn't load this return." onRetry={() => q.refetch()} />
        ) : (
          <div className="space-y-5 text-sm">
            <div className="flex flex-wrap items-center gap-2">
              <StatusBadge status={d.status} />
              <span className="ml-auto font-medium">{inr(d.refundAmount)} refund</span>
            </div>

            {d.description && (
              <Section title="Customer's note">
                <p className="text-muted-foreground">{d.description}</p>
              </Section>
            )}

            <Section title="Order">
              <KV label="Order" value={d.order.code ?? "—"} />
              <KV label="Order total" value={inr(d.order.total)} />
              {d.order.paymentMethod && (
                <KV
                  label="Payment"
                  value={`${titleize(d.order.paymentMethod)} · ${titleize(d.order.paymentStatus ?? "")}`}
                />
              )}
            </Section>

            <Section title="Customer">
              <KV label="Name" value={d.customer.name ?? "—"} />
              <KV label="Phone" value={d.customer.phone ?? "—"} />
            </Section>

            <Section title={`Items (${d.items.length})`}>
              {d.items.length === 0 ? (
                <p className="text-muted-foreground">Whole-order return.</p>
              ) : (
                <ul className="divide-y">
                  {d.items.map((it, i) => {
                    // The refund is computed on what the agent ACCEPTED, so when
                    // that differs from the request, show both.
                    const trimmed =
                      it.acceptedQuantity !== null && it.acceptedQuantity !== it.quantity;
                    return (
                      <li key={i} className="flex items-center justify-between gap-3 py-1.5">
                        <span className="truncate">
                          {it.quantity} × {it.name}
                          {trimmed && (
                            <span className="ml-2 text-xs text-muted-foreground">
                              agent accepted {it.acceptedQuantity}
                            </span>
                          )}
                        </span>
                        <span className="shrink-0 font-medium">{inr(it.settledAmount)}</span>
                      </li>
                    );
                  })}
                </ul>
              )}
            </Section>

            <ReturnEvidence evidence={d.evidence ?? []} />

            {(d.decisionNote || d.decidedBy) && (
              <Section title="Decision">
                {d.decidedBy && <KV label="By" value={d.decidedBy} />}
                {d.resolvedAt && <KV label="At" value={fmtDate(d.resolvedAt, true)} />}
                {d.decisionNote && (
                  <p className="pt-1 text-muted-foreground">{d.decisionNote}</p>
                )}
              </Section>
            )}
          </div>
        )}
      </DialogContent>
    </Dialog>
  );
}

/**
 * The photos backing a return. Customer proof (condition on submission) and
 * agent proof (condition at the door) are labelled separately because they
 * answer different questions: what was claimed, versus what was found.
 *
 * `AuthImage` because the endpoint is permission-gated and a bare <img src>
 * carries no bearer token.
 */
function ReturnEvidence({ evidence }: { evidence: ReturnEvidenceRow[] }) {
  if (evidence.length === 0) {
    return (
      <Section title="Photos">
        <p className="text-muted-foreground">No photos were attached.</p>
      </Section>
    );
  }
  const groups: { key: "customer" | "agent"; label: string }[] = [
    { key: "customer", label: "Customer's photos (as submitted)" },
    { key: "agent", label: "Agent's photos (at pickup)" },
  ];
  return (
    <>
      {groups.map(({ key, label }) => {
        const shots = evidence.filter((e) => e.source === key);
        if (shots.length === 0) return null;
        return (
          <Section key={key} title={`${label} · ${shots.length}`}>
            <div className="grid grid-cols-3 gap-2 sm:grid-cols-4">
              {shots.map((e) => (
                <a
                  key={e.id}
                  href={`${API_BASE}${e.url}`}
                  target="_blank"
                  rel="noreferrer"
                  title={e.capturedAt ? `Taken ${fmtDate(e.capturedAt, true)}` : "Open full size"}
                  className="block overflow-hidden rounded-md border transition-opacity hover:opacity-80"
                >
                  <AuthImage
                    path={e.url}
                    alt="Return photo"
                    className="aspect-square w-full object-cover"
                  />
                </a>
              ))}
            </div>
          </Section>
        );
      })}
    </>
  );
}

function Section({ title, children }: { title: string; children: React.ReactNode }) {
  return (
    <div className="space-y-1.5">
      <p className="text-xs font-semibold uppercase tracking-wider text-muted-foreground">
        {title}
      </p>
      {children}
    </div>
  );
}

function KV({ label, value }: { label: string; value: React.ReactNode }) {
  return (
    <div className="flex justify-between gap-3">
      <span className="text-muted-foreground">{label}</span>
      <span className="text-right font-medium">{value}</span>
    </div>
  );
}
