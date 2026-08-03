"use client";

import * as React from "react";
import { keepPreviousData, useQuery } from "@tanstack/react-query";
import { type ColumnDef } from "@tanstack/react-table";
import { Boxes, Loader2, Search, SlidersHorizontal } from "lucide-react";
import { api } from "@/lib/api/client";
import { useApiMutation } from "@/lib/api/hooks";
import { InvNav } from "@/components/inventory/inv-nav";
import { PageHeader } from "@/components/page-header";
import { DataTable } from "@/components/data-table";
import { StatCard } from "@/components/stat-card";
import { ProductLink } from "@/components/product-link";
import { Tabs, TabsContent, TabsList, TabsTrigger } from "@/components/ui/tabs";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import { Badge } from "@/components/ui/badge";
import { Switch } from "@/components/ui/switch";
import { Dialog, DialogContent, DialogFooter, DialogHeader, DialogTitle } from "@/components/ui/dialog";
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from "@/components/ui/select";
import type { CursorMeta, PageMeta } from "@/lib/types";
import { inr } from "@/lib/utils";

interface InvProduct { id: string; name: string; brand: string; category: string; price: number; stockCount: number; inStock: boolean; low: boolean }
interface StockItem { id: string; productId: string; productName: string; warehouseId: string; warehouseName: string; quantity: number; reserved: number; lowStockThreshold: number; available: number }
interface LedgerEntry { id: string; productId: string; productName: string; warehouseId: string; warehouseName: string; type: string; quantity: number; balanceAfter: number; note: string; createdAt: string }
interface Valuation { rows: { productId: string; name: string; warehouseId: string; warehouseName: string; quantity: number; unitCost: number; value: number }[]; total: number; skuCount: number }

export default function InventoryOperationsPage() {
  const [tab, setTab] = React.useState("products");
  return (
    <>
      <PageHeader title="Inventory Operations" description="Raw stock, ledger and valuation." />
      <InvNav />
      <Tabs value={tab} onValueChange={setTab}>
        <TabsList>
          <TabsTrigger value="products">Products</TabsTrigger>
          <TabsTrigger value="stock">Stock Levels</TabsTrigger>
          <TabsTrigger value="ledger">Ledger</TabsTrigger>
          <TabsTrigger value="valuation">Valuation</TabsTrigger>
        </TabsList>
        <TabsContent value="products"><ProductsTab active={tab === "products"} /></TabsContent>
        <TabsContent value="stock"><StockTab active={tab === "stock"} /></TabsContent>
        <TabsContent value="ledger"><LedgerTab active={tab === "ledger"} /></TabsContent>
        <TabsContent value="valuation"><ValuationTab active={tab === "valuation"} /></TabsContent>
      </Tabs>
    </>
  );
}

