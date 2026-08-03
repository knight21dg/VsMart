"use client";

import * as React from "react";
import { useRouter } from "next/navigation";
import { useQuery } from "@tanstack/react-query";
import type { ColumnDef } from "@tanstack/react-table";
import { Loader2, Pencil, Plus, SlidersHorizontal, Upload } from "lucide-react";
import { api, useApiMutation } from "@/lib/api/hooks";
import { useStore } from "@/lib/store/store-context";
import { PageHeader } from "@/components/page-header";
import { DataTable } from "@/components/data-table";
import { ImageUpload } from "@/components/image-upload";
import { VariantsEditor, type VariantRow } from "@/components/variants-editor";
import { RequirePerm } from "@/components/permission-gate";
import { ProductLink } from "@/components/product-link";
import { Badge } from "@/components/ui/badge";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import { Textarea } from "@/components/ui/textarea";
import { Tabs, TabsList, TabsTrigger, TabsContent } from "@/components/ui/tabs";
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from "@/components/ui/select";
import {
  Dialog, DialogContent, DialogDescription, DialogFooter, DialogHeader, DialogTitle,
} from "@/components/ui/dialog";
import { inr, fmtDate } from "@/lib/utils";

interface StockRow {
  productId: string; variantId: string | null; variantLabel: string | null;
  unallocated?: boolean;
  name: string; sku: string; brand: string; private?: boolean;
  current: number; reserved: number; available: number; damaged: number;
  reorderLevel: number; sellingPrice: number; expiryDate: string | null; lowStock: boolean;
}
interface ExpiryRow {
  batchId: string; productId: string; name: string; batchNo: string; quantity: number;
  expiryDate: string; daysLeft: number; expired: boolean;
}

export default function InventoryPage() {
  return (
    <RequirePerm perm="inventory.view">
      <InventoryInner />
    </RequirePerm>
  );
}

