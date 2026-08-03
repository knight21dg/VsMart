"use client";

import * as React from "react";
import { useQuery, useQueryClient } from "@tanstack/react-query";
import { type ColumnDef } from "@tanstack/react-table";
import { Crop, ImageIcon, Loader2, Megaphone, Pencil, Plus, Send, Ticket, Trash2, Upload } from "lucide-react";
import { toast } from "sonner";
import { api } from "@/lib/api/client";
import { ApiError } from "@/lib/types";
import { useApiMutation } from "@/lib/api/hooks";
import { PageHeader } from "@/components/page-header";
import { ImageUpload } from "@/components/image-upload";
import { BannerCropDialog, type CropRect } from "@/components/banner-cropper";
import { DataTable } from "@/components/data-table";
import { ConfirmDialog } from "@/components/confirm-dialog";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";
import { Tabs, TabsContent, TabsList, TabsTrigger } from "@/components/ui/tabs";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Textarea } from "@/components/ui/textarea";
import { Label } from "@/components/ui/label";
import { Badge } from "@/components/ui/badge";
import { Switch } from "@/components/ui/switch";
import { BoolBadge } from "@/components/status-badge";
import { Dialog, DialogContent, DialogFooter, DialogHeader, DialogTitle } from "@/components/ui/dialog";
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from "@/components/ui/select";
import { inr, titleize } from "@/lib/utils";

interface OfferImage { large?: string; medium?: string; small?: string; thumb?: string; focus?: { x: number; y: number } }
interface Offer {
  id: string; type: string; placement: string; title: string; subtitle: string; code: string;
  imageUrl: string | null; badge: string; discountPercent: number | null; dealPrice: number | null;
  categoryId: number | string | null; subcategoryId: number | string | null; isFallback: boolean;
  isActive: boolean; sortOrder: number;
  // v1.0
  state: string; isPinned: boolean; zoneId: number | string | null; storeId: number | string | null;
  titleTe: string; titleHi: string; subtitleTe: string; subtitleHi: string;
  action: string; payload: Record<string, unknown> | null;
  validFrom: string | null; validTo: string | null; timezone: string;
  focusX: number; focusY: number; image: OfferImage | null; imageVersion: number;
  impressions: number; clicks: number; ctr: number; rejectionReason: string;
  // v1.1 overlay
  ctaText: string; ctaTextTe: string; ctaTextHi: string;
  textTheme: string; textPosition: string; accentColor: string;
  cropRect: CropRect | Record<string, never> | null;
}

/** One row of GET /offers/specs — the placement geometry contract. */
interface BannerSpec {
  placement: string; label: string; note: string; ratio: number; aspect: string;
  master: { width: number; height: number };
  minUpload: { width: number; height: number };
  sizes: { name: string; width: number; height: number }[];
}

const TEXT_THEMES = [
  { value: "light", label: "Light text on dark scrim" },
  { value: "dark", label: "Dark text on light scrim" },
  { value: "none", label: "No overlay (artwork only)" },
];
const TEXT_POSITIONS = [
  { value: "bottom_left", label: "Bottom left" },
  { value: "bottom_center", label: "Bottom center" },
  { value: "center", label: "Center" },
  { value: "top_left", label: "Top left" },
];
interface CategoryRef { id: string; name: string; parentId: number | string | null }

const PLACEMENTS: { value: string; label: string }[] = [
  { value: "top", label: "Home — Top" },
  { value: "middle", label: "Home — Middle" },
  { value: "spotlight", label: "Home — Spotlight" },
  { value: "product_list", label: "Product List" },
  { value: "product_detail", label: "Product Detail" },
  { value: "cart", label: "Cart" },
];
// Deep-link actions (enum) — keep in sync with offers.Offer.Action on the backend.
// State → which workflow transitions are offered.
// Archive is reachable from every live state — previously it was only offered
// from paused/expired, so a draft or active banner could never be taken down.
const TRANSITIONS: Record<string, string[]> = {
  draft: ["submit", "archive"],
  pending: ["approve", "reject", "archive"],
  scheduled: ["pause", "archive"],
  active: ["pause", "archive"],
  paused: ["resume", "archive"],
  expired: ["approve", "archive"],
};
const STATE_VARIANT: Record<string, "success" | "warning" | "secondary" | "destructive"> = {
  active: "success", scheduled: "warning", pending: "warning",
  draft: "secondary", paused: "secondary", expired: "destructive", archived: "destructive",
};
const ANY = "__any__"; // Select can't use "" as an item value.
interface Coupon { id: string; code: string; discountType: string; value: number; minOrder: number | null; maxDiscount: number | null; usageLimit: number | null; perUserLimit: number | null; validTo: string | null; isActive: boolean; redemptions: number }
interface Zone { id: string; name: string }
interface StoreRef { id: string; name: string }

export default function MarketingPage() {
  const [tab, setTab] = React.useState("offers");
  return (
    <>
      <PageHeader title="Marketing" description="Banners, deals, coupons and customer campaigns." />
      <Tabs value={tab} onValueChange={setTab}>
        <TabsList>
          <TabsTrigger value="offers">Banners & Deals</TabsTrigger>
          <TabsTrigger value="coupons">Coupons</TabsTrigger>
          <TabsTrigger value="notify">Campaigns</TabsTrigger>
        </TabsList>
        <TabsContent value="offers"><OffersTab active={tab === "offers"} /></TabsContent>
        <TabsContent value="coupons"><CouponsTab active={tab === "coupons"} /></TabsContent>
        <TabsContent value="notify"><CampaignTab active={tab === "notify"} /></TabsContent>
      </Tabs>
    </>
  );
}