function ProductsTab({ active }: { active: boolean }) {
  const [search, setSearch] = React.useState("");
  const [q, setQ] = React.useState("");
  const [lowOnly, setLowOnly] = React.useState(false);
  const [adjust, setAdjust] = React.useState<InvProduct | null>(null);
  const [mode, setMode] = React.useState<"set" | "delta">("delta");
  const [value, setValue] = React.useState("");
  const [reason, setReason] = React.useState("");

  const [page, setPage] = React.useState(1);

  React.useEffect(() => {
    const t = setTimeout(() => setQ(search.trim()), 300);
    return () => clearTimeout(t);
  }, [search]);

  // Any filter change must return to page 1 — staying on page N of a now-shorter
  // result set would show an empty table. Adjusted DURING render (React's "reset
  // state when a value changes" pattern) because this project lints
  // setState-inside-an-effect as an error.
  const filterKey = `${q}|${lowOnly}`;
  const [prevFilterKey, setPrevFilterKey] = React.useState(filterKey);
  if (prevFilterKey !== filterKey) {
    setPrevFilterKey(filterKey);
    setPage(1);
  }

  const query = useQuery({
    queryKey: ["admin", "inventory", { q, lowOnly }, page],
    queryFn: () => api.getPaged<InvProduct>("/admin/inventory", { q: q || undefined, low_stock: lowOnly ? 1 : undefined, page }),
    enabled: active,
    placeholderData: keepPreviousData,
  });

  const save = useApiMutation(
    (vars: { id: string; body: Record<string, unknown> }) => api.post(`/admin/inventory/${vars.id}/adjust`, vars.body),
    { invalidate: [["admin", "inventory"], ["inv"]], successMessage: "Stock adjusted.", onDone: () => setAdjust(null) }
  );

  const columns: ColumnDef<InvProduct, unknown>[] = [
    { accessorKey: "name", header: "Product", cell: ({ row }) => <ProductLink id={row.original.id} name={row.original.name} className="font-medium" /> },
    { accessorKey: "brand", header: "Brand" },
    { accessorKey: "category", header: "Category", cell: ({ row }) => <span className="text-muted-foreground">{row.original.category}</span> },
    { accessorKey: "price", header: "Price", cell: ({ row }) => inr(row.original.price) },
    { accessorKey: "stockCount", header: "Stock", cell: ({ row }) => <span className="tabular-nums">{row.original.stockCount}</span> },
    {
      id: "status",
      header: "Status",
      cell: ({ row }) => (!row.original.inStock ? <Badge variant="destructive">Out</Badge> : row.original.low ? <Badge variant="warning">Low</Badge> : <Badge variant="success">OK</Badge>),
    },
    {
      id: "actions",
      header: "",
      cell: ({ row }) => (
        <Button variant="outline" size="sm" onClick={() => { setAdjust(row.original); setMode("delta"); setValue(""); setReason(""); }}>
          <SlidersHorizontal /> Adjust
        </Button>
      ),
    },
  ];

  return (
    <>
      <DataTable
        columns={columns}
        data={query.data?.rows ?? []}
        loading={query.isLoading}
        error={query.isError ? "Failed to load inventory." : null}
        onRetry={() => query.refetch()}
        pageMeta={query.data?.meta as PageMeta | undefined}
        page={page}
        onPageChange={setPage}
        toolbar={
          <div className="flex flex-wrap items-center gap-3">
            <div className="relative max-w-xs">
              <Search className="pointer-events-none absolute left-3 top-1/2 size-4 -translate-y-1/2 text-muted-foreground" />
              <Input value={search} onChange={(e) => setSearch(e.target.value)} placeholder="Search products…" className="pl-9" />
            </div>
            <label className="flex items-center gap-2 text-sm"><Switch checked={lowOnly} onCheckedChange={setLowOnly} /> Low stock only</label>
          </div>
        }
      />
      <Dialog open={!!adjust} onOpenChange={(o) => !o && setAdjust(null)}>
        <DialogContent className="max-w-md">
          <DialogHeader><DialogTitle className="flex items-center gap-2"><Boxes className="size-4" /> Adjust — {adjust?.name}</DialogTitle></DialogHeader>
          <div className="space-y-3">
            <p className="text-sm text-muted-foreground">Current stock: <span className="font-medium text-foreground">{adjust?.stockCount}</span></p>
            <div className="space-y-1.5">
              <Label>Mode</Label>
              <Select value={mode} onValueChange={(v) => setMode(v as "set" | "delta")}>
                <SelectTrigger><SelectValue /></SelectTrigger>
                <SelectContent>
                  <SelectItem value="delta">Adjust by (+/−)</SelectItem>
                  <SelectItem value="set">Set absolute</SelectItem>
                </SelectContent>
              </Select>
            </div>
            <div className="space-y-1.5"><Label>{mode === "set" ? "New count" : "Change (e.g. -5 or 10)"}</Label><Input type="number" value={value} onChange={(e) => setValue(e.target.value)} /></div>
            <div className="space-y-1.5"><Label>Reason</Label><Input value={reason} onChange={(e) => setReason(e.target.value)} placeholder="restock / damage / correction" /></div>
          </div>
          <DialogFooter className="gap-2">
            <Button variant="outline" onClick={() => setAdjust(null)} disabled={save.isPending}>Cancel</Button>
            <Button disabled={save.isPending || value === ""} onClick={() => adjust && save.mutate({ id: adjust.id, body: { [mode]: Number(value), reason } })}>
              {save.isPending && <Loader2 className="size-4 animate-spin" />} Apply
            </Button>
          </DialogFooter>
        </DialogContent>
      </Dialog>
    </>
  );
}

function StockTab({ active }: { active: boolean }) {
  const [page, setPage] = React.useState(1);
  const query = useQuery({
    queryKey: ["inventory", "stock", page],
    queryFn: () => api.getPaged<StockItem>("/inventory/stock", { page }),
    enabled: active,
    placeholderData: keepPreviousData,
  });
  const columns: ColumnDef<StockItem, unknown>[] = [
    { accessorKey: "productName", header: "Product", cell: ({ row }) => <ProductLink id={row.original.productId} name={row.original.productName} className="font-medium" /> },
    { accessorKey: "warehouseName", header: "Warehouse", cell: ({ row }) => <span className="text-muted-foreground">{row.original.warehouseName}</span> },
    { accessorKey: "quantity", header: "On Hand", cell: ({ row }) => <span className="tabular-nums">{row.original.quantity}</span> },
    { accessorKey: "reserved", header: "Reserved", cell: ({ row }) => <span className="tabular-nums">{row.original.reserved}</span> },
    { accessorKey: "available", header: "Available", cell: ({ row }) => <span className="font-medium tabular-nums">{row.original.available}</span> },
    { id: "low", header: "Status", cell: ({ row }) => (row.original.available <= row.original.lowStockThreshold ? <Badge variant="warning">Low</Badge> : <Badge variant="success">OK</Badge>) },
  ];
  return (
    <DataTable columns={columns} data={query.data?.rows ?? []} loading={query.isLoading} error={query.isError ? "Failed to load stock." : null} onRetry={() => query.refetch()} pageMeta={query.data?.meta as PageMeta | undefined} page={page} onPageChange={setPage} emptyMessage="No stock records." />
  );
}

