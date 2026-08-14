"use client";

import * as React from "react";
import { keepPreviousData, useQuery } from "@tanstack/react-query";
import { type ColumnDef } from "@tanstack/react-table";
import { Archive, Loader2, Package, Pencil, Search } from "lucide-react";
import { api } from "@/lib/api/client";
import { useApiMutation } from "@/lib/api/hooks";
import { PageHeader } from "@/components/page-header";
import { DataTable } from "@/components/data-table";
import { ImageUpload } from "@/components/image-upload";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import { Badge } from "@/components/ui/badge";
import { BoolBadge } from "@/components/status-badge";
import { ProductLink } from "@/components/product-link";
import { ConfirmDialog } from "@/components/confirm-dialog";
import { Dialog, DialogContent, DialogFooter, DialogHeader, DialogTitle } from "@/components/ui/dialog";
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from "@/components/ui/select";
import type { PageMeta } from "@/lib/types";
import { inr } from "@/lib/utils";

interface MasterProduct {
  id: string;
  name: string;
  brand: string;
  unit: string;
  sku: string;
  hsn: string;
  gstRate: number | null;
  price: number;
  mrp: number;
  creditPrice: number | null;
  categoryId: number | string;
  categoryName?: string;
  imageUrl?: string | null;
  description?: string;
  storeCount?: number;
  isActive: boolean;
  // Content translations — resolved per request language on the customer API.
  nameTe?: string;
  nameHi?: string;
  descriptionTe?: string;
  descriptionHi?: string;
}
interface Category { id: string; name: string }
type Form = Partial<MasterProduct>;

