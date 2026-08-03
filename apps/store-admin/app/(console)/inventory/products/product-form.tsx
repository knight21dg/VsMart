"use client";

import * as React from "react";
import { useRouter } from "next/navigation";
import { useQuery } from "@tanstack/react-query";
import { ArrowLeft, Loader2 } from "lucide-react";
import { api, useApiMutation } from "@/lib/api/hooks";
import { PageHeader } from "@/components/page-header";
import { RequirePerm } from "@/components/permission-gate";
import { Card, CardContent } from "@/components/ui/card";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import { Textarea } from "@/components/ui/textarea";
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from "@/components/ui/select";
import { MultiImageUpload } from "@/components/multi-image-upload";
import { BarcodeField, type BarcodeOwner } from "@/components/barcode-field";
import { VariantsEditor, type VariantRow } from "@/components/variants-editor";

interface Category { id: string; name: string; parentId: string | null }
interface ProductPayload {
  productId: string; private: boolean; categoryId: string | null; name: string;
  brand: string; unit: string; sku: string; hsn: string; description: string;
  imageUrl: string; images: string[]; price: number; mrp: number; barcode: string;
  variants: {
    id: string; label: string; priceDelta: number; mrp: number | null;
    imageUrl: string; hasOwnImage: boolean; barcode: string;
    onHand: number; available: number; reorderLevel: number; inStock: boolean;
  }[];
  unallocated?: number;
}
interface Initial {
  dept: string; sub: string; fields: Record<string, string>;
  images: string[]; variants: VariantRow[]; barcode: string;
}

const NONE = "__none__";

export function StoreProductForm({ productId }: { productId?: string }) {
  return (
    <RequirePerm perm="inventory.manage">
      <FormLoader productId={productId} />
    </RequirePerm>
  );
}

/** Loads the category list (+ the product on edit), then renders the stateful body
 * with its initial values — keeping all setState out of effects (strict R19 lint). */
function FormLoader({ productId }: { productId?: string }) {
  const editing = !!productId;
  const catsQ = useQuery({ queryKey: ["store", "categories"], queryFn: () => api.get<Category[]>("/store/categories") });
  const existingQ = useQuery({
    queryKey: ["store", "product", productId],
    queryFn: () => api.get<ProductPayload>(`/store/inventory/products/${productId}`),
    enabled: editing,
  });

  if (catsQ.isLoading || (editing && existingQ.isLoading)) {
    return <div className="grid place-items-center py-20"><Loader2 className="size-6 animate-spin text-muted-foreground" /></div>;
  }

  const cats = catsQ.data ?? [];
  let initial: Initial;
  if (editing && existingQ.data) {
    const d = existingQ.data;
    const cat = cats.find((c) => c.id === d.categoryId);
    initial = {
      dept: cat?.parentId ?? cat?.id ?? "",
      sub: cat?.parentId ? cat.id : "",
      fields: {
        name: d.name, brand: d.brand, unit: d.unit || "Each", sku: d.sku, hsn: d.hsn,
        description: d.description, price: String(d.price ?? ""), mrp: String(d.mrp ?? ""),
      },
      images: d.images && d.images.length ? d.images : (d.imageUrl ? [d.imageUrl] : []),
      barcode: d.barcode ?? "",
      variants: (d.variants ?? []).map((v) => ({
        id: v.id, label: v.label, priceDelta: String(v.priceDelta),
        mrp: v.mrp != null ? String(v.mrp) : "",
        imageUrl: v.hasOwnImage ? v.imageUrl : "",
        barcode: v.barcode ?? "",
        // Prefill the "set stock" field with what's on the shelf, and show it live.
        openingStock: String(v.onHand ?? ""),
        reorderLevel: v.reorderLevel ? String(v.reorderLevel) : "",
        onHand: v.onHand ?? 0,
      })),
    };
  } else {
    initial = { dept: "", sub: "", fields: { unit: "Each" }, images: [], variants: [], barcode: "" };
  }

  return (
    <FormBody
      key={editing ? productId : "new"}
      categories={cats}
      initial={initial}
      editing={editing}
      productId={productId}
    />
  );
}