function OffersTab({ active }: { active: boolean }) {
  const qc = useQueryClient();
  const [open, setOpen] = React.useState(false);
  const [editing, setEditing] = React.useState<Offer | null>(null);
  const [form, setForm] = React.useState<Partial<Offer>>({});
  const [stagedFile, setStagedFile] = React.useState<File | null>(null);
  const [focus, setFocus] = React.useState<{ x: number; y: number }>({ x: 0.5, y: 0.5 });
  const [cropRect, setCropRect] = React.useState<CropRect | null>(null);
  const [confirmDelete, setConfirmDelete] = React.useState<Offer | null>(null);
  // Rejection reason is collected in a real dialog. It used to be a
  // window.prompt(), which Chrome lets the operator permanently suppress via
  // "prevent additional dialogs" — after that every reject silently aborted.
  const [rejectOpen, setRejectOpen] = React.useState(false);
  const [rejectReason, setRejectReason] = React.useState("");
  const [busy, setBusy] = React.useState(false);

  const query = useQuery({ queryKey: ["mkt", "offers"], queryFn: () => api.getPaged<Offer>("/admin/marketing/offers"), enabled: active });
  // Placement geometry comes from the server so the cropper, the size hints and
  // the backend's crop can never drift apart. Cached hard — it changes with a deploy.
  const specsQ = useQuery({
    queryKey: ["banner", "specs"],
    queryFn: () => api.get<{ placements: BannerSpec[] }>("/offers/specs"),
    staleTime: 60 * 60 * 1000,
    enabled: active,
  });
  const specs = specsQ.data?.placements ?? [];
  const spec = specs.find((s) => s.placement === (form.placement ?? "top")) ?? null;
  const cats = useQuery({ queryKey: ["admin", "categories"], queryFn: () => api.getPaged<CategoryRef>("/admin/catalog/categories"), enabled: open });
  const zonesQ = useQuery({ queryKey: ["admin", "zones", "ref"], queryFn: () => api.get<Zone[]>("/admin/zones"), enabled: active });
  const storesQ = useQuery({ queryKey: ["admin", "stores", "ref"], queryFn: () => api.getPaged<StoreRef>("/admin/stores"), enabled: active });
  const zones = zonesQ.data ?? [];
  const stores = storesQ.data?.rows ?? [];
  const zoneName = (id: Offer["zoneId"]) => (id == null ? null : zones.find((z) => String(z.id) === String(id))?.name ?? `#${id}`);
  const storeName = (id: Offer["storeId"]) => (id == null ? null : stores.find((s) => String(s.id) === String(id))?.name ?? `#${id}`);

  const allCats = cats.data?.rows ?? [];
  const topCats = allCats.filter((c) => c.parentId == null);
  const subCats = form.categoryId != null ? allCats.filter((c) => c.parentId != null && String(c.parentId) === String(form.categoryId)) : [];

  function openCreate() {
    setEditing(null);
    setForm({
      type: "banner", placement: "top", isActive: true, isFallback: false, isPinned: false,
      action: "none", sortOrder: 0, payload: {},
      textTheme: "light", textPosition: "bottom_left", accentColor: "",
    });
    setStagedFile(null); setCropRect(null); setFocus({ x: 0.5, y: 0.5 }); setOpen(true);
  }
  function openEdit(o: Offer) {
    setEditing(o); setForm(o); setStagedFile(null);
    const r = o.cropRect as CropRect | null;
    setCropRect(r && r.w ? r : null);
    setFocus({ x: o.focusX ?? 0.5, y: o.focusY ?? 0.5 }); setOpen(true);
  }

  async function uploadImage(id: string) {
    if (!stagedFile) return;
    const fd = new FormData();
    fd.append("file", stagedFile);
    fd.append("focusX", String(focus.x));
    fd.append("focusY", String(focus.y));
    // The server crops the ORIGINAL file to this rect, so full source resolution
    // survives; without a rect it falls back to a focal-point crop.
    if (cropRect) fd.append("cropRect", JSON.stringify(cropRect));
    await api.upload(`/admin/marketing/offers/${id}/image`, fd);
  }

  async function submit() {
    setBusy(true);
    // type=number inputs yield "" when cleared — coerce to null (nullable fields)
    // so the backend doesn't reject "" as "a valid number is required".
    const num = (v: unknown) => (v === "" || v == null ? null : Number(v));
    try {
      const body: Partial<Offer> = {
        type: form.type, placement: form.placement, title: form.title, subtitle: form.subtitle,
        imageUrl: form.imageUrl, badge: form.badge,
        discountPercent: num(form.discountPercent), dealPrice: num(form.dealPrice),
        categoryId: form.categoryId ?? null, subcategoryId: form.subcategoryId ?? null, isFallback: form.isFallback ?? false,
        zoneId: form.zoneId ?? null, storeId: form.storeId ?? null, isPinned: form.isPinned ?? false,
        action: form.action ?? "none", payload: form.payload ?? {},
        validFrom: form.validFrom || null, validTo: form.validTo || null,
        sortOrder: (num(form.sortOrder) ?? 0) as unknown as number, focusX: focus.x, focusY: focus.y,
        ctaText: form.ctaText ?? "",
        textTheme: form.textTheme ?? "light", textPosition: form.textPosition ?? "bottom_left",
        accentColor: form.accentColor ?? "",
        ...(editing ? {} : { isActive: form.isActive ?? true }),
      };
      const saved = editing
        ? await api.patch<Offer>(`/admin/marketing/offers/${editing.id}`, body)
        : await api.post<Offer>("/admin/marketing/offers", body);
      // Persist identity NOW so an image-upload failure + Save retry PATCHes this
      // same row instead of creating a duplicate orphaned offer.
      if (!editing) { setEditing(saved); setForm(saved); }
      if (stagedFile) {
        try {
          await uploadImage(saved.id);
        } catch {
          toast.error("Banner saved, but the image failed to upload — re-add it and Save again.");
          qc.invalidateQueries({ queryKey: ["mkt", "offers"] });
          return; // keep dialog open in edit mode; retry won't duplicate
        }
      }
      setStagedFile(null);
      toast.success("Saved.");
      qc.invalidateQueries({ queryKey: ["mkt", "offers"] });
      setOpen(false);
    } catch (e) {
      toast.error(e instanceof ApiError ? e.message : "Save failed.");
    } finally {
      setBusy(false);
    }
  }

  /** Delete a banner. Served banners are archived server-side so the
   *  impression/click history behind past reporting survives. */
  async function remove(offer: Offer) {
    setBusy(true);
    try {
      await api.del(`/admin/marketing/offers/${offer.id}`);
      toast.success(
        offer.impressions > 0
          ? "Banner removed. Its performance history was kept for reporting."
          : "Banner deleted."
      );
      qc.invalidateQueries({ queryKey: ["mkt", "offers"] });
      setConfirmDelete(null);
      setOpen(false);
    } catch (e) {
      toast.error(e instanceof ApiError ? e.message : "Could not delete.");
    } finally {
      setBusy(false);
    }
  }

  async function transition(action: string, payload: Record<string, unknown> = {}) {
    if (!editing) return;
    setBusy(true);
    try {
      const updated = await api.post<Offer>(`/admin/marketing/offers/${editing.id}/${action}`, payload);
      toast.success("Updated.");
      qc.invalidateQueries({ queryKey: ["mkt", "offers"] });
      setEditing(updated); setForm(updated);
      setRejectOpen(false);
      setRejectReason("");
    } catch (e) {
      toast.error(e instanceof ApiError ? e.message : "Action failed.");
    } finally {
      setBusy(false);
    }
  }

  const columns: ColumnDef<Offer, unknown>[] = [
    {
      id: "img", header: "", cell: ({ row }) => {
        const src = row.original.image?.thumb ?? row.original.imageUrl;
        return src
          // eslint-disable-next-line @next/next/no-img-element
          ? <img src={api.assetUrl(src)} alt="" className="h-8 w-16 rounded object-cover" />
          : <div className="flex h-8 w-16 items-center justify-center rounded bg-muted"><ImageIcon className="size-3.5 text-muted-foreground" /></div>;
      },
    },
    { accessorKey: "title", header: "Title", cell: ({ row }) => <span className="font-medium">{row.original.title}</span> },
    { accessorKey: "type", header: "Type", cell: ({ row }) => <Badge variant="secondary">{titleize(row.original.type)}</Badge> },
    { id: "zone", header: "Zone / Store", cell: ({ row }) => <span className="text-xs">{storeName(row.original.storeId) ?? zoneName(row.original.zoneId) ?? "Global"}</span> },
    { id: "state", header: "State", cell: ({ row }) => <Badge variant={STATE_VARIANT[row.original.state] ?? "secondary"}>{titleize(row.original.state)}{row.original.isPinned ? " · 📌" : ""}</Badge> },
    { accessorKey: "sortOrder", header: "Priority", cell: ({ row }) => <span className="tabular-nums">{row.original.sortOrder}</span> },
    { id: "ctr", header: "Impr / Clk / CTR", cell: ({ row }) => <span className="tabular-nums text-xs">{row.original.impressions} / {row.original.clicks} / {(row.original.ctr * 100).toFixed(1)}%</span> },
    {
      id: "a", header: "", cell: ({ row }) => (
        <div className="flex items-center justify-end">
          <Button variant="ghost" size="icon" onClick={() => openEdit(row.original)}><Pencil className="size-4" /></Button>
          <Button
            variant="ghost" size="icon" title="Delete banner"
            className="text-destructive hover:text-destructive"
            onClick={() => setConfirmDelete(row.original)}
          >
            <Trash2 className="size-4" />
          </Button>
        </div>
      ),
    },
  ];

  return (
    <>
      <div className="mb-3 flex justify-end"><Button onClick={openCreate}><Plus /> New Banner / Deal</Button></div>
      <DataTable columns={columns} data={query.data?.rows ?? []} loading={query.isLoading} error={query.isError ? "Failed to load." : null} onRetry={() => query.refetch()} emptyMessage="No offers yet." />
      <Dialog open={open} onOpenChange={setOpen}>
        <DialogContent className="max-h-[90vh] max-w-2xl overflow-y-auto">
          <DialogHeader>
            <DialogTitle className="flex items-center gap-2">
              {editing ? "Edit Banner" : "New Banner"}
              {editing && <Badge variant={STATE_VARIANT[editing.state] ?? "secondary"}>{titleize(editing.state)}</Badge>}
            </DialogTitle>
          </DialogHeader>

          {/* Image — aspect-locked crop for the selected placement + live app preview. */}
          <div className="grid gap-4 sm:grid-cols-[1fr_auto]">
            <BannerImageField
              current={form.image?.medium ?? form.imageUrl ?? null}
              staged={stagedFile} focus={focus} spec={spec} cropRect={cropRect}
              onFile={(f) => { setStagedFile(f); setCropRect(null); }}
              onFocus={setFocus} onCrop={setCropRect}
            />
            <BannerPreview
              spec={spec} staged={stagedFile} cropRect={cropRect}
              current={form.image?.medium ?? form.imageUrl ?? null} form={form}
            />
          </div>

          <div className="grid grid-cols-2 gap-3">
            {/* ── The simple path: image, a line of text, where a tap goes. ── */}
            <div className="col-span-2 flex items-center justify-between gap-3 rounded-md border px-3 py-2.5">
              <div className="space-y-0.5">
                <Label className="cursor-pointer">Image only</Label>
                <p className="text-xs text-muted-foreground">
                  The artwork carries everything — no text, badge or button is drawn over it.
                </p>
              </div>
              <Switch
                checked={(form.textTheme ?? "light") === "none"}
                onCheckedChange={(v) => setForm({ ...form, textTheme: v ? "none" : "light" })}
              />
            </div>

            <div className="col-span-2">
              <F label={(form.textTheme ?? "light") === "none" ? "Name (internal — customers never see it)" : "Title"}>
                <Input value={form.title ?? ""} onChange={(e) => setForm({ ...form, title: e.target.value })} />
              </F>
            </div>
            {(form.textTheme ?? "light") !== "none" && (
              <div className="col-span-2">
                <F label="Subtitle (optional)">
                  <Input value={form.subtitle ?? ""} onChange={(e) => setForm({ ...form, subtitle: e.target.value })} />
                </F>
              </div>
            )}

            <div className="col-span-2">
              <F label="Opens on tap">
                <TargetPicker
                  action={form.action ?? "none"}
                  payload={form.payload ?? {}}
                  cats={[...topCats, ...subCats]}
                  onChange={(action, payload) => setForm({ ...form, action, payload })}
                />
              </F>
            </div>

            <F label="Placement">
              <Select value={form.placement ?? "top"} onValueChange={(v) => setForm({ ...form, placement: v })}>
                <SelectTrigger><SelectValue /></SelectTrigger>
                <SelectContent>{PLACEMENTS.map((pl) => <SelectItem key={pl.value} value={pl.value}>{pl.label}</SelectItem>)}</SelectContent>
              </Select>
            </F>
            <div />
            <F label="Start (IST)"><Input type="datetime-local" value={(form.validFrom ?? "").slice(0, 16)} onChange={(e) => setForm({ ...form, validFrom: e.target.value })} /></F>
            <F label="End (IST)"><Input type="datetime-local" value={(form.validTo ?? "").slice(0, 16)} onChange={(e) => setForm({ ...form, validTo: e.target.value })} /></F>

            {!editing && (
              <div className="col-span-2 flex items-center justify-between gap-3 rounded-md border px-3 py-2.5">
                <Label className="cursor-pointer">Publish immediately</Label>
                <Switch checked={form.isActive ?? true} onCheckedChange={(v) => setForm({ ...form, isActive: v })} />
              </div>
            )}

            {/* ── Everything else lives behind one fold. ── */}
            <details className="col-span-2 rounded-md border">
              <summary className="cursor-pointer select-none px-3 py-2.5 text-sm font-medium text-muted-foreground">
                Advanced options
              </summary>
              <div className="grid grid-cols-2 gap-3 border-t p-3">
                <F label="Type">
                  <Select value={form.type ?? "banner"} onValueChange={(v) => setForm({ ...form, type: v })}>
                    <SelectTrigger><SelectValue /></SelectTrigger>
                    <SelectContent>{["banner", "deal", "coupon"].map((t) => <SelectItem key={t} value={t}>{titleize(t)}</SelectItem>)}</SelectContent>
                  </Select>
                </F>
                <F label="Priority (sort)"><Input type="number" value={form.sortOrder ?? 0} onChange={(e) => setForm({ ...form, sortOrder: e.target.value as unknown as number })} /></F>

                {(form.textTheme ?? "light") !== "none" && (<>
                  <div className="col-span-2"><F label="CTA button text (blank = no button)"><Input value={form.ctaText ?? ""} onChange={(e) => setForm({ ...form, ctaText: e.target.value })} placeholder="Shop now" maxLength={40} /></F></div>
                  <F label="Text style">
                    <Select value={form.textTheme ?? "light"} onValueChange={(v) => setForm({ ...form, textTheme: v })}>
                      <SelectTrigger><SelectValue /></SelectTrigger>
                      <SelectContent>{TEXT_THEMES.map((t) => <SelectItem key={t.value} value={t.value}>{t.label}</SelectItem>)}</SelectContent>
                    </Select>
                  </F>
                  <F label="Text position">
                    <Select value={form.textPosition ?? "bottom_left"} onValueChange={(v) => setForm({ ...form, textPosition: v })}>
                      <SelectTrigger><SelectValue /></SelectTrigger>
                      <SelectContent>{TEXT_POSITIONS.map((t) => <SelectItem key={t.value} value={t.value}>{t.label}</SelectItem>)}</SelectContent>
                    </Select>
                  </F>
                  <div className="col-span-2">
                    <F label="Accent colour (CTA pill / badge)">
                      <div className="flex items-center gap-2">
                        <input
                          type="color" value={form.accentColor || "#16a34a"} aria-label="Accent colour"
                          onChange={(e) => setForm({ ...form, accentColor: e.target.value })}
                          className="h-9 w-12 cursor-pointer rounded border bg-transparent p-1"
                        />
                        <Input
                          value={form.accentColor ?? ""} placeholder="#16A34A (blank = brand green)"
                          onChange={(e) => setForm({ ...form, accentColor: e.target.value })}
                        />
                        {form.accentColor && (
                          <Button type="button" variant="ghost" size="sm" onClick={() => setForm({ ...form, accentColor: "" })}>Clear</Button>
                        )}
                      </div>
                    </F>
                  </div>
                  <F label="Badge"><Input value={form.badge ?? ""} onChange={(e) => setForm({ ...form, badge: e.target.value })} /></F>
                  <div />
                </>)}

                <F label="Discount %"><Input type="number" value={form.discountPercent ?? ""} onChange={(e) => setForm({ ...form, discountPercent: e.target.value as unknown as number })} /></F>
                <F label="Deal price (₹)"><Input type="number" value={form.dealPrice ?? ""} onChange={(e) => setForm({ ...form, dealPrice: e.target.value as unknown as number })} /></F>

                <F label="Show on category screens">
                  <Select value={form.categoryId != null ? String(form.categoryId) : ANY} onValueChange={(v) => setForm({ ...form, categoryId: v === ANY ? null : v, subcategoryId: null })}>
                    <SelectTrigger><SelectValue /></SelectTrigger>
                    <SelectContent>
                      <SelectItem value={ANY}>— Any —</SelectItem>
                      {topCats.map((c) => <SelectItem key={c.id} value={String(c.id)}>{c.name}</SelectItem>)}
                    </SelectContent>
                  </Select>
                </F>
                <F label="Subcategory">
                  <Select value={form.subcategoryId != null ? String(form.subcategoryId) : ANY} onValueChange={(v) => setForm({ ...form, subcategoryId: v === ANY ? null : v })}>
                    <SelectTrigger><SelectValue /></SelectTrigger>
                    <SelectContent>
                      <SelectItem value={ANY}>— Any —</SelectItem>
                      {subCats.map((c) => <SelectItem key={c.id} value={String(c.id)}>{c.name}</SelectItem>)}
                    </SelectContent>
                  </Select>
                </F>

                <F label="Zone (target)">
                  <Select value={form.zoneId != null ? String(form.zoneId) : ANY} onValueChange={(v) => setForm({ ...form, zoneId: v === ANY ? null : v })}>
                    <SelectTrigger><SelectValue /></SelectTrigger>
                    <SelectContent>
                      <SelectItem value={ANY}>— Global —</SelectItem>
                      {zones.map((z) => <SelectItem key={z.id} value={String(z.id)}>{z.name}</SelectItem>)}
                    </SelectContent>
                  </Select>
                </F>
                <F label="Store (target)">
                  <Select value={form.storeId != null ? String(form.storeId) : ANY} onValueChange={(v) => setForm({ ...form, storeId: v === ANY ? null : v })}>
                    <SelectTrigger><SelectValue /></SelectTrigger>
                    <SelectContent>
                      <SelectItem value={ANY}>— Any —</SelectItem>
                      {stores.map((st) => <SelectItem key={st.id} value={String(st.id)}>{st.name}</SelectItem>)}
                    </SelectContent>
                  </Select>
                </F>

                <div className="col-span-2 flex items-center justify-between gap-3 rounded-md border px-3 py-2.5">
                  <div className="space-y-0.5">
                    <Label className="cursor-pointer">Pin to top</Label>
                    <p className="text-xs text-muted-foreground">Forces this banner above others in its placement.</p>
                  </div>
                  <Switch checked={form.isPinned ?? false} onCheckedChange={(v) => setForm({ ...form, isPinned: v })} />
                </div>
                <div className="col-span-2 flex items-start justify-between gap-3 rounded-md border px-3 py-2.5">
                  <div className="space-y-0.5">
                    <Label className="cursor-pointer">Is marketing fallback</Label>
                    <p className="text-xs text-muted-foreground">Shown on product screens when no category-targeted banner matches.</p>
                  </div>
                  <Switch checked={form.isFallback ?? false} onCheckedChange={(v) => setForm({ ...form, isFallback: v })} />
                </div>
              </div>
            </details>
          </div>

          {/* Workflow transitions (edit mode) */}
          {editing && (
            <div className="flex flex-wrap items-center gap-2 rounded-md border bg-muted/30 px-3 py-2">
              <span className="text-xs text-muted-foreground">Workflow:</span>
              {(TRANSITIONS[editing.state] ?? []).map((t) => (
                <Button
                  key={t}
                  size="sm"
                  variant={t === "approve" ? "default" : "outline"}
                  disabled={busy}
                  onClick={() => (t === "reject" ? (setRejectReason(""), setRejectOpen(true)) : transition(t))}
                >
                  {titleize(t)}
                </Button>
              ))}
              {editing.rejectionReason && <span className="text-xs text-destructive">Rejected: {editing.rejectionReason}</span>}
            </div>
          )}

          <DialogFooter className="gap-2">
            {editing && (
              <Button
                variant="ghost" disabled={busy}
                className="mr-auto text-destructive hover:text-destructive"
                onClick={() => setConfirmDelete(editing)}
              >
                <Trash2 className="size-4" /> Delete
              </Button>
            )}
            <Button variant="outline" onClick={() => setOpen(false)} disabled={busy}>Cancel</Button>
            <Button onClick={submit} disabled={busy || !form.title}>{busy && <Loader2 className="size-4 animate-spin" />} Save</Button>
          </DialogFooter>
        </DialogContent>
      </Dialog>

      <ConfirmDialog
        open={confirmDelete != null}
        onOpenChange={(o) => !o && setConfirmDelete(null)}
        title={`Delete "${confirmDelete?.title ?? ""}"?`}
        description={
          (confirmDelete?.impressions ?? 0) > 0
            ? "This banner has been served to customers, so it will be archived rather than erased — its impression and click history stays available for reporting. It will stop showing in the app immediately."
            : "This banner has never been shown to a customer and will be permanently deleted."
        }
        confirmLabel="Delete banner"
        destructive
        loading={busy}
        onConfirm={() => confirmDelete && remove(confirmDelete)}
      />

      <Dialog open={rejectOpen} onOpenChange={(o) => { if (!o) { setRejectOpen(false); setRejectReason(""); } }}>
        <DialogContent className="max-w-md">
          <DialogHeader>
            <DialogTitle>Reject “{editing?.title ?? "banner"}”?</DialogTitle>
          </DialogHeader>
          <div className="space-y-1.5">
            <Label htmlFor="reject-reason">Reason for rejection</Label>
            <Textarea
              id="reject-reason"
              rows={3}
              autoFocus
              value={rejectReason}
              onChange={(e) => setRejectReason(e.target.value)}
              placeholder="e.g. Image is off-brand — the logo is cropped at the top edge."
            />
            <p className="text-xs text-muted-foreground">
              Sent back to the submitting store, who sees this text verbatim. The banner stays out of the app until
              it is resubmitted.
            </p>
          </div>
          <DialogFooter className="gap-2">
            <Button variant="outline" onClick={() => { setRejectOpen(false); setRejectReason(""); }} disabled={busy}>
              Cancel
            </Button>
            <Button
              variant="destructive"
              disabled={busy || !rejectReason.trim()}
              onClick={() => transition("reject", { reason: rejectReason.trim() })}
            >
              {busy && <Loader2 className="size-4 animate-spin" />} Reject banner
            </Button>
          </DialogFooter>
        </DialogContent>
      </Dialog>
    </>
  );
}

