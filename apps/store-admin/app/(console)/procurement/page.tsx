"use client";

import * as React from "react";
import { useQuery } from "@tanstack/react-query";
import type { ColumnDef } from "@tanstack/react-table";
import { Loader2, Plus, Search, Trash2, Truck } from "lucide-react";
import { api, useApiMutation } from "@/lib/api/hooks";
import { useStore } from "@/lib/store/store-context";
import { PageHeader } from "@/components/page-header";
import { DataTable } from "@/components/data-table";
import { RequirePerm } from "@/components/permission-gate";
import { StatusBadge } from "@/components/status-badge";
import { ProductLink } from "@/components/product-link";
import { Badge } from "@/components/ui/badge";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import { Tabs, TabsList, TabsTrigger, TabsContent } from "@/components/ui/tabs";
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from "@/components/ui/select";
import {
  Dialog, DialogContent, DialogDescription, DialogFooter, DialogHeader, DialogTitle,
} from "@/components/ui/dialog";
import { inr, fmtDate } from "@/lib/utils";

interface Supplier { id: string; name: string; gstin: string; phone: string; email: string; address: string; isActive: boolean; shared: boolean; }
interface Purchase { id: string; reference: string; supplier: string | null; status: string; totalCost: number; postedAt: string | null; createdAt: string; lines: number; }
// A pack (500g / 1kg) is a SEPARATELY-STOCKED SKU, so goods-inward has to name
// one. Receiving without it lands the units in the unallocated pool, where the
// till can't sell them and every pack still reads zero.
interface VariantHit { id: string; label: string; sku: string; barcode: string; onHand: number; }
interface ProductHit { productId: string; name: string; sku: string; brand: string; price: number; onHand: number; variants: VariantHit[]; }
// `lineId` (not productId) identifies a line: one supplier invoice legitimately
// carries the SAME product twice as two lots with different batch/expiry, and
// GRNItem models batch_no/expiry_date per line. Keying by productId silently
// swallowed the second lot.
interface PurchaseLine { lineId: string; productId: string; name: string; variantId: string; variantLabel: string; quantity: string; unitCost: string; batchNo: string; expiryDate: string; }

export default function ProcurementPage() {
  return (
    <RequirePerm perm="procurement.view">
      <ProcurementInner />
    </RequirePerm>
  );
}

