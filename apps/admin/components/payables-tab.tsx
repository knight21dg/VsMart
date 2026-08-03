"use client";

import * as React from "react";
import { keepPreviousData, useQuery, useQueryClient } from "@tanstack/react-query";
import { type ColumnDef } from "@tanstack/react-table";
import { Banknote, Loader2, Plus, Search } from "lucide-react";
import { toast } from "sonner";
import { api } from "@/lib/api/client";
import { ApiError, type PageMeta } from "@/lib/types";
import { DataTable } from "@/components/data-table";
import { StatusBadge } from "@/components/status-badge";
import { Card } from "@/components/ui/card";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import {
  Dialog, DialogContent, DialogFooter, DialogHeader, DialogTitle,
} from "@/components/ui/dialog";
import {
  Select, SelectContent, SelectItem, SelectTrigger, SelectValue,
} from "@/components/ui/select";
import { inr, titleize } from "@/lib/utils";

interface Invoice {
  id: string;
  supplierId: number | string;
  supplierName: string;
  invoiceNumber: string;
  invoiceDate: string;
  dueDate: string | null;
  subtotal: number | string;
  tax: number | string;
  total: number | string;
  amountPaid: number | string;
  balanceDue: number | string;
  status: string;
  notes: string;
}
interface Payment {
  id: string; amount: number | string; method: string; paidOn: string;
  reference: string; notes: string; createdByName: string | null;
}
interface InvoiceDetail extends Invoice { payments: Payment[] }
interface Aging {
  totalOutstanding: number | string;
  buckets: { bucket: string; count: number; amount: number | string }[];
  bySupplier: { supplierId: string; supplier: string; amount: number | string; invoices: number }[];
}
interface SupplierRef { id: string; name: string }

const STATUSES = [
  { value: "outstanding", label: "Outstanding" },
  { value: "draft", label: "Draft" },
  { value: "paid", label: "Paid" },
  { value: "cancelled", label: "Cancelled" },
  { value: "", label: "All" },
];
const ALL = "__all__";
const n = (v: number | string | null | undefined) => (v == null ? 0 : Number(v));