/**
 * Inline styles that render exactly the region the server will crop.
 *
 * `object-position` can't express this: a cover-fit image only has slack on one
 * axis, so a *zoomed* crop (both rect.w and rect.h < 1) is unrepresentable. Blowing
 * the image up to `100/rect.w` percent and offsetting it is exact for any rect.
 */
function cropImageStyle(rect: CropRect | null, focus: { x: number; y: number }): React.CSSProperties {
  if (!rect || !rect.w || !rect.h) {
    // No crop yet — approximate the server's focal-point crop with cover-fit.
    return { objectFit: "cover", objectPosition: `${focus.x * 100}% ${focus.y * 100}%`, width: "100%", height: "100%" };
  }
  return {
    position: "absolute",
    width: `${100 / rect.w}%`,
    height: `${100 / rect.h}%`,
    left: `${(-rect.x / rect.w) * 100}%`,
    top: `${(-rect.y / rect.h) * 100}%`,
    maxWidth: "none",
  };
}

function BannerImageField({ current, staged, focus, spec, cropRect, onFile, onFocus, onCrop }: {
  current: string | null; staged: File | null; focus: { x: number; y: number };
  spec: BannerSpec | null; cropRect: CropRect | null;
  onFile: (f: File | null) => void; onFocus: (f: { x: number; y: number }) => void;
  onCrop: (r: CropRect | null) => void;
}) {
  const [cropping, setCropping] = React.useState(false);
  const preview = React.useMemo(() => (staged ? URL.createObjectURL(staged) : null), [staged]);
  React.useEffect(() => () => { if (preview) URL.revokeObjectURL(preview); }, [preview]);
  const src = preview ?? (current ? api.assetUrl(current) : null);
  const ratio = spec?.ratio ?? 1.6;

  // A newly chosen file goes straight into the cropper — cropping is the point.
  function chooseFile(f: File | null) {
    onFile(f);
    if (f) setCropping(true);
  }

  function pickFocus(e: React.MouseEvent<HTMLDivElement>) {
    const r = e.currentTarget.getBoundingClientRect();
    onFocus({
      x: Math.min(Math.max((e.clientX - r.left) / r.width, 0), 1),
      y: Math.min(Math.max((e.clientY - r.top) / r.height, 0), 1),
    });
  }

  return (
    <div className="space-y-2">
      <Label>
        Banner image
        {spec && (
          <span className="ml-1 font-normal text-muted-foreground">
            — {spec.aspect}, saved at {spec.master.width}×{spec.master.height}px
          </span>
        )}
      </Label>
      <div
        className="relative w-full overflow-hidden rounded-md border bg-muted"
        style={{ aspectRatio: String(ratio) }}
        onClick={src && !cropRect ? pickFocus : undefined}
        role={src && !cropRect ? "button" : undefined}
      >
        {src ? (
          <>
            {/* eslint-disable-next-line @next/next/no-img-element */}
            <img src={src} alt="banner preview" style={cropImageStyle(cropRect, focus)} />
            {!cropRect && (
              <span
                className="pointer-events-none absolute size-4 -translate-x-1/2 -translate-y-1/2 rounded-full border-2 border-white shadow ring-2 ring-black/40"
                style={{ left: `${focus.x * 100}%`, top: `${focus.y * 100}%` }}
              />
            )}
          </>
        ) : (
          <div className="flex h-full w-full flex-col items-center justify-center gap-1 text-muted-foreground">
            <ImageIcon className="size-6" /><span className="text-xs">No image</span>
          </div>
        )}
      </div>

      <div className="flex flex-wrap items-center gap-2">
        <label className="inline-flex">
          <input type="file" accept="image/png,image/jpeg,image/webp" className="hidden"
            onChange={(e) => chooseFile(e.target.files?.[0] ?? null)} />
          <span className="inline-flex cursor-pointer items-center gap-1.5 rounded-md border px-3 py-1.5 text-sm hover:bg-accent">
            <Upload className="size-3.5" /> {staged ? staged.name : "Choose image…"}
          </span>
        </label>
        {staged && (
          <Button type="button" variant="outline" size="sm" onClick={() => setCropping(true)}>
            <Crop className="size-3.5" /> {cropRect ? "Adjust crop" : "Crop"}
          </Button>
        )}
        {cropRect && (
          <Button type="button" variant="ghost" size="sm" onClick={() => onCrop(null)}>
            Reset to focal point
          </Button>
        )}
      </div>
      <p className="text-xs text-muted-foreground">
        {staged
          ? cropRect
            ? "Cropped. The server crops the original file to this frame — full resolution is preserved."
            : "Not cropped — the server will centre-crop around the focal point (click the preview to move it)."
          : spec?.note}
      </p>

      {cropping && staged && spec && (
        <BannerCropDialog
          file={staged}
          aspect={spec.ratio}
          aspectLabel={spec.aspect}
          minWidth={spec.minUpload.width}
          minHeight={spec.minUpload.height}
          placementLabel={spec.label}
          initialRect={cropRect}
          onCancel={() => setCropping(false)}
          onDone={(r, resized) => {
            // A resized export replaces the staged original — it is already
            // cropped and at the placement's exact resolution, so it ships with
            // a full-frame rect and the server just re-encodes it.
            if (resized) onFile(resized);
            onCrop(r);
            setCropping(false);
          }}
        />
      )}
    </div>
  );
}

