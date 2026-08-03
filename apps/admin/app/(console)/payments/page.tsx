"use client";

import * as React from "react";
import { keepPreviousData, useQuery } from "@tanstack/react-query";
import { type ColumnDef } from "@tanstack/react-table";
import { ArrowDownLeft, ArrowUpRight, Loader2, Search, XCircle } from "lucide-react";
import { api } from "@/lib/api/client";
import { type PageMeta } from "@/lib/types";
import { PageHeader } from "@/components/page-header";
import { DataTable } from "@/components/data-table";
import { StatusBadge } from "@/components/status-badge";
import { Card } from "@/components/ui/card";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import { Badge } from "@/components/ui/badge";
import {
  Dialog, DialogContent, DialogHeader, DialogTitle,
} from "@/components/ui/dialog";
import {
  Select, SelectContent, SelectItem, SelectTrigger, SelectValue,
} from "@/components/ui/select";
import { inr, titleize } from "@/lib/utils";

interface Payment {
  id: string;
  userId: string;
  customerName: string;
  customerPhone: string;
  purpose: string;
  amount: number | string;
  method: string;
  gateway: string;
  status: string;
  gatewayOrderId: string;
  gatewayPaymentId: string;
  gatewayRefundId: string;
  orderCode: string | null;
  statementId: number | null;
  refundOfId: number | null;
  createdAt: string;
}
interface PaymentEvent {
  id: string; status: string; note: string; gatewayRef: string;
  actor: string | null; createdAt: string;
}
interface PaymentDetail extends Payment {
  events: PaymentEvent[];
  refunds: Payment[];
}
interface Summary {
  collected: number | string;
  refunded: number | string;
  failedCount: number;
  total: number;
  byStatus: { status: string; count: number; amount: number | string }[];
  byMethod: { method: string; count: number; amount: number | string }[];
}

const ANY = "__any__";
const STATUSES = ["created", "pending", "success", "failed", "refunded"];
const METHODS = ["upi", "card", "netbanking", "cash"];
const PURPOSES = ["order", "repayment", "refund"];

function FilterSelect({ value, onChange, placeholder, options }: {
  value: string; onChange: (v: string) => void; placeholder: string; options: string[];
}) {
  return (
    <Select value={value || ANY} onValueChange={(v) => onChange(v === ANY ? "" : v)}>
      <SelectTrigger className="w-[150px]"><SelectValue placeholder={placeholder} /></SelectTrigger>
      <SelectContent>
        <SelectItem value={ANY}>{placeholder}</SelectItem>
        {options.map((o) => <SelectItem key={o} value={o}>{titleize(o)}</SelectItem>)}
      </SelectContent>
    </Select>
  );
}

