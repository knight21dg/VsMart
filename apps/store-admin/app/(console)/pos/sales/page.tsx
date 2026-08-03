"use client";

import * as React from "react";
import { useQuery } from "@tanstack/react-query";
import type { ColumnDef } from "@tanstack/react-table";
import { Download, Eye, Loader2, Search, Undo2 } from "lucide-react";
import { api, useApiMutation } from "@/lib/api/hooks";
import { downloadPdf } from "@/lib/pdf";
import { PageHeader } from "@/components/page-header";
import { DataTable } from "@/components/data-table";
import { RequirePerm } from "@/components/permission-gate";
import { ProductLink } from "@/components/product-link";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from "@/components/ui/select";
import { Badge } from "@/components/ui/badge";
import { Dialog, DialogContent, DialogFooter, DialogHeader, DialogTitle } from "@/components/ui/dialog";
import { inr, fmtDate } from "@/lib/utils";

const ALL = "__all__";

interface TxnItem { productId: string; variantId: string | null; name: string; quantity: number; lineTotal: number }
interface TxnPayment { method: string; amount: number }
interface Txn {
  code: string; type: string; subtotal: number; tax: number; discount: number;
  total: number; creditUsed: number; changeDue: number; paymentStatus: string;
  createdAt: string; customerName: string | null; primaryMethod: string | null;
  items: TxnItem[]; payments: TxnPayment[];
}

export default function POSSalesPage() {
  return (
    <RequirePerm perm="pos.operate">
      <Inner />
    </RequirePerm>
  );
}