/**
 * Live phone-frame preview: the same box geometry the Flutter app renders, so
 * marketing can see the overlay land before publishing.
 */
function BannerPreview({ spec, staged, cropRect, current, form }: {
  spec: BannerSpec | null; staged: File | null; cropRect: CropRect | null;
  current: string | null; form: Partial<Offer>;
}) {
  const preview = React.useMemo(() => (staged ? URL.createObjectURL(staged) : null), [staged]);
  React.useEffect(() => () => { if (preview) URL.revokeObjectURL(preview); }, [preview]);
  const src = preview ?? (current ? api.assetUrl(current) : null);

  const W = 200; // preview width ≈ a 360dp phone's carousel card, scaled down
  const H = Math.round(W / (spec?.ratio ?? 1.6));
  const theme = form.textTheme ?? "light";
  const pos = form.textPosition ?? "bottom_left";
  const accent = form.accentColor || "#16a34a";

  const align =
    pos === "bottom_center" ? "items-end text-center justify-items-center"
    : pos === "center" ? "items-center"
    : pos === "top_left" ? "items-start"
    : "items-end";

  return (
    <div className="space-y-2">
      <Label>App preview</Label>
      <div className="rounded-[1.25rem] border-4 border-foreground/80 bg-background p-1.5">
        <div
          className="relative overflow-hidden rounded-[0.75rem] bg-muted"
          style={{ width: W, height: H }}
        >
          {src ? (
            // eslint-disable-next-line @next/next/no-img-element
            <img src={src} alt=""
                 style={cropImageStyle(cropRect, { x: form.focusX ?? 0.5, y: form.focusY ?? 0.5 })} />
          ) : (
            <div className="absolute inset-0 bg-gradient-to-br from-emerald-500 to-emerald-700" />
          )}

          {theme !== "none" && (
            <>
              <div
                className="absolute inset-0"
                style={{
                  background: theme === "dark"
                    ? "linear-gradient(to top, rgba(255,255,255,0.88) 0%, rgba(255,255,255,0) 55%)"
                    : "linear-gradient(to top, rgba(0,0,0,0.62) 0%, rgba(0,0,0,0) 55%)",
                }}
              />
              <div className={`absolute inset-0 grid content-between p-2 ${align}`}>
                <div className="grid gap-1">
                  {form.badge && (
                    <span className="w-fit rounded px-1.5 py-0.5 text-[8px] font-semibold text-white"
                          style={{ background: accent }}>{form.badge}</span>
                  )}
                  <span className={`text-[11px] font-bold leading-tight ${theme === "dark" ? "text-neutral-900" : "text-white"}`}>
                    {form.title || "Banner headline"}
                  </span>
                  {form.subtitle && (
                    <span className={`text-[9px] leading-tight ${theme === "dark" ? "text-neutral-700" : "text-white/90"}`}>
                      {form.subtitle}
                    </span>
                  )}
                  {form.ctaText && (
                    <span className="mt-0.5 w-fit rounded-full px-2 py-0.5 text-[8px] font-semibold text-white"
                          style={{ background: accent }}>{form.ctaText}</span>
                  )}
                </div>
              </div>
            </>
          )}
        </div>
      </div>
      <p className="max-w-[212px] text-[11px] text-muted-foreground">
        {spec ? `${spec.label} · ${spec.aspect}` : "Select a placement"}
      </p>
    </div>
  );
}