export function PayablesTab({ active }: { active: boolean }) {
  const qc = useQueryClient();
  const [status, setStatus] = React.useState("outstanding");
  const [search, setSearch] = React.useState("");
  const [q, setQ] = React.useState("");
  const [page, setPage] = React.useState(1);
  const [openId, setOpenId] = React.useState<string | null>(null);
  const [creating, setCreating] = React.useState(false);

  React.useEffect(() => {
    const t = setTimeout(() => { setQ(search.trim()); setPage(1); }, 300);
    return () => clearTimeout(t);
  }, [search]);

  const query = useQuery({
    queryKey: ["ap", "invoices", status, q, page],
    queryFn: () => api.getPaged<Invoice>("/admin/procurement/invoices", {
      status: status || undefined, search: q || undefined, page,
    }),
    enabled: active,
    placeholderData: keepPreviousData,
  });
  const aging = useQuery({
    queryKey: ["ap", "aging"],
    queryFn: () => api.get<Aging>("/admin/procurement/payables"),
    enabled: active,
  });

  const columns: ColumnDef<Invoice, unknown>[] = [
    {
      accessorKey: "invoiceNumber", header: "Invoice",
      cell: ({ row }) => (
        <div className="flex flex-col">
          <span className="font-mono font-medium">{row.original.invoiceNumber}</span>
          <span className="text-xs text-muted-foreground">{row.original.supplierName}</span>
        </div>
      ),
    },
    { accessorKey: "invoiceDate", header: "Dated", cell: ({ row }) => row.original.invoiceDate },
    {
      accessorKey: "dueDate", header: "Due",
      cell: ({ row }) => {
        const due = row.original.dueDate;
        if (!due) return <span className="text-muted-foreground">—</span>;
        const overdue = new Date(due) < new Date() && n(row.original.balanceDue) > 0;
        return <span className={overdue ? "font-medium text-destructive" : ""}>{due}</span>;
      },
    },
    { accessorKey: "total", header: "Total", cell: ({ row }) => <span className="tabular-nums">{inr(n(row.original.total))}</span> },
    {
      accessorKey: "balanceDue", header: "Owed",
      cell: ({ row }) => (
        <span className="tabular-nums font-medium">{inr(n(row.original.balanceDue))}</span>
      ),
    },
    { accessorKey: "status", header: "Status", cell: ({ row }) => <StatusBadge status={row.original.status} /> },
    {
      id: "a", header: "",
      cell: ({ row }) => (
        <Button size="sm" variant="outline" onClick={() => setOpenId(row.original.id)}>Open</Button>
      ),
    },
  ];

  return (
    <>
      <div className="mb-3 grid gap-3 sm:grid-cols-[1fr_auto]">
        <Card className="p-4">
          <div className="flex items-center gap-2 text-sm text-muted-foreground">
            <Banknote className="size-4" /> Outstanding payables
          </div>
          <div className="mt-1 text-2xl font-semibold tabular-nums">
            {aging.isLoading
              ? <Loader2 className="size-5 animate-spin text-muted-foreground" />
              : inr(n(aging.data?.totalOutstanding))}
          </div>
          <div className="mt-3 flex flex-wrap gap-2">
            {(aging.data?.buckets ?? []).map((b) => (
              <div key={b.bucket} className="rounded-md border px-2.5 py-1.5 text-xs">
                <span className="text-muted-foreground">{b.bucket === "current" ? "Current" : `${b.bucket} days`}</span>
                <span className="ml-2 font-medium tabular-nums">{inr(n(b.amount))}</span>
              </div>
            ))}
          </div>
        </Card>
        <div className="flex items-start justify-end">
          <Button onClick={() => setCreating(true)}><Plus /> Record Invoice</Button>
        </div>
      </div>

      <div className="mb-3 flex flex-wrap items-center gap-2">
        <div className="relative min-w-[240px] flex-1">
          <Search className="pointer-events-none absolute left-3 top-1/2 size-4 -translate-y-1/2 text-muted-foreground" />
          <Input value={search} onChange={(e) => setSearch(e.target.value)}
                 placeholder="Search invoice number or supplier…" className="pl-9" />
        </div>
        <Select value={status || ALL} onValueChange={(v) => { setStatus(v === ALL ? "" : v); setPage(1); }}>
          <SelectTrigger className="w-[170px]"><SelectValue /></SelectTrigger>
          <SelectContent>
            {STATUSES.map((s) => (
              <SelectItem key={s.value || ALL} value={s.value || ALL}>{s.label}</SelectItem>
            ))}
          </SelectContent>
        </Select>
      </div>

      <DataTable
        columns={columns}
        data={query.data?.rows ?? []}
        loading={query.isLoading}
        error={query.isError ? "Failed to load invoices." : null}
        onRetry={() => query.refetch()}
        emptyMessage="No supplier invoices match this filter."
        pageMeta={query.data?.meta as PageMeta | undefined}
        page={page}
        onPageChange={setPage}
      />

      {openId && (
        <InvoiceDialog
          invoiceId={openId}
          onClose={() => setOpenId(null)}
          onChanged={() => {
            qc.invalidateQueries({ queryKey: ["ap"] });
          }}
        />
      )}
      {creating && (
        <NewInvoiceDialog
          onClose={() => setCreating(false)}
          onDone={() => { qc.invalidateQueries({ queryKey: ["ap"] }); setCreating(false); }}
        />
      )}
    </>
  );
}

function InvoiceDialog({ invoiceId, onClose, onChanged }: {
  invoiceId: string; onClose: () => void; onChanged: () => void;
}) {
  const detail = useQuery({
    queryKey: ["ap", "invoice", invoiceId],
    queryFn: () => api.get<InvoiceDetail>(`/admin/procurement/invoices/${invoiceId}`),
  });
  const inv = detail.data;
  return (
    <Dialog open onOpenChange={(o) => !o && onClose()}>
      <DialogContent className="max-h-[90vh] max-w-xl overflow-y-auto">
        {detail.isLoading || !inv ? (
          <>
            <DialogHeader><DialogTitle>Supplier invoice</DialogTitle></DialogHeader>
            <div className="grid place-items-center py-10">
              <Loader2 className="size-5 animate-spin text-muted-foreground" />
            </div>
          </>
        ) : (
          <InvoiceBody inv={inv} onClose={onClose} onChanged={onChanged} />
        )}
      </DialogContent>
    </Dialog>
  );
}

