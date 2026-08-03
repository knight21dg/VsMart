"use client";

import * as React from "react";
import { useQuery } from "@tanstack/react-query";
import type { ColumnDef } from "@tanstack/react-table";
import { api, useApiMutation } from "@/lib/api/hooks";
import { useStore } from "@/lib/store/store-context";
import { PageHeader } from "@/components/page-header";
import { DataTable } from "@/components/data-table";
import { RequirePerm } from "@/components/permission-gate";
import { StatusBadge } from "@/components/status-badge";
import { Button } from "@/components/ui/button";
import { Textarea } from "@/components/ui/textarea";
import {
  Dialog, DialogContent, DialogHeader, DialogTitle, DialogDescription,
} from "@/components/ui/dialog";
import { ErrorState, LoadingState } from "@/components/states";
import { KV, Section, sheetClass } from "@/components/detail-sheet";
import { ProductLink } from "@/components/product-link";
import { inr, fmtDate, titleize } from "@/lib/utils";

interface ReturnRow {
  code: string; orderCode: string | null; customer: string | null; phone: string | null;
  reason: string; status: string; refundAmount: number; items: number; createdAt: string;
}

interface ReturnDetail {
  code: string; status: string; reason: string; description: string;
  refundAmount: number; createdAt: string; resolvedAt: string | null;
  decisionNote: string; decidedBy: string | null;
  order: { code: string | null; total: number; paymentMethod: string | null; paymentStatus: string | null; status: string | null };
  customer: { id: string | null; name: string | null; phone: string | null };
  items: { name: string; quantity: number; amount: number }[];
}

// Next actions available from each status.
const NEXT: Record<string, string[]> = {
  requested: ["approved", "rejected"],
  approved: ["picked", "refunded", "rejected"],
  picked: ["refunded", "rejected"],
};

export default function ReturnsPage() {
  return (
    <RequirePerm perm="returns.manage">
      <ReturnsInner />
    </RequirePerm>
  );
}

function ReturnsInner() {
  const [filter, setFilter] = React.useState("all");
  const [openCode, setOpenCode] = React.useState<string | null>(null);
  const q = useQuery({
    queryKey: ["store", "returns", filter],
    queryFn: () => api.get<ReturnRow[]>("/store/returns", filter === "all" ? {} : { status: filter }),
  });

  const columns: ColumnDef<ReturnRow, unknown>[] = [
    {
      header: "Return",
      cell: ({ row }) => (
        <button onClick={() => setOpenCode(row.original.code)} className="text-left">
          <div className="font-mono text-sm text-primary hover:underline">{row.original.code}</div>
          <div className="text-xs text-muted-foreground">{row.original.orderCode}</div>
        </button>
      ),
    },
    { header: "Customer", cell: ({ row }) => <div><div className="text-sm">{row.original.customer ?? "—"}</div><div className="text-xs text-muted-foreground">{row.original.phone}</div></div> },
    { header: "Reason", cell: ({ row }) => <span className="text-sm text-muted-foreground">{titleize(row.original.reason)}</span> },
    { header: "Refund", cell: ({ row }) => <span className="font-medium">{inr(row.original.refundAmount)}</span> },
    { header: "Status", cell: ({ row }) => <StatusBadge status={row.original.status} /> },
    { header: "Raised", cell: ({ row }) => <span className="text-xs text-muted-foreground">{fmtDate(row.original.createdAt)}</span> },
    {
      header: "", id: "actions",
      cell: ({ row }) =>
        (NEXT[row.original.status] ?? []).length > 0 ? (
          <Button variant="outline" size="sm" onClick={() => setOpenCode(row.original.code)}>Review</Button>
        ) : null,
    },
  ];

  return (
    <div className="space-y-5">
      <PageHeader title="Returns & Refunds" description="Review return requests against your store's orders." />
      <DataTable
        columns={columns}
        data={q.data ?? []}
        loading={q.isLoading}
        error={q.error ? "Couldn't load returns." : null}
        onRetry={() => q.refetch()}
        emptyMessage="No returns in this view."
        toolbar={
          <div className="flex flex-wrap gap-2">
            {["all", "requested", "approved", "picked", "refunded", "rejected"].map((s) => (
              <button key={s} onClick={() => setFilter(s)}
                className={`rounded-full px-3 py-1 text-xs font-medium capitalize transition-colors ${filter === s ? "bg-primary text-primary-foreground" : "bg-muted text-muted-foreground hover:bg-accent"}`}>
                {s}
              </button>
            ))}
          </div>
        }
      />
      <ReturnDetailSheet code={openCode} onClose={() => setOpenCode(null)} />
    </div>
  );
}