function CouponsTab({ active }: { active: boolean }) {
  const [open, setOpen] = React.useState(false);
  const [editing, setEditing] = React.useState<Coupon | null>(null);
  const [form, setForm] = React.useState<Partial<Coupon>>({});
  const query = useQuery({ queryKey: ["mkt", "coupons"], queryFn: () => api.getPaged<Coupon>("/admin/marketing/coupons"), enabled: active });
  const save = useApiMutation(
    (body: Partial<Coupon>) => (editing ? api.patch(`/admin/marketing/coupons/${editing.id}`, body) : api.post("/admin/marketing/coupons", body)),
    { invalidate: [["mkt", "coupons"]], successMessage: "Saved.", onDone: () => setOpen(false) }
  );
  const remove = useApiMutation(
    () => api.del(`/admin/marketing/coupons/${editing!.id}`),
    { invalidate: [["mkt", "coupons"]], successMessage: "Coupon deleted.", onDone: () => { setConfirmDelete(false); setOpen(false); } }
  );
  const [confirmDelete, setConfirmDelete] = React.useState(false);
  function openCreate() { setEditing(null); setForm({ discountType: "percent", isActive: true }); setOpen(true); }
  function openEdit(c: Coupon) { setEditing(c); setForm(c); setOpen(true); }
  const columns: ColumnDef<Coupon, unknown>[] = [
    { accessorKey: "code", header: "Code", cell: ({ row }) => <span className="font-mono font-medium">{row.original.code}</span> },
    { accessorKey: "discountType", header: "Type", cell: ({ row }) => titleize(row.original.discountType) },
    { accessorKey: "value", header: "Value", cell: ({ row }) => (row.original.discountType === "percent" ? `${row.original.value}%` : inr(row.original.value)) },
    { accessorKey: "minOrder", header: "Min Order", cell: ({ row }) => (row.original.minOrder ? inr(row.original.minOrder) : "—") },
    { accessorKey: "redemptions", header: "Used", cell: ({ row }) => <span className="tabular-nums">{row.original.redemptions}</span> },
    { accessorKey: "isActive", header: "Active", cell: ({ row }) => <BoolBadge value={row.original.isActive} /> },
    { id: "a", header: "", cell: ({ row }) => <Button variant="ghost" size="icon" onClick={() => openEdit(row.original)}><Pencil className="size-4" /></Button> },
  ];
  return (
    <>
      <div className="mb-3 flex justify-end"><Button onClick={openCreate}><Plus /> New Coupon</Button></div>
      <DataTable columns={columns} data={query.data?.rows ?? []} loading={query.isLoading} error={query.isError ? "Failed to load." : null} onRetry={() => query.refetch()} emptyMessage="No coupons yet." />
      <Dialog open={open} onOpenChange={setOpen}>
        <DialogContent>
          <DialogHeader><DialogTitle className="flex items-center gap-2"><Ticket className="size-4" /> {editing ? "Edit Coupon" : "New Coupon"}</DialogTitle></DialogHeader>
          <div className="grid grid-cols-2 gap-3">
            <F label="Code"><Input value={form.code ?? ""} onChange={(e) => setForm({ ...form, code: e.target.value.toUpperCase() })} /></F>
            <F label="Discount type">
              <Select value={form.discountType ?? "percent"} onValueChange={(v) => setForm({ ...form, discountType: v })}>
                <SelectTrigger><SelectValue /></SelectTrigger>
                <SelectContent><SelectItem value="percent">Percent</SelectItem><SelectItem value="flat">Flat</SelectItem></SelectContent>
              </Select>
            </F>
            <F label="Value"><Input type="number" value={form.value ?? ""} onChange={(e) => setForm({ ...form, value: e.target.value as unknown as number })} /></F>
            <F label="Min order (₹)"><Input type="number" value={form.minOrder ?? ""} onChange={(e) => setForm({ ...form, minOrder: e.target.value as unknown as number })} /></F>
            <F label="Max discount (₹)"><Input type="number" value={form.maxDiscount ?? ""} onChange={(e) => setForm({ ...form, maxDiscount: e.target.value as unknown as number })} /></F>
            <F label="Usage limit"><Input type="number" value={form.usageLimit ?? ""} onChange={(e) => setForm({ ...form, usageLimit: e.target.value as unknown as number })} /></F>
            <F label="Per-user limit"><Input type="number" value={form.perUserLimit ?? ""} onChange={(e) => setForm({ ...form, perUserLimit: e.target.value as unknown as number })} /></F>
            <F label="Valid to"><Input type="date" value={form.validTo ?? ""} onChange={(e) => setForm({ ...form, validTo: e.target.value })} /></F>
            {/* Without this the backend's is_active flag was unreachable from the UI —
                a live coupon could only be stopped by editing the DB. */}
            <div className="col-span-2 flex items-center justify-between gap-3 rounded-md border px-3 py-2.5">
              <div className="space-y-0.5">
                <Label className="cursor-pointer">Active</Label>
                <p className="text-xs text-muted-foreground">Inactive coupons stop validating at checkout immediately.</p>
              </div>
              <Switch checked={form.isActive ?? true} onCheckedChange={(v) => setForm({ ...form, isActive: v })} />
            </div>
          </div>
          <DialogFooter className="gap-2">
            {editing && (
              <Button variant="ghost" className="mr-auto text-destructive hover:text-destructive"
                      disabled={save.isPending || remove.isPending}
                      onClick={() => setConfirmDelete(true)}>
                <Trash2 className="size-4" /> Delete
              </Button>
            )}
            <Button variant="outline" onClick={() => setOpen(false)} disabled={save.isPending}>Cancel</Button>
            <Button onClick={() => save.mutate(form)} disabled={save.isPending || !form.code}>{save.isPending && <Loader2 className="size-4 animate-spin" />} Save</Button>
          </DialogFooter>
        </DialogContent>
      </Dialog>
      <ConfirmDialog
        open={confirmDelete}
        onOpenChange={setConfirmDelete}
        title={`Delete ${editing?.code ?? "coupon"}?`}
        description="Past redemptions are kept for accounting, but the code stops working immediately. Deactivate instead if you may re-run this promotion."
        confirmLabel="Delete coupon"
        destructive
        loading={remove.isPending}
        onConfirm={() => remove.mutate(undefined)}
      />
    </>
  );
}