function InvoiceBody({ inv, onClose, onChanged }: {
  inv: InvoiceDetail; onClose: () => void; onChanged: () => void;
}) {
  const [amount, setAmount] = React.useState(String(n(inv.balanceDue)));
  const [method, setMethod] = React.useState("bank");
  const [reference, setReference] = React.useState("");
  const [busy, setBusy] = React.useState(false);
  const owed = n(inv.balanceDue);

  async function act(fn: () => Promise<unknown>, ok: string) {
    setBusy(true);
    try { await fn(); toast.success(ok); onChanged(); onClose(); }
    catch (e) { toast.error(e instanceof ApiError ? e.message : "Action failed."); }
    finally { setBusy(false); }
  }

  return (
    <>
      <DialogHeader>
        <DialogTitle className="flex items-center gap-2">
          {inv.invoiceNumber} <StatusBadge status={inv.status} />
        </DialogTitle>
      </DialogHeader>

      <div className="space-y-4">
        <div className="rounded-md border divide-y text-sm">
          <Row label="Supplier" value={inv.supplierName} />
          <Row label="Invoice date" value={inv.invoiceDate} />
          <Row label="Due" value={inv.dueDate ?? "—"} />
          <Row label="Total" value={inr(n(inv.total))} />
          <Row label="Paid" value={inr(n(inv.amountPaid))} />
          <Row label="Still owed" value={inr(owed)} />
        </div>

        {inv.payments.length > 0 && (
          <div>
            <p className="mb-2 text-xs font-medium uppercase tracking-wide text-muted-foreground">
              Payments
            </p>
            <div className="rounded-md border divide-y text-sm">
              {inv.payments.map((p) => (
                <Row key={p.id} label={`${p.paidOn} · ${titleize(p.method)}${p.reference ? ` · ${p.reference}` : ""}`}
                     value={inr(n(p.amount))} />
              ))}
            </div>
          </div>
        )}

        {inv.status === "draft" && (
          <p className="rounded-md border border-amber-500/40 bg-amber-500/10 p-2.5 text-xs text-amber-700 dark:text-amber-400">
            This invoice is a draft. Approve it to add it to payables before paying.
          </p>
        )}

        {owed > 0 && inv.status !== "draft" && inv.status !== "cancelled" && (
          <div className="grid gap-3 rounded-md border p-3 sm:grid-cols-3">
            <div className="space-y-1.5">
              <Label className="text-xs text-muted-foreground">Amount (₹)</Label>
              <Input type="number" value={amount} max={owed}
                     onChange={(e) => setAmount(e.target.value)} />
            </div>
            <div className="space-y-1.5">
              <Label className="text-xs text-muted-foreground">Method</Label>
              <Select value={method} onValueChange={setMethod}>
                <SelectTrigger><SelectValue /></SelectTrigger>
                <SelectContent>
                  {["bank", "upi", "cash", "cheque"].map((m) => (
                    <SelectItem key={m} value={m}>{titleize(m)}</SelectItem>
                  ))}
                </SelectContent>
              </Select>
            </div>
            <div className="space-y-1.5">
              <Label className="text-xs text-muted-foreground">Reference</Label>
              <Input value={reference} onChange={(e) => setReference(e.target.value)}
                     placeholder="UTR / cheque no" />
            </div>
          </div>
        )}
      </div>

      <DialogFooter className="gap-2">
        {inv.status === "draft" && (
          <>
            <Button variant="ghost" className="mr-auto text-destructive hover:text-destructive"
                    disabled={busy}
                    onClick={() => act(() => api.post(`/admin/procurement/invoices/${inv.id}/cancel`, {}), "Invoice cancelled.")}>
              Cancel invoice
            </Button>
            <Button disabled={busy}
                    onClick={() => act(() => api.post(`/admin/procurement/invoices/${inv.id}/approve`, {}), "Approved.")}>
              {busy && <Loader2 className="size-4 animate-spin" />} Approve
            </Button>
          </>
        )}
        {owed > 0 && inv.status !== "draft" && inv.status !== "cancelled" && (
          <>
            <Button variant="outline" onClick={onClose} disabled={busy}>Close</Button>
            <Button disabled={busy || !(Number(amount) > 0) || Number(amount) > owed}
                    onClick={() => act(
                      () => api.post(`/admin/procurement/invoices/${inv.id}/payments`,
                                     { amount: Number(amount), method, reference }),
                      "Payment recorded.")}>
              {busy && <Loader2 className="size-4 animate-spin" />} Record payment
            </Button>
          </>
        )}
        {(owed <= 0 || inv.status === "cancelled") && inv.status !== "draft" && (
          <Button variant="outline" onClick={onClose}>Close</Button>
        )}
      </DialogFooter>
    </>
  );
}