function LedgerTab({ active }: { active: boolean }) {
  const [cursor, setCursor] = React.useState<string | null>(null);
  const query = useQuery({ queryKey: ["inventory", "ledger", cursor], queryFn: () => api.getPaged<LedgerEntry>("/inventory/ledger", { cursor: cursor || undefined }), enabled: active, placeholderData: keepPreviousData });
  const meta = query.data?.meta as CursorMeta | undefined;
  const extract = (u: string | null) => { if (!u) return null; try { return new URL(u).searchParams.get("cursor"); } catch { return u; } };
  const columns: ColumnDef<LedgerEntry, unknown>[] = [
    { accessorKey: "createdAt", header: "Time", cell: ({ row }) => <span className="text-xs text-muted-foreground">{new Date(row.original.createdAt).toLocaleString("en-IN")}</span> },
    { accessorKey: "productName", header: "Product", cell: ({ row }) => <ProductLink id={row.original.productId} name={row.original.productName} className="font-medium" /> },
    { accessorKey: "warehouseName", header: "Warehouse", cell: ({ row }) => <span className="text-muted-foreground">{row.original.warehouseName}</span> },
    { accessorKey: "type", header: "Type", cell: ({ row }) => <Badge variant="secondary">{row.original.type}</Badge> },
    { accessorKey: "quantity", header: "Qty", cell: ({ row }) => <span className={"tabular-nums " + (row.original.quantity < 0 ? "text-destructive" : "text-[var(--color-success)]")}>{row.original.quantity > 0 ? "+" : ""}{row.original.quantity}</span> },
    { accessorKey: "balanceAfter", header: "Balance", cell: ({ row }) => <span className="tabular-nums">{row.original.balanceAfter}</span> },
    { accessorKey: "note", header: "Note", cell: ({ row }) => <span className="text-muted-foreground">{row.original.note || "—"}</span> },
  ];
  return (
    <DataTable columns={columns} data={query.data?.rows ?? []} loading={query.isLoading} error={query.isError ? "Failed to load ledger." : null} onRetry={() => query.refetch()} cursorMeta={meta ? { pageSize: meta.pageSize, nextCursor: extract(meta.nextCursor), previousCursor: extract(meta.previousCursor) } : undefined} onCursor={setCursor} emptyMessage="No ledger movements." />
  );
}

function ValuationTab({ active }: { active: boolean }) {
  const query = useQuery({ queryKey: ["inventory", "valuation"], queryFn: () => api.get<Valuation>("/inventory/valuation"), enabled: active });
  const v = query.data;
  const columns: ColumnDef<Valuation["rows"][number], unknown>[] = [
    { accessorKey: "name", header: "Product", cell: ({ row }) => <ProductLink id={row.original.productId} name={row.original.name} className="font-medium" /> },
    { accessorKey: "warehouseName", header: "Warehouse", cell: ({ row }) => <span className="text-muted-foreground">{row.original.warehouseName}</span> },
    { accessorKey: "quantity", header: "Qty", cell: ({ row }) => <span className="tabular-nums">{row.original.quantity}</span> },
    { accessorKey: "unitCost", header: "Unit Cost", cell: ({ row }) => inr(row.original.unitCost) },
    { accessorKey: "value", header: "Value", cell: ({ row }) => <span className="font-medium">{inr(row.original.value)}</span> },
  ];
  return (
    <div className="space-y-4">
      <div className="grid grid-cols-2 gap-4 sm:max-w-md">
        <StatCard label="Total Stock Value" value={inr(v?.total)} loading={query.isLoading} accent="green" />
        <StatCard label="SKUs" value={v?.skuCount ?? 0} loading={query.isLoading} accent="slate" />
      </div>
      <DataTable columns={columns} data={v?.rows ?? []} loading={query.isLoading} error={query.isError ? "Failed to load valuation." : null} onRetry={() => query.refetch()} emptyMessage="No valuation data." />
    </div>
  );
}