function CampaignTab({ active }: { active: boolean }) {
  const [title, setTitle] = React.useState("");
  const [body, setBody] = React.useState("");
  const [segment, setSegment] = React.useState("all");
  const [zoneId, setZoneId] = React.useState("");
  const [image, setImage] = React.useState<string | null>(null);
  const [confirming, setConfirming] = React.useState(false);
  const zones = useQuery({ queryKey: ["admin", "zones", "ref"], queryFn: () => api.get<Zone[]>("/admin/zones"), enabled: active && segment === "zone" });
  const send = useApiMutation(
    () => api.post<{ sent: number }>("/admin/marketing/notify", { title, body, segment, imageUrl: image || undefined, zoneId: segment === "zone" ? zoneId : undefined }),
    { successMessage: "Campaign sent.", onDone: () => { setConfirming(false); setTitle(""); setBody(""); setImage(null); } }
  );

  const zoneName = (zones.data ?? []).find((z) => String(z.id) === zoneId)?.name ?? "the selected zone";
  const audience =
    segment === "credit" ? "every VS Credit customer"
      : segment === "zone" ? `every customer in ${zoneName}`
        : "EVERY VS Mart customer with the app installed";

  return (
    <Card className="max-w-xl">
      <CardHeader><CardTitle className="flex items-center gap-2"><Megaphone className="size-4" /> Push a campaign</CardTitle></CardHeader>
      <CardContent className="space-y-4">
        <F label="Title"><Input value={title} onChange={(e) => setTitle(e.target.value)} placeholder="Weekend Sale!" /></F>
        <F label="Message"><Input value={body} onChange={(e) => setBody(e.target.value)} placeholder="Flat 20% off groceries this weekend." /></F>
        <F label="Image (optional — shown in the notification; defaults to the app logo)">
          <ImageUpload value={image} onChange={setImage} category="marketing" />
        </F>
        <F label="Segment">
          <Select value={segment} onValueChange={setSegment}>
            <SelectTrigger><SelectValue /></SelectTrigger>
            <SelectContent>
              <SelectItem value="all">All customers</SelectItem>
              <SelectItem value="credit">Credit customers</SelectItem>
              <SelectItem value="zone">Zone customers</SelectItem>
            </SelectContent>
          </Select>
        </F>
        {segment === "zone" && (
          <F label="Zone">
            <Select value={zoneId} onValueChange={setZoneId}>
              <SelectTrigger><SelectValue placeholder="Select zone" /></SelectTrigger>
              <SelectContent>{(zones.data ?? []).map((z) => <SelectItem key={z.id} value={z.id}>{z.name}</SelectItem>)}</SelectContent>
            </Select>
          </F>
        )}
        <Button onClick={() => setConfirming(true)} disabled={send.isPending || !title || (segment === "zone" && !zoneId)}>
          {send.isPending ? <Loader2 className="size-4 animate-spin" /> : <Send />} Send campaign
        </Button>
      </CardContent>

      <ConfirmDialog
        open={confirming}
        onOpenChange={setConfirming}
        title="Send this push to every phone in the segment?"
        description={
          `“${title}” goes out as a phone notification to ${audience}. Push notifications are delivered immediately ` +
          `and cannot be recalled, edited or deleted once sent — there is no undo. Re-read the title and message before ` +
          `confirming.`
        }
        confirmLabel="Send campaign"
        destructive
        loading={send.isPending}
        onConfirm={() => send.mutate(undefined)}
      />
    </Card>
  );
}