function ProcurementInner() {
  const { hasPerm } = useStore();
  const canManage = hasPerm("procurement.manage");
  const [addingSupplier, setAddingSupplier] = React.useState(false);
  const [recording, setRecording] = React.useState(false);

  const suppliersQ = useQuery({ queryKey: ["store", "suppliers"], queryFn: () => api.get<Supplier[]>("/store/suppliers") });
  const purchasesQ = useQuery({ queryKey: ["store", "purchases"], queryFn: () => api.get<Purchase[]>("/store/purchases") });

  const supplierCols: ColumnDef<Supplier, unknown>[] = [
    { header: "Supplier", cell: ({ row }) => <div><div className="font-medium">{row.original.name}</div><div className="text-xs text-muted-foreground">{row.original.gstin || "No GSTIN"}</div></div> },
    { header: "Phone", accessorKey: "phone", cell: ({ row }) => <span className="text-sm">{row.original.phone || "—"}</span> },
    { header: "Address", cell: ({ row }) => <span className="text-sm text-muted-foreground">{row.original.address || "—"}</span> },
    { header: "", id: "shared", cell: ({ row }) => row.original.shared ? <Badge variant="secondary">Shared</Badge> : null },
  ];

  const purchaseCols: ColumnDef<Purchase, unknown>[] = [
    { header: "Invoice", cell: ({ row }) => <span className="font-mono text-sm">{row.original.reference || `GRN-${row.original.id}`}</span> },
    { header: "Supplier", cell: ({ row }) => <span className="text-sm">{row.original.supplier ?? "—"}</span> },
    { header: "Lines", accessorKey: "lines" },
    { header: "Total", cell: ({ row }) => <span className="font-medium">{inr(row.original.totalCost)}</span> },
    { header: "Status", cell: ({ row }) => <StatusBadge status={row.original.status} /> },
    { header: "Date", cell: ({ row }) => <span className="text-xs text-muted-foreground">{fmtDate(row.original.postedAt ?? row.original.createdAt)}</span> },
  ];

  return (
    <div className="space-y-5">
      <PageHeader
        title="Procurement"
        description="Suppliers and the stock you've purchased into the store."
        actions={canManage ? <Button onClick={() => setRecording(true)}><Truck className="size-4" /> Record purchase</Button> : undefined}
      />
      <Tabs defaultValue="purchases">
        <TabsList>
          <TabsTrigger value="purchases">Purchases ({purchasesQ.data?.length ?? 0})</TabsTrigger>
          <TabsTrigger value="suppliers">Suppliers ({suppliersQ.data?.length ?? 0})</TabsTrigger>
        </TabsList>
        <TabsContent value="purchases">
          <DataTable columns={purchaseCols} data={purchasesQ.data ?? []} loading={purchasesQ.isLoading} error={purchasesQ.error ? "Couldn't load purchases." : null} onRetry={() => purchasesQ.refetch()} emptyMessage="No purchases recorded yet. Record a supplier invoice to add stock." />
        </TabsContent>
        <TabsContent value="suppliers">
          <DataTable
            columns={supplierCols} data={suppliersQ.data ?? []} loading={suppliersQ.isLoading}
            error={suppliersQ.error ? "Couldn't load suppliers." : null} onRetry={() => suppliersQ.refetch()}
            emptyMessage="No suppliers yet."
            toolbar={canManage ? <div className="flex justify-end"><Button size="sm" onClick={() => setAddingSupplier(true)}><Plus className="size-4" /> Add supplier</Button></div> : undefined}
          />
        </TabsContent>
      </Tabs>

      {addingSupplier && <SupplierDialog onClose={() => setAddingSupplier(false)} />}
      {recording && <PurchaseDialog suppliers={suppliersQ.data ?? []} onClose={() => setRecording(false)} />}
    </div>
  );
}

function SupplierDialog({ onClose }: { onClose: () => void }) {
  const [form, setForm] = React.useState({ name: "", gstin: "", phone: "", email: "", address: "" });
  const set = (k: keyof typeof form) => (e: React.ChangeEvent<HTMLInputElement>) => setForm((f) => ({ ...f, [k]: e.target.value }));
  const m = useApiMutation<void>(
    () => api.post("/store/suppliers", form),
    { invalidate: [["store", "suppliers"]], successMessage: "Supplier added", onDone: onClose }
  );
  return (
    <Dialog open onOpenChange={(o) => !o && onClose()}>
      <DialogContent className="max-w-md">
        <DialogHeader><DialogTitle>Add supplier</DialogTitle></DialogHeader>
        <div className="space-y-3">
          <div className="space-y-1.5"><Label>Name</Label><Input value={form.name} onChange={set("name")} /></div>
          <div className="grid grid-cols-2 gap-3">
            <div className="space-y-1.5"><Label>GSTIN</Label><Input value={form.gstin} onChange={set("gstin")} /></div>
            <div className="space-y-1.5"><Label>Phone</Label><Input value={form.phone} onChange={set("phone")} /></div>
          </div>
          <div className="space-y-1.5"><Label>Email</Label><Input value={form.email} onChange={set("email")} /></div>
          <div className="space-y-1.5"><Label>Address</Label><Input value={form.address} onChange={set("address")} /></div>
        </div>
        <DialogFooter>
          <Button variant="outline" onClick={onClose} disabled={m.isPending}>Cancel</Button>
          <Button onClick={() => m.mutate()} disabled={m.isPending || !form.name}>
            {m.isPending && <Loader2 className="size-4 animate-spin" />} Add
          </Button>
        </DialogFooter>
      </DialogContent>
    </Dialog>
  );
}