function ReturnDetailSheet({ code, onClose }: { code: string | null; onClose: () => void }) {
  const { hasPerm } = useStore();
  const canManage = hasPerm("returns.manage");
  const open = code !== null;
  const [note, setNote] = React.useState("");

  const q = useQuery({
    queryKey: ["store", "returns", "detail", code],
    queryFn: () => api.get<ReturnDetail>(`/store/returns/${code}`),
    enabled: open,
  });

  function close() {
    setNote("");
    onClose();
  }

  const setStatus = useApiMutation(
    ({ status }: { status: string }) => api.post(`/store/returns/${code}/status`, { status, note: note.trim() }),
    {
      invalidate: [["store", "returns"], ["store", "returns", "detail", code]],
      successMessage: "Return updated",
    },
  );

  const d = q.data;
  const actions = d ? (NEXT[d.status] ?? []) : [];

  return (
    <Dialog open={open} onOpenChange={(o) => !o && close()}>
      <DialogContent className={sheetClass}>
        <DialogHeader>
          <DialogTitle className="font-mono">{code}</DialogTitle>
          <DialogDescription>
            {d ? `${titleize(d.reason)} · raised ${fmtDate(d.createdAt)}` : "Return detail"}
          </DialogDescription>
        </DialogHeader>

        {q.isLoading ? (
          <LoadingState label="Loading return…" />
        ) : q.error || !d ? (
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
              {d.order.paymentMethod && <KV label="Payment" value={`${titleize(d.order.paymentMethod)} · ${titleize(d.order.paymentStatus ?? "")}`} />}
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
                  {d.items.map((it, i) => (
                    <li key={i} className="flex items-center justify-between gap-3 py-1.5">
                      {/* Return-item snapshot — the payload carries no product id. */}
                      <span className="truncate">{it.quantity} × <ProductLink name={it.name} /></span>
                      <span className="shrink-0 font-medium">{inr(it.amount)}</span>
                    </li>
                  ))}
                </ul>
              )}
            </Section>

            {(d.decisionNote || d.decidedBy) && (
              <Section title="Decision">
                {d.decidedBy && <KV label="By" value={d.decidedBy} />}
                {d.resolvedAt && <KV label="At" value={fmtDate(d.resolvedAt, true)} />}
                {d.decisionNote && <p className="pt-1 text-muted-foreground">{d.decisionNote}</p>}
              </Section>
            )}

            {canManage && actions.length > 0 && (
              <div className="space-y-2 border-t pt-4">
                <p className="text-xs font-semibold uppercase tracking-wider text-muted-foreground">Decision note (optional)</p>
                <Textarea
                  value={note}
                  onChange={(e) => setNote(e.target.value)}
                  placeholder="Add a note explaining this decision…"
                />
                <div className="flex flex-wrap gap-2 pt-1">
                  {actions.map((s) => (
                    <Button
                      key={s}
                      variant={s === "rejected" ? "outline" : "default"}
                      size="sm"
                      disabled={setStatus.isPending}
                      onClick={() => setStatus.mutate({ status: s })}
                    >
                      {titleize(s)}
                    </Button>
                  ))}
                </div>
              </div>
            )}
          </div>
        )}
      </DialogContent>
    </Dialog>
  );
}