function NewInvoiceDialog({ onClose, onDone }: { onClose: () => void; onDone: () => void }) {
  const [form, setForm] = React.useState<Record<string, string>>({
    invoiceDate: new Date().toISOString().slice(0, 10),
  });
  const [busy, setBusy] = React.useState(false);
  const suppliers = useQuery({
    queryKey: ["ap", "suppliers"],
    queryFn: () => api.getPaged<SupplierRef>("/inventory/suppliers"),
  });

  async function save() {
    setBusy(true);
    try {
      await api.post("/admin/procurement/invoices", {
        supplierId: form.supplierId,
        invoiceNumber: form.invoiceNumber,
        invoiceDate: form.invoiceDate,
        dueDate: form.dueDate || null,
        subtotal: Number(form.subtotal || form.total || 0),
        tax: Number(form.tax || 0),
        total: Number(form.total || 0),
        notes: form.notes || "",
      });
      toast.success("Invoice recorded as a draft.");
      onDone();
    } catch (e) {
      toast.error(e instanceof ApiError ? e.message : "Could not save.");
    } finally {
      setBusy(false);
    }
  }

  const set = (k: string) => (v: string) => setForm({ ...form, [k]: v });

  return (
    <Dialog open onOpenChange={(o) => !o && onClose()}>
      <DialogContent className="max-w-lg">
        <DialogHeader><DialogTitle>Record supplier invoice</DialogTitle></DialogHeader>
        <div className="grid grid-cols-2 gap-3">
          <div className="col-span-2 space-y-1.5">
            <Label className="text-xs text-muted-foreground">Supplier</Label>
            <Select value={form.supplierId ?? ""} onValueChange={set("supplierId")}>
              <SelectTrigger><SelectValue placeholder="Select supplier" /></SelectTrigger>
              <SelectContent>
                {(suppliers.data?.rows ?? []).map((s) => (
                  <SelectItem key={s.id} value={String(s.id)}>{s.name}</SelectItem>
                ))}
              </SelectContent>
            </Select>
          </div>
          <F label="Invoice number"><Input value={form.invoiceNumber ?? ""} onChange={(e) => set("invoiceNumber")(e.target.value)} /></F>
          <F label="Invoice date"><Input type="date" value={form.invoiceDate ?? ""} onChange={(e) => set("invoiceDate")(e.target.value)} /></F>
          <F label="Due date"><Input type="date" value={form.dueDate ?? ""} onChange={(e) => set("dueDate")(e.target.value)} /></F>
          <F label="Subtotal (₹)"><Input type="number" value={form.subtotal ?? ""} onChange={(e) => set("subtotal")(e.target.value)} /></F>
          <F label="Tax (₹)"><Input type="number" value={form.tax ?? ""} onChange={(e) => set("tax")(e.target.value)} /></F>
          <F label="Total (₹)"><Input type="number" value={form.total ?? ""} onChange={(e) => set("total")(e.target.value)} /></F>
        </div>
        <DialogFooter className="gap-2">
          <Button variant="outline" onClick={onClose} disabled={busy}>Cancel</Button>
          <Button onClick={save}
                  disabled={busy || !form.supplierId || !form.invoiceNumber || !(Number(form.total) > 0)}>
            {busy && <Loader2 className="size-4 animate-spin" />} Save draft
          </Button>
        </DialogFooter>
      </DialogContent>
    </Dialog>
  );
}

function Row({ label, value }: { label: string; value: string }) {
  return (
    <div className="flex items-start justify-between gap-4 px-3 py-2">
      <span className="text-muted-foreground">{label}</span>
      <span className="text-right font-medium">{value}</span>
    </div>
  );
}

function F({ label, children }: { label: string; children: React.ReactNode }) {
  return (
    <div className="space-y-1.5">
      <Label className="text-xs text-muted-foreground">{label}</Label>
      {children}
    </div>
  );
}
