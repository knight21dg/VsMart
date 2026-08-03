"use client";

import * as React from "react";
import { useParams, useRouter } from "next/navigation";
import { keepPreviousData, useQuery } from "@tanstack/react-query";
import { type ColumnDef } from "@tanstack/react-table";
import { ArrowLeft, Loader2, Pencil, Plus, Truck } from "lucide-react";
import { api } from "@/lib/api/client";
import { useApiMutation } from "@/lib/api/hooks";
import { PageHeader } from "@/components/page-header";
import { StatCard } from "@/components/stat-card";
import { DataTable } from "@/components/data-table";
import { Tabs, TabsContent, TabsList, TabsTrigger } from "@/components/ui/tabs";
import { Badge } from "@/components/ui/badge";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import { Switch } from "@/components/ui/switch";
import { StatusBadge, BoolBadge } from "@/components/status-badge";
import { ProductLink } from "@/components/product-link";
import { Dialog, DialogContent, DialogFooter, DialogHeader, DialogTitle } from "@/components/ui/dialog";
import type { CursorMeta, PageMeta } from "@/lib/types";
import type { StoreRollup } from "@/lib/inventory";
import { fmtDate, inr } from "@/lib/utils";

interface StoreProductRow {
  productId: string;
  name: string;
  brand: string;
  onHand: number;
  reserved: number;
  available: number;
  lowStockThreshold: number;
  isAvailable: boolean;
  globalPrice: number;
  storePrice: number | null;
  effectivePrice: number;
  mrp: number;
}
interface LedgerEntry { id: string; productId: string; productName: string; type: string; quantity: number; balanceAfter: number; note: string; createdAt: string }
interface Supplier { id: string; name: string; gstin: string; phone: string; email: string; isActive: boolean }
interface PurchaseOrder { id: string; supplierName: string; warehouseId: string; status: string; total: number; receivedAt: string | null }

export default function StoreWorkspacePage() {
  const { wid } = useParams<{ wid: string }>();
  const router = useRouter();
  const [tab, setTab] = React.useState("products");

  const stores = useQuery({ queryKey: ["inv", "stores"], queryFn: () => api.get<StoreRollup[]>("/inventory/stores") });
  const store = (stores.data ?? []).find((s) => s.warehouseId === wid);

  return (
    <>
      <Button variant="ghost" size="sm" className="-ml-2 w-fit" onClick={() => router.back()}>
        <ArrowLeft /> Back
      </Button>
      <PageHeader title={store?.storeName ?? "Store"} description="Store inventory workspace." />

      <div className="grid grid-cols-2 gap-4 md:grid-cols-4 lg:grid-cols-6">
        <StatCard label="Inventory Value" value={inr(store?.inventoryValue)} accent="green" loading={stores.isLoading} />
        <StatCard label="Products" value={store?.skuCount ?? 0} loading={stores.isLoading} />
        <StatCard label="Out of Stock" value={store?.outOfStock ?? 0} accent={store?.outOfStock ? "red" : "slate"} loading={stores.isLoading} />
        <StatCard label="Low Stock" value={store?.lowStock ?? 0} accent={store?.lowStock ? "gold" : "slate"} loading={stores.isLoading} />
        <StatCard label="Fill Rate" value={`${store?.fillRate ?? 0}%`} accent="teal" loading={stores.isLoading} />
        <StatCard label="Health" value={store?.healthScore ?? 0} accent={(store?.healthScore ?? 0) >= 90 ? "green" : "gold"} loading={stores.isLoading} />
      </div>

      <Tabs value={tab} onValueChange={setTab}>
        <TabsList className="flex-wrap">
          <TabsTrigger value="products">Products</TabsTrigger>
          <TabsTrigger value="suppliers">Suppliers</TabsTrigger>
          <TabsTrigger value="purchases">Purchases</TabsTrigger>
          <TabsTrigger value="ledger">Ledger</TabsTrigger>
        </TabsList>
        <TabsContent value="products"><ProductsTab wid={wid} active={tab === "products"} /></TabsContent>
        <TabsContent value="suppliers"><SuppliersTab storeId={store?.storeId} active={tab === "suppliers"} /></TabsContent>
        <TabsContent value="purchases"><PurchasesTab wid={wid} active={tab === "purchases"} /></TabsContent>
        <TabsContent value="ledger"><LedgerTab wid={wid} active={tab === "ledger"} /></TabsContent>
      </Tabs>
    </>
  );
}