function PurchaseDialog({ suppliers, onClose }: { suppliers: Supplier[]; onClose: () => void }) {
  const [invoiceNumber, setInvoiceNumber] = React.useState("");
  const [supplierId, setSupplierId] = React.useState("");
  const [lines, setLines] = React.useState<PurchaseLine[]>([]);

  const lineSeq = React.useRef(0);
  function addLine(p: ProductHit, variant?: VariantHit) {
    lineSeq.current += 1;
    setLines((l) => [...l, {
      lineId: `L${lineSeq.current}`, productId: p.productId, name: p.name,
      variantId: variant?.id ?? "", variantLabel: variant?.label ?? "",
      quantity: "1",
      // NOT prefilled from p.price — that is the SELLING price. Defaulting purchase
      // cost to retail makes COGS == revenue and every margin/valuation report read
      // zero. The operator must enter what the supplier actually charged.
      unitCost: "", batchNo: "", expiryDate: "",
    }]);
  }
  function updateLine(id: string, k: keyof PurchaseLine, v: string) {
    setLines((l) => l.map((x) => (x.lineId === id ? { ...x, [k]: v } : x)));
  }
  // Every line needs a real qty (>0) and a real cost (>=0) before this invoice can
  // post — the cost drives COGS and the ledger can't be corrected afterwards.
  const num = (v: string) => (v.trim() === "" ? NaN : Number(v));
  const linesValid = lines.every(
    (l) => Number.isFinite(num(l.quantity)) && num(l.quantity) > 0 &&
           Number.isFinite(num(l.unitCost)) && num(l.unitCost) >= 0,
  );

  const m = useApiMutation<void>(
    () => api.post("/store/purchases", {
      invoiceNumber, supplierId: supplierId || undefined,
      // Send the raw strings — the backend validates and 400s per field. Number()
      // turned a fat-fingered "1O.50" into NaN -> null -> a silent ₹0 cost, which
      // permanently poisons weighted-average cost (the ledger is append-only).
      items: lines.map((l) => ({
        productId: l.productId, variantId: l.variantId || undefined,
        quantity: l.quantity.trim(), unitCost: l.unitCost.trim(),
        batchNo: l.batchNo, expiryDate: l.expiryDate || undefined,
      })),
    }),
    { invalidate: [["store", "purchases"], ["store", "inventory"]], successMessage: "Purchase recorded — stock updated", onDone: onClose }
  );

  // NaN-safe: a half-typed/invalid cost must not render the total as "₹NaN".
  const total = lines.reduce((s, l) => {
    const line = Number(l.quantity || 0) * Number(l.unitCost || 0);
    return s + (Number.isFinite(line) ? line : 0);
  }, 0);

  return (
    <Dialog open onOpenChange={(o) => !o && onClose()}>
      <DialogContent className="max-h-[90vh] max-w-2xl overflow-y-auto">
        <DialogHeader>
          <DialogTitle>Record supplier purchase</DialogTitle>
          <DialogDescription>Enter the invoice; posting it increases your store&apos;s stock.</DialogDescription>
        </DialogHeader>

        <div className="space-y-4">
          <div className="grid gap-3 sm:grid-cols-2">
            <div className="space-y-1.5"><Label>Invoice number</Label><Input value={invoiceNumber} onChange={(e) => setInvoiceNumber(e.target.value)} placeholder="INV-1234" /></div>
            <div className="space-y-1.5">
              <Label>Supplier</Label>
              <Select value={supplierId} onValueChange={setSupplierId}>
                <SelectTrigger><SelectValue placeholder="Optional" /></SelectTrigger>
                <SelectContent>{suppliers.map((s) => <SelectItem key={s.id} value={s.id}>{s.name}</SelectItem>)}</SelectContent>
              </Select>
            </div>
          </div>

          <ProductPicker onPick={addLine} />

          {lines.length > 0 && (
            <div className="space-y-2 rounded-lg border p-3">
              {lines.map((l) => (
                <div key={l.lineId} className="grid grid-cols-[1fr_auto] items-start gap-2">
                  <div className="min-w-0">
                    <p className="truncate text-sm">
                      <ProductLink id={l.productId} name={l.name} className="font-medium" />
                      {l.variantLabel && <Badge variant="secondary" className="ml-2 align-middle">{l.variantLabel}</Badge>}
                    </p>
                    <div className="mt-1 grid grid-cols-4 gap-1.5">
                      <LabeledMini label="Qty"><Input className="h-8" inputMode="numeric" value={l.quantity} onChange={(e) => updateLine(l.lineId, "quantity", e.target.value)} /></LabeledMini>
                      <LabeledMini label="Cost"><Input className="h-8" inputMode="numeric" value={l.unitCost} onChange={(e) => updateLine(l.lineId, "unitCost", e.target.value)} /></LabeledMini>
                      <LabeledMini label="Batch"><Input className="h-8" value={l.batchNo} onChange={(e) => updateLine(l.lineId, "batchNo", e.target.value)} /></LabeledMini>
                      <LabeledMini label="Expiry"><Input className="h-8" type="date" value={l.expiryDate} onChange={(e) => updateLine(l.lineId, "expiryDate", e.target.value)} /></LabeledMini>
                    </div>
                  </div>
                  <Button variant="ghost" size="icon" className="size-8" onClick={() => setLines((ls) => ls.filter((x) => x.lineId !== l.lineId))}><Trash2 className="size-4 text-muted-foreground" /></Button>
                </div>
              ))}
              <div className="flex justify-between border-t pt-2 text-sm font-semibold"><span>Total cost</span><span>{inr(total, { decimals: true })}</span></div>
            </div>
          )}
        </div>

        <DialogFooter>
          <Button variant="outline" onClick={onClose} disabled={m.isPending}>Cancel</Button>
          <Button onClick={() => m.mutate()} disabled={m.isPending || lines.length === 0 || !linesValid}>
            {m.isPending && <Loader2 className="size-4 animate-spin" />} Post & add to stock
          </Button>
        </DialogFooter>
      </DialogContent>
    </Dialog>
  );
}