function Inner() {
  const q = useQuery({ queryKey: ["store", "pos", "transactions"], queryFn: () => api.get<Txn[]>("/store/pos/transactions") });
  const [view, setView] = React.useState<Txn | null>(null);
  const [returning, setReturning] = React.useState<Txn | null>(null);
  const [search, setSearch] = React.useState("");
  const [method, setMethod] = React.useState(ALL);
  const [day, setDay] = React.useState("");

  // Client-side: the endpoint returns this store's till history unpaginated, and
  // a counter's day is small. Finding yesterday's bill by scrolling was the
  // complaint — code/customer/date/tender narrow it instantly.
  const rows = React.useMemo(() => {
    const term = search.trim().toLowerCase();
    return (q.data ?? []).filter((t) => {
      if (term && !t.code.toLowerCase().includes(term) &&
          !(t.customerName ?? "").toLowerCase().includes(term)) return false;
      if (method !== ALL && (t.primaryMethod ?? "") !== method) return false;
      if (day && !t.createdAt.startsWith(day)) return false;
      return true;
    });
  }, [q.data, search, method, day]);

  function downloadTxnPdf(code: string, kind: "invoice" | "receipt-pdf" = "invoice") {
    return downloadPdf(
      `/store/pos/transactions/${code}/${kind}`,
      `${kind === "invoice" ? "invoice" : "receipt"}-${code}.pdf`,
    );
  }

  const columns: ColumnDef<Txn, unknown>[] = [
    { header: "Order ID", cell: ({ row }) => <span className="font-mono text-xs font-medium">{row.original.code}</span> },
    { header: "Date", cell: ({ row }) => <span className="text-sm text-muted-foreground">{fmtDate(row.original.createdAt, true)}</span> },
    { header: "Customer", cell: ({ row }) => <span className="text-muted-foreground">{row.original.customerName || "Walk-in"}</span> },
    { header: "Total", cell: ({ row }) => <span className="font-semibold">{inr(row.original.total)}</span> },
    { header: "Payment", cell: ({ row }) => <span className="capitalize">{row.original.primaryMethod || "—"}</span> },
    {
      header: "Status", cell: ({ row }) => (
        <Badge variant={row.original.type === "return" ? "warning" : row.original.paymentStatus === "paid" ? "success" : "secondary"} className="capitalize">
          {row.original.type === "return" ? "Return" : row.original.paymentStatus}
        </Badge>
      ),
    },
    {
      header: "", id: "actions",
      cell: ({ row }) => (
        <div className="flex justify-end gap-1">
          <Button variant="ghost" size="icon" onClick={() => setView(row.original)}><Eye className="size-4" /></Button>
          <Button variant="ghost" size="icon" onClick={() => downloadTxnPdf(row.original.code)}><Download className="size-4" /></Button>
          {/* Returns exist server-side; there was simply no way to start one. */}
          {row.original.type !== "return" && (
            <Button variant="ghost" size="icon" title="Return items"
                    onClick={() => setReturning(row.original)}>
              <Undo2 className="size-4" />
            </Button>
          )}
        </div>
      ),
    },
  ];

  return (
    <div className="space-y-5">
      <PageHeader title="POS Sales" description="Every sale rung up at this store's counter." />
      <DataTable
        columns={columns}
        data={rows}
        loading={q.isLoading}
        error={q.error ? "Couldn't load POS sales." : null}
        onRetry={() => q.refetch()}
        emptyMessage={(q.data ?? []).length ? "No sales match those filters." : "No POS sales yet."}
        toolbar={
          <div className="flex flex-wrap items-center gap-2">
            <div className="relative min-w-[200px] flex-1">
              <Search className="pointer-events-none absolute left-2.5 top-2.5 size-4 text-muted-foreground" />
              <Input className="pl-8" placeholder="Search bill no. or customer…"
                     value={search} onChange={(e) => setSearch(e.target.value)} />
            </div>
            <Input type="date" className="w-[160px]" value={day}
                   onChange={(e) => setDay(e.target.value)} />
            <Select value={method} onValueChange={setMethod}>
              <SelectTrigger className="w-[140px]"><SelectValue placeholder="Payment" /></SelectTrigger>
              <SelectContent>
                <SelectItem value={ALL}>All payments</SelectItem>
                {["cash", "online", "credit"].map((m) => (
                  <SelectItem key={m} value={m}><span className="capitalize">{m}</span></SelectItem>
                ))}
              </SelectContent>
            </Select>
            {(search || day || method !== ALL) && (
              <Button variant="ghost" size="sm" onClick={() => { setSearch(""); setDay(""); setMethod(ALL); }}>
                Clear
              </Button>
            )}
            <span className="ml-auto text-xs text-muted-foreground">{rows.length} of {(q.data ?? []).length}</span>
          </div>
        }
      />

      {returning && (
        <ReturnDialog txn={returning} onClose={() => setReturning(null)} onDone={() => { setReturning(null); void q.refetch(); }} />
      )}

      {view && (
        <Dialog open onOpenChange={(o) => !o && setView(null)}>
          <DialogContent className="max-w-md">
            <DialogHeader><DialogTitle className="font-mono text-sm">{view.code}</DialogTitle></DialogHeader>
            <div className="space-y-3 text-sm">
              <p className="text-xs text-muted-foreground">{fmtDate(view.createdAt, true)} · {view.customerName || "Walk-in"}</p>
              <ul className="divide-y">
                {view.items.map((i, idx) => (
                  <li key={idx} className="flex justify-between py-1">
                    <span>{i.quantity} × <ProductLink id={i.productId} name={i.name} /></span>
                    <span>{inr(i.lineTotal, { decimals: true })}</span>
                  </li>
                ))}
              </ul>
              <div className="space-y-1 border-t pt-2">
                <div className="flex justify-between text-muted-foreground"><span>Subtotal</span><span>{inr(view.subtotal, { decimals: true })}</span></div>
                <div className="flex justify-between text-muted-foreground"><span>Tax</span><span>{inr(view.tax, { decimals: true })}</span></div>
                {view.discount > 0 && <div className="flex justify-between text-[var(--color-success)]"><span>Discount</span><span>− {inr(view.discount, { decimals: true })}</span></div>}
                <div className="flex justify-between border-t pt-1 font-bold"><span>Total</span><span>{inr(view.total, { decimals: true })}</span></div>
              </div>
              <div className="space-y-1">
                {view.payments.map((p, idx) => (
                  <div key={idx} className="flex justify-between capitalize text-muted-foreground"><span>{p.method}</span><span>{inr(p.amount, { decimals: true })}</span></div>
                ))}
              </div>
              <div className="flex gap-2">
                <Button className="flex-1" onClick={() => downloadTxnPdf(view.code, "invoice")}>
                  <Download className="size-4" /> Download invoice
                </Button>
                <Button variant="outline" onClick={() => downloadTxnPdf(view.code, "receipt-pdf")}>
                  Receipt
                </Button>
              </div>
            </div>
          </DialogContent>
        </Dialog>
      )}
    </div>
  );
}