export default function PaymentsPage() {
  const [search, setSearch] = React.useState("");
  const [q, setQ] = React.useState("");
  const [status, setStatus] = React.useState("");
  const [method, setMethod] = React.useState("");
  const [purpose, setPurpose] = React.useState("");
  const [from, setFrom] = React.useState("");
  const [to, setTo] = React.useState("");
  const [page, setPage] = React.useState(1);
  const [openId, setOpenId] = React.useState<string | null>(null);

  React.useEffect(() => {
    const t = setTimeout(() => { setQ(search.trim()); setPage(1); }, 300);
    return () => clearTimeout(t);
  }, [search]);

  const filters = {
    q: q || undefined,
    status: status || undefined,
    method: method || undefined,
    purpose: purpose || undefined,
    from: from || undefined,
    to: to || undefined,
  };
  // One filter object drives both queries, so the totals always describe
  // exactly the rows on screen.
  const query = useQuery({
    queryKey: ["admin", "payments", filters, page],
    queryFn: () => api.getPaged<Payment>("/admin/payments", { ...filters, page }),
    placeholderData: keepPreviousData,
  });
  const summary = useQuery({
    queryKey: ["admin", "payments", "summary", filters],
    queryFn: () => api.get<Summary>("/admin/payments/summary", filters),
  });

  function reset(fn: (v: string) => void) {
    return (v: string) => { fn(v); setPage(1); };
  }

  const columns: ColumnDef<Payment, unknown>[] = [
    {
      accessorKey: "createdAt", header: "When",
      cell: ({ row }) => (
        <span className="whitespace-nowrap text-xs text-muted-foreground">
          {new Date(row.original.createdAt).toLocaleString("en-IN", {
            day: "2-digit", month: "short", hour: "2-digit", minute: "2-digit",
          })}
        </span>
      ),
    },
    {
      accessorKey: "customerName", header: "Customer",
      cell: ({ row }) => (
        <div className="flex flex-col">
          <span className="font-medium">{row.original.customerName || "—"}</span>
          <span className="text-xs text-muted-foreground">{row.original.customerPhone}</span>
        </div>
      ),
    },
    {
      accessorKey: "amount", header: "Amount",
      cell: ({ row }) => {
        const out = row.original.purpose === "refund";
        return (
          <span className={`tabular-nums font-medium ${out ? "text-destructive" : ""}`}>
            {out ? "−" : ""}{inr(Number(row.original.amount))}
          </span>
        );
      },
    },
    { accessorKey: "purpose", header: "Purpose", cell: ({ row }) => <Badge variant="secondary">{titleize(row.original.purpose)}</Badge> },
    { accessorKey: "method", header: "Method", cell: ({ row }) => titleize(row.original.method) },
    { accessorKey: "gateway", header: "Gateway", cell: ({ row }) => <span className="text-xs text-muted-foreground">{titleize(row.original.gateway)}</span> },
    { accessorKey: "status", header: "Status", cell: ({ row }) => <StatusBadge status={row.original.status} /> },
    {
      id: "ref", header: "Reference",
      cell: ({ row }) => (
        <span className="font-mono text-xs text-muted-foreground">
          {row.original.gatewayPaymentId || row.original.orderCode || "—"}
        </span>
      ),
    },
  ];

  return (
    <>
      <PageHeader
        title="Payments"
        description="Every payment, refund and repayment — searchable, and reconcilable for any date range."
      />

      <div className="grid gap-3 sm:grid-cols-3">
        <StatCard
          label="Collected" hint="Successful payments, excluding refunds"
          value={summary.data ? inr(Number(summary.data.collected)) : "—"}
          icon={<ArrowDownLeft className="size-4 text-[var(--color-success)]" />}
          loading={summary.isLoading}
        />
        <StatCard
          label="Refunded" hint="Successful refunds paid back out"
          value={summary.data ? inr(Number(summary.data.refunded)) : "—"}
          icon={<ArrowUpRight className="size-4 text-destructive" />}
          loading={summary.isLoading}
        />
        <StatCard
          label="Failed" hint="Attempts that never completed"
          value={summary.data ? String(summary.data.failedCount) : "—"}
          icon={<XCircle className="size-4 text-muted-foreground" />}
          loading={summary.isLoading}
        />
      </div>

      <div className="space-y-3">
        <div className="relative">
          <Search className="pointer-events-none absolute left-3 top-1/2 size-4 -translate-y-1/2 text-muted-foreground" />
          <Input
            value={search} onChange={(e) => setSearch(e.target.value)}
            placeholder="Search — customer, phone, order code, gateway payment id…"
            className="pl-9"
          />
        </div>
        <div className="flex flex-wrap items-end gap-2">
          <FilterSelect value={status} onChange={reset(setStatus)} placeholder="Status" options={STATUSES} />
          <FilterSelect value={method} onChange={reset(setMethod)} placeholder="Method" options={METHODS} />
          <FilterSelect value={purpose} onChange={reset(setPurpose)} placeholder="Purpose" options={PURPOSES} />
          <div className="space-y-1">
            <Label className="text-xs text-muted-foreground">From</Label>
            <Input type="date" value={from} onChange={(e) => { setFrom(e.target.value); setPage(1); }} className="w-[150px]" />
          </div>
          <div className="space-y-1">
            <Label className="text-xs text-muted-foreground">To</Label>
            <Input type="date" value={to} onChange={(e) => { setTo(e.target.value); setPage(1); }} className="w-[150px]" />
          </div>
        </div>
      </div>

      <DataTable
        columns={columns}
        data={query.data?.rows ?? []}
        loading={query.isLoading}
        error={query.isError ? "Failed to load payments." : null}
        onRetry={() => query.refetch()}
        emptyMessage="No payments match these filters."
        pageMeta={query.data?.meta as PageMeta | undefined}
        page={page}
        onPageChange={setPage}
        onRowClick={(row) => setOpenId(row.id)}
      />

      {openId && <PaymentDialog paymentId={openId} onClose={() => setOpenId(null)} />}
    </>
  );
}