export default function ProductMasterPage() {
  const [search, setSearch] = React.useState("");
  const [q, setQ] = React.useState("");
  const [page, setPage] = React.useState(1);
  const [open, setOpen] = React.useState(false);
  const [editing, setEditing] = React.useState<MasterProduct | null>(null);
  const [form, setForm] = React.useState<Form>({});
  const [toArchive, setToArchive] = React.useState<MasterProduct | null>(null);

  React.useEffect(() => {
    const t = setTimeout(() => { setQ(search.trim()); setPage(1); }, 300);
    return () => clearTimeout(t);
  }, [search]);

  const query = useQuery({
    queryKey: ["catalog", "products", { q, page }],
    queryFn: () => api.getPaged<MasterProduct>("/admin/catalog/products", { q: q || undefined, page }),
    placeholderData: keepPreviousData,
  });
  const cats = useQuery({ queryKey: ["catalog", "categories"], queryFn: () => api.getPaged<Category>("/admin/catalog/categories"), enabled: open });

  // Admin can EDIT the company catalog but not create products — new products are
  // added per-store from the store panel (they belong to that store).
  const save = useApiMutation(
    (body: Form) => api.patch(`/admin/catalog/products/${editing!.id}`, body),
    { invalidate: [["catalog", "products"]], successMessage: "Product saved.", onDone: () => setOpen(false) }
  );
  const archive = useApiMutation((id: string) => api.del(`/admin/catalog/products/${id}`), {
    invalidate: [["catalog", "products"]],
    successMessage: "Product archived.",
    onDone: () => setToArchive(null),
  });

  function openEdit(p: MasterProduct) { setEditing(p); setForm(p); setOpen(true); }
  function submit() {
    if (!editing) return;
    const body: Form = {
      name: form.name, brand: form.brand, unit: form.unit, sku: form.sku, hsn: form.hsn,
      gstRate: numOrNull(form.gstRate), price: Number(form.price ?? 0), mrp: Number(form.mrp ?? 0),
      creditPrice: numOrNull(form.creditPrice), categoryId: form.categoryId, imageUrl: form.imageUrl,
      description: form.description,
      nameTe: form.nameTe ?? "", nameHi: form.nameHi ?? "",
      descriptionTe: form.descriptionTe ?? "", descriptionHi: form.descriptionHi ?? "",
    };
    save.mutate(body);
  }

  const columns: ColumnDef<MasterProduct, unknown>[] = [
    {
      accessorKey: "name", header: "Product",
      // No `archived` badge here — this table already carries an explicit
      // Status column (Active / Archived), so it would just be duplicated.
      cell: ({ row }) => <ProductLink id={row.original.id} name={row.original.name} className="font-medium" />,
    },
    { accessorKey: "sku", header: "SKU", cell: ({ row }) => <span className="font-mono text-xs">{row.original.sku || "—"}</span> },
    { accessorKey: "categoryName", header: "Category", cell: ({ row }) => <span className="text-muted-foreground">{row.original.categoryName}</span> },
    { accessorKey: "hsn", header: "HSN", cell: ({ row }) => <span className="font-mono text-xs">{row.original.hsn || "—"}</span> },
    // gstRate is a percentage (18 = 18%). It used to be a fraction here and was
    // rendered as `gstRate * 100`, which is why the form asked for "0–1".
    { id: "gst", header: "GST", cell: ({ row }) => (row.original.gstRate != null ? `${row.original.gstRate}%` : "Default") },
    {
      id: "stores",
      header: "Stores",
      cell: ({ row }) => {
        const n = row.original.storeCount ?? 0;
        return n > 0 ? <Badge variant="secondary">{n} store{n === 1 ? "" : "s"}</Badge> : <span className="text-xs text-muted-foreground">None</span>;
      },
    },
    { accessorKey: "mrp", header: "MRP", cell: ({ row }) => inr(row.original.mrp) },
    { accessorKey: "price", header: "Price", cell: ({ row }) => inr(row.original.price) },
    { accessorKey: "isActive", header: "Status", cell: ({ row }) => <BoolBadge value={row.original.isActive} trueLabel="Active" falseLabel="Archived" /> },
    {
      id: "actions",
      header: "",
      cell: ({ row }) => (
        <div className="flex justify-end gap-1">
          <Button variant="ghost" size="icon" onClick={() => openEdit(row.original)}><Pencil className="size-4" /></Button>
          {row.original.isActive && <Button variant="ghost" size="icon" onClick={() => setToArchive(row.original)}><Archive className="size-4 text-destructive" /></Button>}
        </div>
      ),
    },
  ];

  return (
    <>
      <PageHeader
        title="Product Master"
        description="The company catalog — edit products, SKU, HSN, GST, MRP. Stock is held per store; new items are added from each store's panel."
      />
      <DataTable
        columns={columns}
        data={query.data?.rows ?? []}
        loading={query.isLoading}
        error={query.isError ? "Failed to load products." : null}
        onRetry={() => query.refetch()}
        pageMeta={query.data?.meta as PageMeta | undefined}
        page={page}
        onPageChange={setPage}
        toolbar={
          <div className="relative max-w-xs">
            <Search className="pointer-events-none absolute left-3 top-1/2 size-4 -translate-y-1/2 text-muted-foreground" />
            <Input value={search} onChange={(e) => setSearch(e.target.value)} placeholder="Search products…" className="pl-9" />
          </div>
        }
      />

      <Dialog open={open} onOpenChange={setOpen}>
        <DialogContent className="max-w-2xl">
          <DialogHeader><DialogTitle className="flex items-center gap-2"><Package className="size-4" /> Edit Product</DialogTitle></DialogHeader>
          <div className="grid grid-cols-2 gap-3">
            <div className="col-span-2 space-y-1.5"><Label>Name</Label><Input value={form.name ?? ""} onChange={(e) => setForm({ ...form, name: e.target.value })} /></div>
            <F label="Brand"><Input value={form.brand ?? ""} onChange={(e) => setForm({ ...form, brand: e.target.value })} /></F>
            <F label="Unit"><Input value={form.unit ?? ""} onChange={(e) => setForm({ ...form, unit: e.target.value })} /></F>
            <F label="SKU"><Input value={form.sku ?? ""} onChange={(e) => setForm({ ...form, sku: e.target.value })} /></F>
            <F label="HSN"><Input value={form.hsn ?? ""} onChange={(e) => setForm({ ...form, hsn: e.target.value })} /></F>
            {/* A free-text decimal let operators type 0.18 for 18% (the old
                label literally asked for 0–1), and accepted typos like 1.8 or
                180 just as happily — a silent tax error on every invoice. The
                slabs are the only legal values, so offer exactly those. */}
            <F label="GST rate">
              <Select
                value={form.gstRate != null ? String(form.gstRate) : "default"}
                onValueChange={(v) => setForm({ ...form, gstRate: v === "default" ? null : (Number(v) as number) })}
              >
                <SelectTrigger><SelectValue /></SelectTrigger>
                <SelectContent>
                  <SelectItem value="default">Platform default</SelectItem>
                  {GST_SLABS.map((s) => <SelectItem key={s} value={String(s)}>{s}%</SelectItem>)}
                </SelectContent>
              </Select>
            </F>
            <F label="Category">
              <Select value={form.categoryId != null ? String(form.categoryId) : ""} onValueChange={(v) => setForm({ ...form, categoryId: v })}>
                <SelectTrigger><SelectValue placeholder="Select" /></SelectTrigger>
                <SelectContent>
                  {(cats.data?.rows ?? []).map((c) => <SelectItem key={c.id} value={c.id}>{c.name}</SelectItem>)}
                </SelectContent>
              </Select>
            </F>
            <F label="MRP (₹)"><Input type="number" value={form.mrp ?? ""} onChange={(e) => setForm({ ...form, mrp: e.target.value as unknown as number })} /></F>
            <F label="Selling price (₹)"><Input type="number" value={form.price ?? ""} onChange={(e) => setForm({ ...form, price: e.target.value as unknown as number })} /></F>
            <F label="Credit price (₹)"><Input type="number" value={form.creditPrice ?? ""} onChange={(e) => setForm({ ...form, creditPrice: e.target.value as unknown as number })} /></F>
            <div className="col-span-2 space-y-1.5"><Label>Product image</Label><ImageUpload value={form.imageUrl ?? null} onChange={(url) => setForm({ ...form, imageUrl: url })} category="catalog" /></div>
            <div className="col-span-2 space-y-1.5"><Label>Description</Label><Input value={form.description ?? ""} onChange={(e) => setForm({ ...form, description: e.target.value })} /></div>

            {/* Content translations. Product names/descriptions are data, not UI
                strings — the app's language files can't translate them, so they
                have to be entered here. Blank falls back to English. */}
            <div className="col-span-2 rounded-md border p-3">
              <p className="mb-2 text-xs text-muted-foreground">
                Translations — shown to customers using that language. Leave blank to fall back to English.
              </p>
              <div className="grid grid-cols-2 gap-3">
                <F label="Name (తెలుగు)"><Input value={form.nameTe ?? ""} onChange={(e) => setForm({ ...form, nameTe: e.target.value })} /></F>
                <F label="Name (हिन्दी)"><Input value={form.nameHi ?? ""} onChange={(e) => setForm({ ...form, nameHi: e.target.value })} /></F>
                <F label="Description (తెలుగు)"><Input value={form.descriptionTe ?? ""} onChange={(e) => setForm({ ...form, descriptionTe: e.target.value })} /></F>
                <F label="Description (हिन्दी)"><Input value={form.descriptionHi ?? ""} onChange={(e) => setForm({ ...form, descriptionHi: e.target.value })} /></F>
              </div>
            </div>
          </div>
          <DialogFooter className="gap-2">
            <Button variant="outline" onClick={() => setOpen(false)} disabled={save.isPending}>Cancel</Button>
            <Button onClick={submit} disabled={save.isPending || !form.name || !form.categoryId}>
              {save.isPending && <Loader2 className="size-4 animate-spin" />} Save
            </Button>
          </DialogFooter>
        </DialogContent>
      </Dialog>

      <ConfirmDialog
        open={!!toArchive}
        onOpenChange={(o) => !o && setToArchive(null)}
        title={`Archive ${toArchive?.name}?`}
        description="The product is hidden from catalogs but its history is preserved."
        confirmLabel="Archive"
        destructive
        loading={archive.isPending}
        onConfirm={() => toArchive && archive.mutate(toArchive.id)}
      />
    </>
  );
}

/** The statutory Indian GST slabs, as percentages. Mirrors `core.pricing.GST_SLABS`
 *  on the backend, which rejects anything else. */
const GST_SLABS = [0, 0.25, 3, 5, 12, 18, 28] as const;

function numOrNull(v: unknown): number | null {
  if (v === "" || v == null) return null;
  const n = Number(v);
  return Number.isNaN(n) ? null : n;
}

function F({ label, children }: { label: string; children: React.ReactNode }) {
  return <div className="space-y-1.5"><Label>{label}</Label>{children}</div>;
}