/**
 * Return items from a completed sale.
 *
 * The backend has always supported this (`POST /store/pos/transactions/<code>/return`
 * → reverses stock, refunds cash/credit, writes a credit-note transaction) but no
 * screen ever called it, so a mis-rung sale could only be fixed in the database.
 *
 * Quantities are capped at what was actually sold — you cannot return three of an
 * item the customer bought two of.
 */
function ReturnDialog({ txn, onClose, onDone }: { txn: Txn; onClose: () => void; onDone: () => void }) {
  const [qty, setQty] = React.useState<Record<string, number>>({});
  const [reason, setReason] = React.useState("");
  const [refundMethod, setRefundMethod] = React.useState(txn.primaryMethod ?? "cash");

  const lines = txn.items.filter((i) => (qty[i.productId] ?? 0) > 0);
  const refundTotal = lines.reduce((s, i) => {
    const unit = i.quantity ? i.lineTotal / i.quantity : 0;
    return s + unit * (qty[i.productId] ?? 0);
  }, 0);

  const submit = useApiMutation<void>(
    () => api.post(`/store/pos/transactions/${txn.code}/return`, {
      items: lines.map((i) => ({ productId: i.productId, qty: qty[i.productId] })),
      reason: reason.trim(),
      refundMethod,
    }),
    {
      invalidate: [["store", "pos", "transactions"], ["store", "inventory"]],
      successMessage: "Return recorded — stock and refund posted",
      onDone,
    },
  );

  return (
    <Dialog open onOpenChange={(o) => !o && onClose()}>
      <DialogContent className="max-w-md">
        <DialogHeader>
          <DialogTitle>Return from <span className="font-mono text-sm">{txn.code}</span></DialogTitle>
        </DialogHeader>
        <div className="space-y-3 py-1">
          <div className="space-y-2 rounded-md border p-2">
            {txn.items.map((i) => {
              const picked = qty[i.productId] ?? 0;
              return (
                <div key={i.productId} className="flex items-center gap-2">
                  <div className="min-w-0 flex-1">
                    {/* Deliberately NOT a ProductLink: this row carries the
                        return quantity being entered, and navigating away would
                        discard the half-built return. */}
                    <p className="truncate text-sm font-medium">{i.name}</p>
                    <p className="text-xs text-muted-foreground">sold {i.quantity} · {inr(i.lineTotal, { decimals: true })}</p>
                  </div>
                  <Input
                    className="h-8 w-20" inputMode="numeric" value={String(picked)}
                    onChange={(e) => {
                      // Never above what was sold.
                      const n = Math.max(0, Math.min(Number(e.target.value) || 0, i.quantity));
                      setQty((p) => ({ ...p, [i.productId]: n }));
                    }}
                  />
                </div>
              );
            })}
          </div>
          <div className="space-y-1.5">
            <Label>Refund via</Label>
            <Select value={refundMethod} onValueChange={setRefundMethod}>
              <SelectTrigger><SelectValue /></SelectTrigger>
              <SelectContent>
                {["cash", "online", "credit"].map((m) => (
                  <SelectItem key={m} value={m}><span className="capitalize">{m}</span></SelectItem>
                ))}
              </SelectContent>
            </Select>
          </div>
          <div className="space-y-1.5">
            <Label>Reason</Label>
            <Input value={reason} onChange={(e) => setReason(e.target.value)} placeholder="e.g. damaged pack" />
          </div>
          <div className="flex justify-between border-t pt-2 text-sm font-semibold">
            <span>Refund</span><span>{inr(refundTotal, { decimals: true })}</span>
          </div>
        </div>
        <DialogFooter>
          <Button variant="outline" onClick={onClose} disabled={submit.isPending}>Cancel</Button>
          <Button disabled={lines.length === 0 || submit.isPending} onClick={() => submit.mutate()}>
            {submit.isPending && <Loader2 className="size-4 animate-spin" />} Return {lines.length || ""}
          </Button>
        </DialogFooter>
      </DialogContent>
    </Dialog>
  );
}