function StatCard({ label, value, hint, icon, loading }: {
  label: string; value: string; hint: string;
  icon: React.ReactNode; loading: boolean;
}) {
  return (
    <Card className="p-4">
      <div className="flex items-center gap-2 text-sm text-muted-foreground">
        {icon} {label}
      </div>
      <div className="mt-1 text-2xl font-semibold tabular-nums">
        {loading ? <Loader2 className="size-5 animate-spin text-muted-foreground" /> : value}
      </div>
      <p className="mt-0.5 text-xs text-muted-foreground">{hint}</p>
    </Card>
  );
}

/** One payment with its full audit trail — why it ended where it did. */
function PaymentDialog({ paymentId, onClose }: { paymentId: string; onClose: () => void }) {
  const detail = useQuery({
    queryKey: ["admin", "payment", paymentId],
    queryFn: () => api.get<PaymentDetail>(`/admin/payments/${paymentId}`),
  });
  const p = detail.data;

  return (
    <Dialog open onOpenChange={(o) => !o && onClose()}>
      <DialogContent className="max-h-[90vh] max-w-xl overflow-y-auto">
        <DialogHeader>
          <DialogTitle className="flex items-center gap-2">
            Payment #{paymentId}
            {p && <StatusBadge status={p.status} />}
          </DialogTitle>
        </DialogHeader>

        {detail.isLoading && (
          <div className="grid place-items-center py-10">
            <Loader2 className="size-5 animate-spin text-muted-foreground" />
          </div>
        )}
        {detail.isError && (
          <p className="py-6 text-center text-sm text-destructive">Failed to load.</p>
        )}

        {p && (
          <div className="space-y-4">
            <div className="rounded-md border divide-y">
              <Row label="Customer" value={`${p.customerName || "—"} · ${p.customerPhone}`} />
              <Row label="Amount" value={inr(Number(p.amount))} />
              <Row label="Purpose" value={titleize(p.purpose)} />
              <Row label="Method" value={`${titleize(p.method)} · ${titleize(p.gateway)}`} />
              {p.orderCode && <Row label="Order" value={p.orderCode} />}
              {p.gatewayOrderId && <Row label="Gateway order id" value={p.gatewayOrderId} mono />}
              {p.gatewayPaymentId && <Row label="Gateway payment id" value={p.gatewayPaymentId} mono />}
              {p.gatewayRefundId && <Row label="Gateway refund id" value={p.gatewayRefundId} mono />}
              <Row label="Created" value={new Date(p.createdAt).toLocaleString("en-IN")} />
            </div>

            <div>
              <p className="mb-2 text-xs font-medium uppercase tracking-wide text-muted-foreground">
                Timeline
              </p>
              {p.events.length === 0 ? (
                <p className="text-sm text-muted-foreground">No events recorded.</p>
              ) : (
                <ol className="space-y-2">
                  {p.events.map((e) => (
                    <li key={e.id} className="flex items-start gap-3 rounded-md border p-2.5 text-sm">
                      <StatusBadge status={e.status} />
                      <div className="flex-1">
                        {e.note && <p>{e.note}</p>}
                        <p className="text-xs text-muted-foreground">
                          {new Date(e.createdAt).toLocaleString("en-IN")}
                          {e.actor ? ` · ${e.actor}` : ""}
                          {e.gatewayRef ? ` · ${e.gatewayRef}` : ""}
                        </p>
                      </div>
                    </li>
                  ))}
                </ol>
              )}
            </div>

            {p.refunds.length > 0 && (
              <div>
                <p className="mb-2 text-xs font-medium uppercase tracking-wide text-muted-foreground">
                  Refunds against this payment
                </p>
                <div className="rounded-md border divide-y">
                  {p.refunds.map((r) => (
                    <Row key={r.id} label={new Date(r.createdAt).toLocaleDateString("en-IN")}
                         value={`−${inr(Number(r.amount))} · ${titleize(r.status)}`} />
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

function Row({ label, value, mono }: { label: string; value: string; mono?: boolean }) {
  return (
    <div className="flex items-start justify-between gap-4 px-3 py-2 text-sm">
      <span className="text-muted-foreground">{label}</span>
      <span className={`text-right font-medium ${mono ? "font-mono text-xs" : ""}`}>{value}</span>
    </div>
  );
}