function ProductsTab({ wid, active }: { wid: string; active: boolean }) {
  const [edit, setEdit] = React.useState<StoreProductRow | null>(null);
  const [price, setPrice] = React.useState("");
  const [reorder, setReorder] = React.useState("");
  const [avail, setAvail] = React.useState(true);

  const query = useQuery({
    queryKey: ["inv", "store-products", wid],
    queryFn: () => api.get<StoreProductRow[]>(`/inventory/stores/${wid}/products`),
    enabled: active,
  });
  const save = useApiMutation(
    (body: Record<string, unknown>) => api.patch(`/inventory/stores/${wid}/products/${edit!.productId}`, body),
    { invalidate: [["inv", "store-products", wid]], successMessage: "Updated.", onDone: () => setEdit(null) }
  );

  function openEdit(r: StoreProductRow) {
    setEdit(r);
    setPrice(r.storePrice != null ? String(r.storePrice) : "");
    setReorder(String(r.lowStockThreshold));
    setAvail(r.isAvailable);
  }

  const columns: ColumnDef<StoreProductRow, unknown>[] = [
    { accessorKey: "name", header: "Product", cell: ({ row }) => <ProductLink id={row.original.productId} name={row.original.name} className="font-medium" /> },
    { accessorKey: "available", header: "Available", cell: ({ row }) => <span className="tabular-nums">{row.original.available}</span> },
    { accessorKey: "lowStockThreshold", header: "Reorder At", cell: ({ row }) => <span className="tabular-nums">{row.original.lowStockThreshold}</span> },
    {
      id: "price",
      header: "Store Price",
      cell: ({ row }) => (
        <span>
          {inr(row.original.effectivePrice)}
          {row.original.storePrice == null && <span className="ml-1 text-xs text-muted-foreground">(global)</span>}
        </span>
      ),
    },
    { accessorKey: "mrp", header: "MRP", cell: ({ row }) => inr(row.original.mrp) },
    { accessorKey: "isAvailable", header: "Carried", cell: ({ row }) => <BoolBadge value={row.original.isAvailable} trueLabel="Yes" falseLabel="No" /> },
    { id: "actions", header: "", cell: ({ row }) => <Button variant="outline" size="sm" onClick={() => openEdit(row.original)}><Pencil className="size-3.5" /> Edit</Button> },
  ];

  return (
    <>
      <DataTable
        columns={columns}
        data={query.data ?? []}
        loading={query.isLoading}
        error={query.isError ? "Failed to load store products." : null}
        onRetry={() => query.refetch()}
        emptyMessage="This store carries no products yet."
      />
      <Dialog open={!!edit} onOpenChange={(o) => !o && setEdit(null)}>
        <DialogContent className="max-w-md">
          <DialogHeader><DialogTitle>{edit?.name}</DialogTitle></DialogHeader>
          <div className="space-y-3">
            <label className="flex items-center justify-between text-sm">
              <span>Carried by this store</span>
              <Switch checked={avail} onCheckedChange={setAvail} />
            </label>
            <div className="space-y-1.5">
              <Label>Store selling price (₹)</Label>
              <Input type="number" value={price} onChange={(e) => setPrice(e.target.value)} placeholder={`Global ${inr(edit?.globalPrice)}`} />
              <p className="text-xs text-muted-foreground">Leave blank to use the global price ({inr(edit?.globalPrice)}). Applies to customers when store pricing is enabled.</p>
            </div>
            <div className="space-y-1.5">
              <Label>Reorder at (units)</Label>
              <Input type="number" value={reorder} onChange={(e) => setReorder(e.target.value)} />
            </div>
          </div>
          <DialogFooter className="gap-2">
            <Button variant="outline" onClick={() => setEdit(null)} disabled={save.isPending}>Cancel</Button>
            <Button
              disabled={save.isPending}
              onClick={() => save.mutate({ isAvailable: avail, sellingPrice: price === "" ? null : Number(price), reorderLevel: reorder === "" ? null : Number(reorder) })}
            >
              {save.isPending && <Loader2 className="size-4 animate-spin" />} Save
            </Button>
          </DialogFooter>
        </DialogContent>
      </Dialog>
    </>
  );
}