function F({ label, children }: { label: string; children: React.ReactNode }) {
  return <div className="space-y-1.5"><Label>{label}</Label>{children}</div>;
}


// ── Target picker ────────────────────────────────────────────────────────────
const SCREEN_TARGETS: { action: string; label: string }[] = [
  { action: "none", label: "Nothing (decorative)" },
  { action: "home", label: "Home" },
  { action: "offers", label: "Offers" },
  { action: "cart", label: "Cart" },
  { action: "credit", label: "VS Credit" },
  { action: "profile", label: "Profile" },
  { action: "store", label: "Store" },
];

/** One search box for "where does a tap go" — type to find a product or a
 *  category, pick an app screen, or turn the typed text into an in-app search.
 *  Replaces the old two-step "action enum + raw numeric ID" pair, which
 *  required knowing database IDs by heart. */
function TargetPicker({
  action, payload, cats, onChange,
}: {
  action: string;
  payload: Record<string, unknown>;
  cats: { id: number | string; name: string }[];
  onChange: (action: string, payload: Record<string, unknown>) => void;
}) {
  const [query, setQuery] = React.useState("");
  const [openList, setOpenList] = React.useState(false);
  const [pickedLabel, setPickedLabel] = React.useState<string | null>(null);
  const [q, setQ] = React.useState("");
  React.useEffect(() => {
    const t = setTimeout(() => setQ(query.trim()), 250);
    return () => clearTimeout(t);
  }, [query]);

  const products = useQuery({
    queryKey: ["marketing", "target-products", q],
    queryFn: () => api.getPaged<{ id: number | string; name: string }>(
      "/admin/catalog/products", { q }),
    enabled: openList && q.length >= 2,
  });

  const lower = q.toLowerCase();
  const screenHits = SCREEN_TARGETS.filter(
    (t) => !lower || t.label.toLowerCase().includes(lower));
  const catHits = lower
    ? cats.filter((c) => c.name.toLowerCase().includes(lower)).slice(0, 6)
    : [];
  const productHits = (products.data?.rows ?? []).slice(0, 6);

  function pick(a: string, p: Record<string, unknown>, label: string) {
    onChange(a, p);
    setPickedLabel(label);
    setQuery("");
    setOpenList(false);
  }

  const current =
    pickedLabel ??
    (action === "none" ? "Nothing (decorative)"
      : action === "product" ? `Product #${payload.productId ?? "?"}`
      : action === "category" ? `Category #${payload.categoryId ?? "?"}`
      : action === "search" ? `Search “${payload.query ?? ""}”`
      : SCREEN_TARGETS.find((t) => t.action === action)?.label ?? titleize(action));

  return (
    <div className="relative">
      <div className="flex items-center gap-2">
        <Input
          value={query}
          placeholder={`Currently: ${current} — type to change…`}
          onFocus={() => setOpenList(true)}
          onChange={(e) => { setQuery(e.target.value); setOpenList(true); }}
        />
        {action !== "none" && (
          <Button type="button" variant="ghost" size="sm"
                  onClick={() => pick("none", {}, "Nothing (decorative)")}>
            Clear
          </Button>
        )}
      </div>
      {openList && (
        <div className="absolute z-50 mt-1 max-h-72 w-full overflow-y-auto rounded-md border bg-popover p-1 shadow-md">
          {screenHits.length > 0 && (
            <p className="px-2 py-1 text-[11px] font-semibold uppercase text-muted-foreground">Screens</p>
          )}
          {screenHits.map((t) => (
            <button key={t.action} type="button"
              className="block w-full rounded px-2 py-1.5 text-left text-sm hover:bg-accent"
              onClick={() => pick(t.action, {}, t.label)}>
              {t.label}
            </button>
          ))}
          {catHits.length > 0 && (
            <p className="px-2 py-1 text-[11px] font-semibold uppercase text-muted-foreground">Categories</p>
          )}
          {catHits.map((c) => (
            <button key={`c${c.id}`} type="button"
              className="block w-full rounded px-2 py-1.5 text-left text-sm hover:bg-accent"
              onClick={() => pick("category", { categoryId: Number(c.id) }, `Category: ${c.name}`)}>
              {c.name}
            </button>
          ))}
          {q.length >= 2 && (
            <p className="px-2 py-1 text-[11px] font-semibold uppercase text-muted-foreground">Products</p>
          )}
          {products.isLoading && q.length >= 2 && (
            <p className="px-2 py-1.5 text-sm text-muted-foreground">Searching…</p>
          )}
          {productHits.map((pr) => (
            <button key={`p${pr.id}`} type="button"
              className="block w-full rounded px-2 py-1.5 text-left text-sm hover:bg-accent"
              onClick={() => pick("product", { productId: Number(pr.id) }, `Product: ${pr.name}`)}>
              {pr.name}
            </button>
          ))}
          {q.length >= 2 && (
            <button type="button"
              className="block w-full rounded px-2 py-1.5 text-left text-sm hover:bg-accent"
              onClick={() => pick("search", { query: q }, `Search “${q}”`)}>
              Search the app for “{q}”
            </button>
          )}
          <div className="border-t p-1 text-right">
            <Button type="button" variant="ghost" size="sm" onClick={() => setOpenList(false)}>Close</Button>
          </div>
        </div>
      )}
    </div>
  );
}