function InventoryInner() {
  const router = useRouter();
  const { hasPerm } = useStore();
  const canManage = hasPerm("inventory.manage");
  const [adjust, setAdjust] = React.useState<StockRow | null>(null);
  const [editId, setEditId] = React.useState<string | null>(null);
  const [stocking, setStocking] = React.useState(false);
  const [search, setSearch] = React.useState("");

  const stockQ = useQuery({ queryKey: ["store", "inventory"], queryFn: () => api.get<StockRow[]>("/store/inventory") });
  const expiryQ = useQuery({ queryKey: ["store", "inventory", "expiry"], queryFn: () => api.get<ExpiryRow[]>("/store/inventory/expiry") });

  const rows = (stockQ.data ?? []).filter(
    (r) => !search || r.name.toLowerCase().includes(search.toLowerCase()) || (r.sku || "").toLowerCase().includes(search.toLowerCase())
  );
  const lowRows = rows.filter((r) => r.lowStock);

  const stockColumns: ColumnDef<StockRow, unknown>[] = [
    {
      header: "Product",
      cell: ({ row }) => (
        <div>
          <div className="flex items-center gap-1.5 font-medium">
            {row.original.name}
            {row.original.private && <Badge variant="secondary">Store item</Badge>}
            {row.original.unallocated && <Badge variant="outline">Unallocated</Badge>}
          </div>
          <div className="text-xs text-muted-foreground">{row.original.sku || row.original.brand}</div>
        </div>
      ),
    },
    { header: "Available", cell: ({ row }) => (
      <span className={row.original.lowStock ? "font-semibold text-destructive" : "font-medium"}>{row.original.available}</span>
    ) },
    { header: "Reserved", accessorKey: "reserved", cell: ({ row }) => <span className="text-sm text-muted-foreground">{row.original.reserved}</span> },
    { header: "Damaged", accessorKey: "damaged", cell: ({ row }) => <span className="text-sm text-muted-foreground">{row.original.damaged}</span> },
    { header: "Reorder", accessorKey: "reorderLevel", cell: ({ row }) => <span className="text-sm text-muted-foreground">{row.original.reorderLevel}</span> },
    { header: "Price", cell: ({ row }) => <span className="text-sm">{inr(row.original.sellingPrice)}</span> },
    { header: "Expiry", cell: ({ row }) => <span className="text-xs text-muted-foreground">{row.original.expiryDate ? fmtDate(row.original.expiryDate) : "—"}</span> },
    { header: "", id: "status", cell: ({ row }) => row.original.lowStock ? <Badge variant="destructive">Low</Badge> : <Badge variant="success">OK</Badge> },
    {
      header: "", id: "actions",
      cell: ({ row }) => canManage ? (
        <div className="flex justify-end gap-1">
          <Button variant="ghost" size="sm" onClick={() => row.original.private
            ? router.push(`/inventory/products/${row.original.productId}/edit`)
            : setEditId(row.original.productId)}>
            <Pencil className="size-3.5" /> Edit
          </Button>
          <Button variant="outline" size="sm" onClick={() => setAdjust(row.original)}>
            <SlidersHorizontal className="size-3.5" /> Adjust
          </Button>
        </div>
      ) : null,
    },
  ];

  const expiryColumns: ColumnDef<ExpiryRow, unknown>[] = [
    { header: "Product", cell: ({ row }) => <div><div><ProductLink id={row.original.productId} name={row.original.name} className="font-medium" /></div><div className="text-xs text-muted-foreground">#{row.original.batchNo}</div></div> },
    { header: "Qty", accessorKey: "quantity" },
    { header: "Expiry", cell: ({ row }) => <span className="text-sm">{fmtDate(row.original.expiryDate)}</span> },
    { header: "Status", cell: ({ row }) => row.original.expired ? <Badge variant="destructive">Expired</Badge> : <Badge variant="warning">{row.original.daysLeft}d left</Badge> },
  ];

  const toolbar = (
    <Input placeholder="Search product or SKU…" value={search} onChange={(e) => setSearch(e.target.value)} className="max-w-xs" />
  );

  return (
    <div className="space-y-5">
      <PageHeader
        title="Inventory"
        description="Your store's stock — on hand, low stock and expiry."
        actions={canManage ? (
          <div className="flex gap-2">
            <Button variant="outline" onClick={() => router.push("/inventory/import")}>
              <Upload className="size-4" /> Import
            </Button>
            <Button variant="outline" onClick={() => setStocking(true)}>Stock item</Button>
            <Button onClick={() => router.push("/inventory/products/new")}><Plus className="size-4" /> Add product</Button>
          </div>
        ) : null}
      />
      <Tabs defaultValue="stock">
        <TabsList>
          <TabsTrigger value="stock">Stock ({rows.length})</TabsTrigger>
          <TabsTrigger value="low">Low Stock ({lowRows.length})</TabsTrigger>
          <TabsTrigger value="expiry">Expiry ({expiryQ.data?.length ?? 0})</TabsTrigger>
        </TabsList>
        <TabsContent value="stock">
          <DataTable columns={stockColumns} data={rows} loading={stockQ.isLoading} error={stockQ.error ? "Couldn't load stock." : null} onRetry={() => stockQ.refetch()} toolbar={toolbar} emptyMessage="No products stocked yet." />
        </TabsContent>
        <TabsContent value="low">
          <DataTable columns={stockColumns} data={lowRows} loading={stockQ.isLoading} emptyMessage="Nothing below reorder level." />
        </TabsContent>
        <TabsContent value="expiry">
          <DataTable columns={expiryColumns} data={expiryQ.data ?? []} loading={expiryQ.isLoading} error={expiryQ.error ? "Couldn't load expiry." : null} onRetry={() => expiryQ.refetch()} emptyMessage="No batches expiring within 30 days." />
        </TabsContent>
      </Tabs>

      {adjust && <AdjustDialog row={adjust} onClose={() => setAdjust(null)} />}
      {stocking && <StockFromCatalogDialog onClose={() => setStocking(false)} />}
      {editId && <ProductEditDialog productId={editId} onClose={() => setEditId(null)} />}
    </div>
  );
}

interface ProductVariantDetail { id: string; label: string; onHand: number }

function AdjustDialog({ row, onClose }: { row: StockRow; onClose: () => void }) {
  // The unallocated pool can only be ALLOCATED into a pack; a real bucket is
  // counted / written off. Default each row to the action that fits it.
  const [mode, setMode] = React.useState<"adjust" | "waste" | "expiry" | "allocate">(
    row.unallocated ? "allocate" : "adjust",
  );
  const [value, setValue] = React.useState("");
  const [reason, setReason] = React.useState("");
  const [target, setTarget] = React.useState("");

  // For allocation we need the product's packs to choose a destination.
  const detailQ = useQuery({
    queryKey: ["store", "product", row.productId],
    queryFn: () => api.get<{ variants: ProductVariantDetail[] }>(`/store/inventory/products/${row.productId}`),
    enabled: mode === "allocate",
  });
  const packs = detailQ.data?.variants ?? [];

  const m = useApiMutation(
    (body: unknown) => api.post(`/store/inventory/${row.productId}/adjust`, body),
    { invalidate: [["store", "inventory"]], successMessage: "Stock updated", onDone: onClose }
  );

  function submit() {
    const n = parseInt(value, 10);
    // A real bucket carries its own variantId; the pool has none (variantId=null).
    const variantId = mode === "allocate" ? target : row.variantId;
    if (mode === "adjust") m.mutate({ mode, variantId, set: Number.isNaN(n) ? undefined : n, reason });
    else m.mutate({ mode, variantId, quantity: Number.isNaN(n) ? 0 : n, reason });
  }

  const canSubmit = !!value && (mode !== "allocate" || !!target);

  return (
    <Dialog open onOpenChange={(o) => !o && onClose()}>
      <DialogContent className="max-w-md">
        <DialogHeader>
          <DialogTitle>Adjust — {row.name}</DialogTitle>
          <DialogDescription>
            {row.unallocated
              ? `${row.current} unallocated — assign to a pack to make it sellable.`
              : `On hand ${row.current} · available ${row.available} · damaged ${row.damaged}`}
          </DialogDescription>
        </DialogHeader>
        <div className="space-y-3">
          <div className="space-y-1.5">
            <Label>Action</Label>
            <Select value={mode} onValueChange={(v) => setMode(v as typeof mode)}>
              <SelectTrigger><SelectValue /></SelectTrigger>
              <SelectContent>
                {row.unallocated ? (
                  <SelectItem value="allocate">Allocate to a pack</SelectItem>
                ) : (
                  <>
                    <SelectItem value="adjust">Set on-hand count</SelectItem>
                    <SelectItem value="waste">Mark damaged / waste</SelectItem>
                    <SelectItem value="expiry">Mark expired</SelectItem>
                  </>
                )}
              </SelectContent>
            </Select>
          </div>
          {mode === "allocate" && (
            <div className="space-y-1.5">
              <Label>To pack</Label>
              <Select value={target} onValueChange={setTarget}>
                <SelectTrigger><SelectValue placeholder={detailQ.isLoading ? "Loading…" : "Choose a pack"} /></SelectTrigger>
                <SelectContent>
                  {packs.map((v) => (
                    <SelectItem key={v.id} value={v.id}>{v.label} (now {v.onHand})</SelectItem>
                  ))}
                </SelectContent>
              </Select>
            </div>
          )}
          <div className="space-y-1.5">
            <Label>
              {mode === "adjust" ? "New on-hand quantity"
                : mode === "allocate" ? "Quantity to allocate"
                : "Quantity to write off"}
            </Label>
            <Input inputMode="numeric" value={value} onChange={(e) => setValue(e.target.value)} placeholder="0" />
          </div>
          {mode !== "allocate" && (
            <div className="space-y-1.5">
              <Label>Reason</Label>
              <Input value={reason} onChange={(e) => setReason(e.target.value)} placeholder="e.g. physical count / breakage" />
            </div>
          )}
        </div>
        <DialogFooter>
          <Button variant="outline" onClick={onClose} disabled={m.isPending}>Cancel</Button>
          <Button onClick={submit} disabled={m.isPending || !canSubmit}>
            {m.isPending && <Loader2 className="size-4 animate-spin" />} Apply
          </Button>
        </DialogFooter>
      </DialogContent>
    </Dialog>
  );
}

// ── Stock an existing catalog product for this store ──────────────────────────────
interface CatalogResult { productId: string; name: string; sku: string; brand: string; price: number; onHand: number }

function StockFromCatalogDialog({ onClose }: { onClose: () => void }) {
  return (
    <Dialog open onOpenChange={(o) => !o && onClose()}>
      <DialogContent className="max-w-lg">
        <DialogHeader>
          <DialogTitle>Stock an item</DialogTitle>
          <DialogDescription>Start stocking a product from the company catalog for your store — set your price and opening stock.</DialogDescription>
        </DialogHeader>
        <CatalogAddForm onDone={onClose} />
      </DialogContent>
    </Dialog>
  );
}

function CatalogAddForm({ onDone }: { onDone: () => void }) {
  const [q, setQ] = React.useState("");
  const [dq, setDq] = React.useState("");
  const [picked, setPicked] = React.useState<CatalogResult | null>(null);
  const [price, setPrice] = React.useState("");
  const [opening, setOpening] = React.useState("");
  const [reorder, setReorder] = React.useState("");

  React.useEffect(() => {
    const t = setTimeout(() => setDq(q.trim()), 300);
    return () => clearTimeout(t);
  }, [q]);

  const results = useQuery({
    queryKey: ["store", "catalog-search", dq],
    queryFn: () => api.get<CatalogResult[]>("/store/products", { q: dq }),
    enabled: dq.length > 0 && !picked,
  });

  const m = useApiMutation(
    (body: unknown) => api.patch(`/store/inventory/products/${picked!.productId}`, body),
    { invalidate: [["store", "inventory"]], successMessage: "Item added to your store", onDone },
  );

  function pick(r: CatalogResult) {
    setPicked(r);
    // Deliberately NOT prefilled with the company price: echoing it back on save
    // pinned a permanent per-store override, so later company price changes never
    // reached this store. Blank = follow the company price.
    setPrice("");
  }
  function submit() {
    const body: Record<string, unknown> = {
      isAvailable: true, openingStock: opening, reorderLevel: reorder,
    };
    // Only send a price when the operator actually typed one (= wants an override).
    if (price.trim() !== "") body.price = price.trim();
    m.mutate(body);
  }

  if (!picked) {
    return (
      <div className="space-y-3 pt-1">
        <Input autoFocus placeholder="Search company catalog…" value={q} onChange={(e) => setQ(e.target.value)} />
        <div className="max-h-64 space-y-1 overflow-y-auto">
          {results.isLoading && <div className="py-6 text-center text-sm text-muted-foreground"><Loader2 className="mx-auto size-4 animate-spin" /></div>}
          {!results.isLoading && dq && (results.data?.length ?? 0) === 0 && (
            <div className="py-6 text-center text-sm text-muted-foreground">No matching products.</div>
          )}
          {(results.data ?? []).map((r) => (
            <button key={r.productId} onClick={() => pick(r)}
              className="flex w-full items-center justify-between rounded-md border px-3 py-2 text-left text-sm hover:bg-accent">
              <span><span className="font-medium">{r.name}</span>
                <span className="ml-2 text-xs text-muted-foreground">{r.sku || r.brand}</span></span>
              <span className="text-xs text-muted-foreground">on hand {r.onHand}</span>
            </button>
          ))}
        </div>
      </div>
    );
  }

  return (
    <div className="space-y-3 pt-1">
      <div className="rounded-md border px-3 py-2 text-sm">
        <div className="font-medium">{picked.name}</div>
        <button className="text-xs text-primary hover:underline" onClick={() => setPicked(null)}>Choose a different product</button>
      </div>
      <div className="grid grid-cols-2 gap-3">
        <div className="space-y-1.5">
          <Label>Your price override (₹) <span className="text-xs font-normal text-muted-foreground">optional</span></Label>
          <Input inputMode="decimal" value={price} onChange={(e) => setPrice(e.target.value)}
                 placeholder={String(picked.price ?? "")} />
          <p className="text-xs text-muted-foreground">
            Leave blank to follow the company price {inr(picked.price ?? 0)}.
          </p>
        </div>
        <div className="space-y-1.5"><Label>Opening stock</Label>
          <Input inputMode="numeric" value={opening} onChange={(e) => setOpening(e.target.value)} placeholder="0" /></div>
        <div className="space-y-1.5"><Label>Reorder level</Label>
          <Input inputMode="numeric" value={reorder} onChange={(e) => setReorder(e.target.value)} placeholder="0" /></div>
      </div>
      <p className="text-xs text-muted-foreground">Your price overrides the company price for your store only.</p>
      <DialogFooter>
        <Button onClick={submit} disabled={m.isPending}>
          {m.isPending && <Loader2 className="size-4 animate-spin" />} Add to my inventory
        </Button>
      </DialogFooter>
    </div>
  );
}

// ── Edit an item's per-store details (override for shared, direct for private) ─────
interface ProductPayload {
  productId: string; private: boolean; name: string; brand: string; description: string;
  imageUrl: string; price: number; mrp: number; isAvailable: boolean; hasOverride: boolean;
  globalName: string; globalPrice: number;
  /** RAW per-store override — null means "follow the company product". */
  overridePrice: number | null; overrideMrp: number | null;
  variants: { id: string; label: string; priceDelta: number }[];
}

function ProductEditDialog({ productId, onClose }: { productId: string; onClose: () => void }) {
  const q = useQuery({
    queryKey: ["store", "product", productId],
    queryFn: () => api.get<ProductPayload>(`/store/inventory/products/${productId}`),
  });
  return (
    <Dialog open onOpenChange={(o) => !o && onClose()}>
      <DialogContent className="max-w-lg">
        <DialogHeader>
          <DialogTitle>Edit item</DialogTitle>
          <DialogDescription>
            {q.data?.private
              ? "This product belongs to your store — edits apply here only."
              : "Company product — your changes override it for your store only."}
          </DialogDescription>
        </DialogHeader>
        {q.isLoading && <div className="py-10 text-center"><Loader2 className="mx-auto size-5 animate-spin" /></div>}
        {q.data && <ProductEditForm data={q.data} onDone={onClose} />}
      </DialogContent>
    </Dialog>
  );
}

function ProductEditForm({ data, onDone }: { data: ProductPayload; onDone: () => void }) {
  const [name, setName] = React.useState(data.name ?? "");
  // For a SHARED (company) product this field is the store's OVERRIDE, so it starts
  // blank when there is none — binding it to the resolved price meant every save
  // (even just toggling availability) echoed that price back and silently pinned a
  // permanent override. For the store's OWN product it's the real price.
  const [price, setPrice] = React.useState(
    data.private ? String(data.price ?? "") : (data.overridePrice != null ? String(data.overridePrice) : ""),
  );
  const [description, setDescription] = React.useState(data.description ?? "");
  const [image, setImage] = React.useState<string | null>(data.imageUrl || null);
  const [available, setAvailable] = React.useState(data.isAvailable);
  const [variants, setVariants] = React.useState<VariantRow[]>(
    () => (data.variants ?? []).map((v) => ({ id: v.id, label: v.label, priceDelta: String(v.priceDelta) })),
  );

  const m = useApiMutation(
    (body: unknown) => api.patch(`/store/inventory/products/${data.productId}`, body),
    { invalidate: [["store", "inventory"], ["store", "product", data.productId]], successMessage: "Item updated", onDone },
  );

  function submit() {
    const body: Record<string, unknown> = { isAvailable: available };
    if (data.private) {
      // The store owns this product — these ARE its fields.
      body.name = name;
      body.price = price;
      body.description = description;
      body.imageUrl = image;
      // Variants are editable only on the store's own product (shared products carry
      // the company's global variants, which a store can't change).
      body.variants = variants.filter((v) => v.label.trim()).map((v) => ({ id: v.id, label: v.label, priceDelta: v.priceDelta }));
    } else {
      // Shared product → send OVERRIDES only, and only the ones that actually
      // differ from what we loaded. Blank price = clear the override (follow the
      // company price); the backend treats an omitted key as "leave untouched".
      const trimmed = price.trim();
      const loaded = data.overridePrice != null ? String(data.overridePrice) : "";
      if (trimmed !== loaded) body.price = trimmed === "" ? null : trimmed;
      if (name !== data.name) body.name = name;
      if (description !== data.description) body.description = description;
      if ((image || "") !== (data.imageUrl || "")) body.imageUrl = image;
    }
    m.mutate(body);
  }

  return (
    <div className="space-y-3">
      <div className="grid grid-cols-2 gap-3">
        <div className="col-span-2 space-y-1.5"><Label>Name {!data.private && <span className="text-xs text-muted-foreground">(overrides “{data.globalName}”)</span>}</Label>
          <Input value={name} onChange={(e) => setName(e.target.value)} /></div>
        <div className="space-y-1.5">
          <Label>{data.private ? "Selling price (₹)" : "Your price override (₹)"}</Label>
          <Input
            inputMode="decimal"
            value={price}
            onChange={(e) => setPrice(e.target.value)}
            placeholder={data.private ? undefined : String(data.globalPrice)}
          />
          {!data.private && (
            <p className="text-xs text-muted-foreground">
              {price.trim() === ""
                ? `Following the company price ${inr(data.globalPrice)} — it updates automatically.`
                : `Overrides the company price ${inr(data.globalPrice)}. Clear this box to follow it again.`}
            </p>
          )}
        </div>
        <div className="flex items-end pb-1">
          <label className="flex items-center gap-2 text-sm">
            <input type="checkbox" checked={available} onChange={(e) => setAvailable(e.target.checked)} />
            Available for sale
          </label>
        </div>
        <div className="col-span-2 space-y-1.5"><Label>Description</Label>
          <Textarea rows={2} value={description} onChange={(e) => setDescription(e.target.value)} /></div>
        <div className="col-span-2 space-y-1.5"><Label>Photo</Label>
          <ImageUpload value={image} onChange={setImage} /></div>
        {data.private && (
          <div className="col-span-2"><VariantsEditor rows={variants} onChange={setVariants} /></div>
        )}
      </div>
      <DialogFooter>
        <Button onClick={submit} disabled={m.isPending}>
          {m.isPending && <Loader2 className="size-4 animate-spin" />} Save
        </Button>
      </DialogFooter>
    </div>
  );
}