function FormBody({ categories, initial, editing, productId }: {
  categories: Category[]; initial: Initial; editing: boolean; productId?: string;
}) {
  const router = useRouter();
  const [dept, setDept] = React.useState(initial.dept);
  const [sub, setSub] = React.useState(initial.sub);
  const [f, setF] = React.useState<Record<string, string>>(initial.fields);
  const [images, setImages] = React.useState<string[]>(initial.images);
  const [variants, setVariants] = React.useState<VariantRow[]>(initial.variants);
  const [barcode, setBarcode] = React.useState(initial.barcode);
  // Set when the scanned code already belongs to something else — blocks save so a
  // duplicate can never be created in the first place.
  const [barcodeClash, setBarcodeClash] = React.useState<BarcodeOwner | null>(null);
  const set = (k: string, v: string) => setF((p) => ({ ...p, [k]: v }));

  const departments = categories.filter((c) => !c.parentId);
  const subcategories = categories.filter((c) => c.parentId === dept);
  const categoryId = sub || dept;
  const hasVariants = variants.some((v) => v.label.trim());

  const save = useApiMutation(
    (body: unknown) => editing
      ? api.patch(`/store/inventory/products/${productId}`, body)
      : api.post("/store/inventory/products", body),
    {
      invalidate: [["store", "inventory"], ["store", "product", productId]],
      successMessage: editing ? "Product updated" : "Product added to your store",
      onDone: () => router.push("/inventory"),
    },
  );

  function submit() {
    const body: Record<string, unknown> = {
      categoryId, name: f.name, brand: f.brand, unit: f.unit || "Each",
      sku: f.sku, hsn: f.hsn, description: f.description,
      price: f.price, mrp: f.mrp, images,
      // Blank barcode → the backend generates a scannable in-store code.
      barcode: barcode.trim(),
      variants: variants.filter((v) => v.label.trim()).map((v) => ({
        id: v.id, label: v.label, priceDelta: v.priceDelta,
        mrp: (v.mrp ?? "").trim() || null,
        imageUrl: (v.imageUrl ?? "").trim(),
        barcode: (v.barcode ?? "").trim(),
        // Stock rides with each pack — on add AND on edit (a "set to" count).
        openingStock: (v.openingStock ?? "").trim(),
        reorderLevel: (v.reorderLevel ?? "").trim(),
      })),
    };
    // Product-level stock only for a product with no packs; a variant product
    // carries its stock on each row instead.
    if (!editing && !hasVariants) {
      body.openingStock = f.openingStock;
      body.reorderLevel = f.reorderLevel;
    }
    save.mutate(body);
  }

  return (
    <div className="space-y-5">
      <PageHeader
        title={editing ? "Edit product" : "New product"}
        description="A product for your store only — set its category, photos and variants."
        actions={<Button variant="outline" onClick={() => router.push("/inventory")}><ArrowLeft className="size-4" /> Back</Button>}
      />

      <div className="grid gap-4 lg:grid-cols-3">
        <Card className="lg:col-span-2">
          <CardContent className="space-y-4 p-5">
            <SectionTitle>Category</SectionTitle>
            <div className="grid gap-3 sm:grid-cols-2">
              <div className="space-y-1.5">
                <Label>Department</Label>
                <Select value={dept} onValueChange={(v) => { setDept(v); setSub(""); }}>
                  <SelectTrigger><SelectValue placeholder="Select department" /></SelectTrigger>
                  <SelectContent>
                    {departments.map((c) => <SelectItem key={c.id} value={c.id}>{c.name}</SelectItem>)}
                  </SelectContent>
                </Select>
              </div>
              <div className="space-y-1.5">
                <Label>Sub-category {subcategories.length === 0 && <span className="text-xs text-muted-foreground">(none)</span>}</Label>
                <Select value={sub || NONE} onValueChange={(v) => setSub(v === NONE ? "" : v)} disabled={subcategories.length === 0}>
                  <SelectTrigger><SelectValue placeholder="Optional" /></SelectTrigger>
                  <SelectContent>
                    <SelectItem value={NONE}>— None —</SelectItem>
                    {subcategories.map((c) => <SelectItem key={c.id} value={c.id}>{c.name}</SelectItem>)}
                  </SelectContent>
                </Select>
              </div>
            </div>

            <SectionTitle>Details</SectionTitle>
            <div className="grid gap-3 sm:grid-cols-2">
              <div className="space-y-1.5 sm:col-span-2"><Label>Name</Label>
                <Input value={f.name ?? ""} onChange={(e) => set("name", e.target.value)} /></div>
              <div className="space-y-1.5"><Label>Brand</Label>
                <Input value={f.brand ?? ""} onChange={(e) => set("brand", e.target.value)} /></div>
              <div className="space-y-1.5"><Label>Unit</Label>
                <Input value={f.unit ?? ""} onChange={(e) => set("unit", e.target.value)} placeholder="Each / 1 kg" /></div>
              <div className="space-y-1.5"><Label>SKU (optional)</Label>
                <Input value={f.sku ?? ""} onChange={(e) => set("sku", e.target.value)} /></div>
              <div className="space-y-1.5"><Label>HSN (optional)</Label>
                <Input value={f.hsn ?? ""} onChange={(e) => set("hsn", e.target.value)} /></div>
              <div className="space-y-1.5"><Label>Selling price (₹)</Label>
                <Input inputMode="decimal" value={f.price ?? ""} onChange={(e) => set("price", e.target.value)} /></div>
              <div className="space-y-1.5"><Label>MRP (₹)</Label>
                <Input inputMode="decimal" value={f.mrp ?? ""} onChange={(e) => set("mrp", e.target.value)} /></div>
              {/* Product-level stock only when there are NO packs. A variant product
                  is stocked per pack, in the Variants editor below — a single number
                  here would be meaningless (which pack?) and the backend rejects it. */}
              {!editing && !hasVariants && (
                <>
                  <div className="space-y-1.5"><Label>Opening stock</Label>
                    <Input inputMode="numeric" value={f.openingStock ?? ""} onChange={(e) => set("openingStock", e.target.value)} placeholder="0" /></div>
                  <div className="space-y-1.5"><Label>Reorder level</Label>
                    <Input inputMode="numeric" value={f.reorderLevel ?? ""} onChange={(e) => set("reorderLevel", e.target.value)} placeholder="0" /></div>
                </>
              )}
              <div className="space-y-1.5 sm:col-span-2"><Label>Barcode</Label>
                <BarcodeField
                  value={barcode}
                  onChange={setBarcode}
                  selfProductId={productId}
                  onOwnerChange={setBarcodeClash}
                  autoFocus={!editing}
                /></div>
              <div className="space-y-1.5 sm:col-span-2"><Label>Description</Label>
                <Textarea rows={3} value={f.description ?? ""} onChange={(e) => set("description", e.target.value)} /></div>
            </div>

            <SectionTitle>Variants</SectionTitle>
            <VariantsEditor rows={variants} onChange={setVariants} selfProductId={productId} editing={editing} />
          </CardContent>
        </Card>

        <Card>
          <CardContent className="space-y-3 p-5">
            <SectionTitle>Photos</SectionTitle>
            <MultiImageUpload value={images} onChange={setImages} />
          </CardContent>
        </Card>
      </div>

      <div className="flex justify-end gap-2">
        <Button variant="outline" onClick={() => router.push("/inventory")} disabled={save.isPending}>Cancel</Button>
        <Button onClick={submit} disabled={save.isPending || !f.name || !categoryId || !f.price || !!barcodeClash}>
          {save.isPending && <Loader2 className="size-4 animate-spin" />} {editing ? "Save changes" : "Add product"}
        </Button>
      </div>
    </div>
  );
}

function SectionTitle({ children }: { children: React.ReactNode }) {
  return <h3 className="text-sm font-semibold text-muted-foreground">{children}</h3>;
}