function SuppliersTab({ storeId, active }: { storeId?: string; active: boolean }) {
  const [open, setOpen] = React.useState(false);
  const [form, setForm] = React.useState<Partial<Supplier>>({});
  const query = useQuery({
    queryKey: ["inv", "store-suppliers", storeId],
    queryFn: () => api.getPaged<Supplier>("/inventory/suppliers", { store: storeId }),
    enabled: active && !!storeId,
  });
  const save = useApiMutation(
    (body: Record<string, unknown>) => api.post("/inventory/suppliers", { ...body, store: storeId ? Number(storeId) : null }),
    { invalidate: [["inv", "store-suppliers", storeId]], successMessage: "Supplier added.", onDone: () => setOpen(false) }
  );
  const columns: ColumnDef<Supplier, unknown>[] = [
    { accessorKey: "name", header: "Supplier", cell: ({ row }) => <span className="font-medium">{row.original.name}</span> },
    { accessorKey: "gstin", header: "GSTIN", cell: ({ row }) => <span className="font-mono text-xs">{row.original.gstin || "—"}</span> },
    { accessorKey: "phone", header: "Phone" },
    { accessorKey: "isActive", header: "Active", cell: ({ row }) => <BoolBadge value={row.original.isActive} /> },
  ];
  return (
    <>
      <div className="mb-3 flex justify-end"><Button onClick={() => { setForm({}); setOpen(true); }}><Plus /> New Supplier</Button></div>
      <DataTable columns={columns} data={query.data?.rows ?? []} loading={query.isLoading} error={query.isError ? "Failed to load." : null} onRetry={() => query.refetch()} emptyMessage="No suppliers for this store." />
      <Dialog open={open} onOpenChange={setOpen}>
        <DialogContent>
          <DialogHeader><DialogTitle className="flex items-center gap-2"><Truck className="size-4" /> New Supplier</DialogTitle></DialogHeader>
          <div className="grid grid-cols-2 gap-3">
            <div className="col-span-2 space-y-1.5"><Label>Name</Label><Input value={form.name ?? ""} onChange={(e) => setForm({ ...form, name: e.target.value })} /></div>
            <div className="space-y-1.5"><Label>GSTIN</Label><Input value={form.gstin ?? ""} onChange={(e) => setForm({ ...form, gstin: e.target.value })} /></div>
            <div className="space-y-1.5"><Label>Phone</Label><Input value={form.phone ?? ""} onChange={(e) => setForm({ ...form, phone: e.target.value })} /></div>
            <div className="col-span-2 space-y-1.5"><Label>Email</Label><Input value={form.email ?? ""} onChange={(e) => setForm({ ...form, email: e.target.value })} /></div>
          </div>
          <DialogFooter className="gap-2">
            <Button variant="outline" onClick={() => setOpen(false)} disabled={save.isPending}>Cancel</Button>
            <Button onClick={() => save.mutate(form)} disabled={save.isPending || !form.name}>{save.isPending && <Loader2 className="size-4 animate-spin" />} Save</Button>
          </DialogFooter>
        </DialogContent>
      </Dialog>
    </>
  );
}

function PurchasesTab({ wid, active }: { wid: string; active: boolean }) {
  const query = useQuery({ queryKey: ["inv", "po-all"], queryFn: () => api.getPaged<PurchaseOrder>("/inventory/purchase-orders"), enabled: active });
  const rows = (query.data?.rows ?? []).filter((p) => p.warehouseId === wid);
  const columns: ColumnDef<PurchaseOrder, unknown>[] = [
    { accessorKey: "id", header: "PO", cell: ({ row }) => <span className="font-mono text-xs">#{row.original.id}</span> },
    { accessorKey: "supplierName", header: "Supplier", cell: ({ row }) => <span className="font-medium">{row.original.supplierName || "—"}</span> },
    { accessorKey: "status", header: "Status", cell: ({ row }) => <StatusBadge status={row.original.status} /> },
    { accessorKey: "total", header: "Total", cell: ({ row }) => inr(row.original.total) },
    { accessorKey: "receivedAt", header: "Received", cell: ({ row }) => fmtDate(row.original.receivedAt, true) },
  ];
  return <DataTable columns={columns} data={rows} loading={query.isLoading} error={query.isError ? "Failed to load." : null} onRetry={() => query.refetch()} emptyMessage="No purchases for this store." />;
}

function LedgerTab({ wid, active }: { wid: string; active: boolean }) {
  const [cursor, setCursor] = React.useState<string | null>(null);
  const query = useQuery({ queryKey: ["inv", "store-ledger", wid, cursor], queryFn: () => api.getPaged<LedgerEntry>("/inventory/ledger", { warehouse: wid, cursor: cursor || undefined }), enabled: active, placeholderData: keepPreviousData });
  const meta = query.data?.meta as CursorMeta | undefined;
  const extract = (u: string | null) => { if (!u) return null; try { return new URL(u).searchParams.get("cursor"); } catch { return u; } };
  const columns: ColumnDef<LedgerEntry, unknown>[] = [
    { accessorKey: "createdAt", header: "Time", cell: ({ row }) => <span className="text-xs text-muted-foreground">{new Date(row.original.createdAt).toLocaleString("en-IN")}</span> },
    { accessorKey: "productName", header: "Product", cell: ({ row }) => <ProductLink id={row.original.productId} name={row.original.productName} className="font-medium" /> },
    { accessorKey: "type", header: "Type", cell: ({ row }) => <Badge variant="secondary">{row.original.type}</Badge> },
    { accessorKey: "quantity", header: "Qty", cell: ({ row }) => <span className={"tabular-nums " + (row.original.quantity < 0 ? "text-destructive" : "text-[var(--color-success)]")}>{row.original.quantity > 0 ? "+" : ""}{row.original.quantity}</span> },
    { accessorKey: "balanceAfter", header: "Balance", cell: ({ row }) => <span className="tabular-nums">{row.original.balanceAfter}</span> },
  ];
  return <DataTable columns={columns} data={query.data?.rows ?? []} loading={query.isLoading} error={query.isError ? "Failed to load." : null} onRetry={() => query.refetch()} cursorMeta={meta ? { pageSize: meta.pageSize, nextCursor: extract(meta.nextCursor), previousCursor: extract(meta.previousCursor) } : undefined} onCursor={setCursor} emptyMessage="No movements." />;
}