function LabeledMini({ label, children }: { label: string; children: React.ReactNode }) {
  return <div><p className="mb-0.5 text-[10px] uppercase text-muted-foreground">{label}</p>{children}</div>;
}

function ProductPicker({ onPick }: { onPick: (p: ProductHit, variant?: VariantHit) => void }) {
  const [q, setQ] = React.useState("");
  const search = useQuery({
    queryKey: ["store", "products", q],
    queryFn: () => api.get<ProductHit[]>("/store/products", { q }),
    enabled: q.length >= 1,
  });
  return (
    <div className="space-y-2">
      <div className="relative">
        <Search className="absolute left-2.5 top-2.5 size-4 text-muted-foreground" />
        <Input className="pl-8" placeholder="Search or scan a product to add to this invoice…" value={q} onChange={(e) => setQ(e.target.value)} />
      </div>
      {q.length >= 1 && (
        <div className="max-h-56 overflow-y-auto rounded-md border">
          {search.isLoading ? <p className="p-3 text-sm text-muted-foreground">Searching…</p> :
            (search.data ?? []).length === 0 ? <p className="p-3 text-sm text-muted-foreground">No products found.</p> :
            (search.data ?? []).map((p) => (
              (p.variants ?? []).length === 0 ? (
                <button key={p.productId} onClick={() => onPick(p)} className="flex w-full items-center justify-between border-b px-3 py-2 text-left last:border-0 hover:bg-accent">
                  <span className="text-sm">{p.name}</span>
                  <span className="text-xs text-muted-foreground">on hand {p.onHand}</span>
                </button>
              ) : (
                // Packs are counted separately, so there is nothing sensible to
                // receive at product level — the clerk picks the pack itself.
                <div key={p.productId} className="border-b px-3 py-2 last:border-0">
                  <p className="text-sm font-medium">{p.name}</p>
                  <p className="text-[11px] text-muted-foreground">Choose the pack you received</p>
                  <div className="mt-1.5 flex flex-wrap gap-1.5">
                    {p.variants.map((v) => (
                      <button
                        key={v.id}
                        onClick={() => onPick(p, v)}
                        title={v.barcode || v.sku || undefined}
                        className="rounded-md border px-2 py-1 text-xs hover:bg-accent focus-visible:ring-2 focus-visible:ring-ring focus-visible:outline-none"
                      >
                        {v.label}
                        <span className="ml-1.5 text-muted-foreground">on hand {v.onHand}</span>
                      </button>
                    ))}
                  </div>
                </div>
              )
            ))}
        </div>
      )}
    </div>
  );
}
