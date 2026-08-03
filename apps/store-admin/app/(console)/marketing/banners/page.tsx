"use client";

import * as React from "react";
import { useQuery, useQueryClient } from "@tanstack/react-query";
import { type ColumnDef } from "@tanstack/react-table";
import { Crop, ImageIcon, Loader2, Pencil, Plus, Send, Upload } from "lucide-react";
import { toast } from "sonner";
import { api } from "@/lib/api/client";
import { ApiError } from "@/lib/types";
import { PageHeader } from "@/components/page-header";
import { DataTable } from "@/components/data-table";
import { RequirePerm } from "@/components/permission-gate";
import { BannerCropDialog, type CropRect } from "@/components/banner-cropper";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import { Badge } from "@/components/ui/badge";
import { Textarea } from "@/components/ui/textarea";
import { Dialog, DialogContent, DialogFooter, DialogHeader, DialogTitle } from "@/components/ui/dialog";
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from "@/components/ui/select";
import { titleize } from "@/lib/utils";

interface BannerImage { large?: string; medium?: string; small?: string; thumb?: string }
interface StoreBanner {
  id: string; type: string; placement: string; title: string; subtitle: string;
  ctaText: string; textTheme: string; textPosition: string; accentColor: string;
  action: string; payload: Record<string, unknown> | null;
  validFrom: string | null; validTo: string | null; sortOrder: number;
  state: string; rejectionReason: string;
  image: BannerImage | null; impressions: number; clicks: number;
}
interface BannerSpec {
  placement: string; label: string; note: string; ratio: number; aspect: string;
  master: { width: number; height: number };
  minUpload: { width: number; height: number };
  sizes: { name: string; width: number; height: number }[];
}

const STATE_VARIANT: Record<string, "success" | "warning" | "secondary" | "destructive"> = {
  active: "success", scheduled: "warning", pending: "warning",
  draft: "secondary", paused: "secondary", expired: "destructive", archived: "destructive",
};
// A store may only edit while the banner is still a draft; everything else is
// frozen until an admin acts on it.
const EDITABLE = new Set(["draft"]);

const ACTIONS: { value: string; label: string; field?: { key: string; label: string; type: string } }[] = [
  { value: "none", label: "None" },
  { value: "home", label: "Open Home" },
  { value: "offers", label: "Open Offers" },
  { value: "cart", label: "Open Cart" },
  { value: "category", label: "Open Category", field: { key: "categoryId", label: "Category ID", type: "number" } },
  { value: "product", label: "Open Product", field: { key: "productId", label: "Product ID", type: "number" } },
  { value: "search", label: "Open Search", field: { key: "query", label: "Search query", type: "text" } },
];

export default function StoreBannersPage() {
  return (
    <RequirePerm perm="marketing.banners">
      <PageHeader
        title="Store Banners"
        description="Propose banners for your store's customers. A super-admin reviews and publishes them."
      />
      <BannersTab />
    </RequirePerm>
  );
}

function BannersTab() {
  const qc = useQueryClient();
  const [open, setOpen] = React.useState(false);
  const [editing, setEditing] = React.useState<StoreBanner | null>(null);
  const [form, setForm] = React.useState<Partial<StoreBanner>>({});
  const [stagedFile, setStagedFile] = React.useState<File | null>(null);
  const [cropRect, setCropRect] = React.useState<CropRect | null>(null);
  const [cropping, setCropping] = React.useState(false);
  const [busy, setBusy] = React.useState(false);

  const query = useQuery({
    queryKey: ["store", "banners"],
    queryFn: () => api.get<{ results: StoreBanner[]; specs: BannerSpec[] }>("/store/marketing/banners"),
  });
  const rows = query.data?.results ?? [];
  const specs = query.data?.specs ?? [];
  const spec = specs.find((s) => s.placement === (form.placement ?? "top")) ?? null;
  const actionDef = ACTIONS.find((a) => a.value === (form.action ?? "none"));
  const canEdit = !editing || EDITABLE.has(editing.state);

  function openCreate() {
    setEditing(null);
    setForm({ type: "banner", placement: "top", action: "none", payload: {}, textTheme: "light", textPosition: "bottom_left", sortOrder: 0 });
    setStagedFile(null); setCropRect(null); setOpen(true);
  }
  function openEdit(b: StoreBanner) {
    setEditing(b); setForm(b); setStagedFile(null); setCropRect(null); setOpen(true);
  }

  async function submit() {
    setBusy(true);
    try {
      const body: Partial<StoreBanner> = {
        type: "banner", placement: form.placement, title: form.title, subtitle: form.subtitle,
        ctaText: form.ctaText ?? "", textTheme: form.textTheme ?? "light",
        textPosition: form.textPosition ?? "bottom_left", accentColor: form.accentColor ?? "",
        action: form.action ?? "none", payload: form.payload ?? {},
        validFrom: form.validFrom || null, validTo: form.validTo || null,
      };
      const saved = editing
        ? await api.patch<StoreBanner>(`/store/marketing/banners/${editing.id}`, body)
        : await api.post<StoreBanner>("/store/marketing/banners", body);
      // Persist identity before the image call so a failed upload + retry PATCHes
      // this row instead of creating a duplicate draft.
      if (!editing) { setEditing(saved); setForm(saved); }
      if (stagedFile) {
        const fd = new FormData();
        fd.append("file", stagedFile);
        if (cropRect) fd.append("cropRect", JSON.stringify(cropRect));
        try {
          await api.upload(`/store/marketing/banners/${saved.id}/image`, fd);
        } catch {
          toast.error("Banner saved, but the image failed to upload — re-add it and Save again.");
          qc.invalidateQueries({ queryKey: ["store", "banners"] });
          return;
        }
      }
      setStagedFile(null);
      toast.success("Saved as a draft.");
      qc.invalidateQueries({ queryKey: ["store", "banners"] });
      setOpen(false);
    } catch (e) {
      toast.error(e instanceof ApiError ? e.message : "Save failed.");
    } finally {
      setBusy(false);
    }
  }

  async function sendForApproval() {
    if (!editing) return;
    setBusy(true);
    try {
      await api.post(`/store/marketing/banners/${editing.id}/submit`, {});
      toast.success("Sent for approval.");
      qc.invalidateQueries({ queryKey: ["store", "banners"] });
      setOpen(false);
    } catch (e) {
      toast.error(e instanceof ApiError ? e.message : "Could not submit.");
    } finally {
      setBusy(false);
    }
  }

  const columns: ColumnDef<StoreBanner, unknown>[] = [
    {
      id: "img", header: "", cell: ({ row }) => {
        const src = row.original.image?.thumb;
        return src
          ? // eslint-disable-next-line @next/next/no-img-element
            <img src={api.assetUrl(src)} alt="" className="h-8 w-14 rounded object-cover" />
          : <div className="flex h-8 w-14 items-center justify-center rounded bg-muted"><ImageIcon className="size-3.5 text-muted-foreground" /></div>;
      },
    },
    { accessorKey: "title", header: "Title", cell: ({ row }) => <span className="font-medium">{row.original.title}</span> },
    { accessorKey: "placement", header: "Placement", cell: ({ row }) => <Badge variant="secondary">{titleize(row.original.placement)}</Badge> },
    {
      id: "state", header: "Status", cell: ({ row }) => (
        <div className="flex flex-col gap-0.5">
          <Badge variant={STATE_VARIANT[row.original.state] ?? "secondary"}>{titleize(row.original.state)}</Badge>
          {row.original.rejectionReason && (
            <span className="text-xs text-destructive">{row.original.rejectionReason}</span>
          )}
        </div>
      ),
    },
    { id: "perf", header: "Impr / Clicks", cell: ({ row }) => <span className="tabular-nums text-xs">{row.original.impressions} / {row.original.clicks}</span> },
    { id: "a", header: "", cell: ({ row }) => <Button variant="ghost" size="icon" onClick={() => openEdit(row.original)}><Pencil className="size-4" /></Button> },
  ];

  return (
    <>
      <div className="mb-3 flex justify-end"><Button onClick={openCreate}><Plus /> New Banner</Button></div>
      <DataTable
        columns={columns} data={rows} loading={query.isLoading}
        error={query.isError ? "Failed to load." : null} onRetry={() => query.refetch()}
        emptyMessage="No banners yet. Create one and send it for approval."
      />

      <Dialog open={open} onOpenChange={setOpen}>
        <DialogContent className="max-h-[90vh] max-w-xl overflow-y-auto">
          <DialogHeader>
            <DialogTitle className="flex items-center gap-2">
              {editing ? "Edit Banner" : "New Banner"}
              {editing && <Badge variant={STATE_VARIANT[editing.state] ?? "secondary"}>{titleize(editing.state)}</Badge>}
            </DialogTitle>
          </DialogHeader>

          {!canEdit && (
            <p className="rounded-md border border-amber-500/40 bg-amber-500/10 p-2 text-xs text-amber-700 dark:text-amber-400">
              This banner is {titleize(editing!.state).toLowerCase()} and can no longer be edited here.
              Ask a super-admin to pause it if you need changes.
            </p>
          )}

          <div className="space-y-2">
            <Label>
              Banner image
              {spec && <span className="ml-1 font-normal text-muted-foreground">— {spec.aspect}, {spec.master.width}×{spec.master.height}px</span>}
            </Label>
            <div className="relative w-full overflow-hidden rounded-md border bg-muted" style={{ aspectRatio: String(spec?.ratio ?? 1.6) }}>
              <BannerPreviewImage staged={stagedFile} cropRect={cropRect} current={form.image?.medium ?? null} />
            </div>
            <div className="flex flex-wrap items-center gap-2">
              <label className="inline-flex">
                <input
                  type="file" accept="image/png,image/jpeg,image/webp" className="hidden" disabled={!canEdit}
                  onChange={(e) => { const f = e.target.files?.[0] ?? null; setStagedFile(f); setCropRect(null); if (f) setCropping(true); }}
                />
                <span className="inline-flex cursor-pointer items-center gap-1.5 rounded-md border px-3 py-1.5 text-sm hover:bg-accent">
                  <Upload className="size-3.5" /> {stagedFile ? stagedFile.name : "Choose image…"}
                </span>
              </label>
              {stagedFile && (
                <Button type="button" variant="outline" size="sm" onClick={() => setCropping(true)}>
                  <Crop className="size-3.5" /> {cropRect ? "Adjust crop" : "Crop"}
                </Button>
              )}
            </div>
            {spec && <p className="text-xs text-muted-foreground">{spec.note}</p>}
          </div>

          <div className="grid grid-cols-2 gap-3">
            <F label="Placement">
              <Select value={form.placement ?? "top"} onValueChange={(v) => setForm({ ...form, placement: v })} disabled={!canEdit}>
                <SelectTrigger><SelectValue /></SelectTrigger>
                <SelectContent>{specs.map((s) => <SelectItem key={s.placement} value={s.placement}>{s.label}</SelectItem>)}</SelectContent>
              </Select>
            </F>
            <F label="CTA button text">
              <Input value={form.ctaText ?? ""} maxLength={40} disabled={!canEdit}
                     placeholder="Shop now" onChange={(e) => setForm({ ...form, ctaText: e.target.value })} />
            </F>
            <div className="col-span-2">
              <F label="Title"><Input value={form.title ?? ""} disabled={!canEdit} onChange={(e) => setForm({ ...form, title: e.target.value })} /></F>
            </div>
            <div className="col-span-2">
              <F label="Subtitle"><Textarea rows={2} value={form.subtitle ?? ""} disabled={!canEdit} onChange={(e) => setForm({ ...form, subtitle: e.target.value })} /></F>
            </div>

            <F label="Tap action">
              <Select value={form.action ?? "none"} onValueChange={(v) => setForm({ ...form, action: v, payload: {} })} disabled={!canEdit}>
                <SelectTrigger><SelectValue /></SelectTrigger>
                <SelectContent>{ACTIONS.map((a) => <SelectItem key={a.value} value={a.value}>{a.label}</SelectItem>)}</SelectContent>
              </Select>
            </F>
            {actionDef?.field ? (
              <F label={actionDef.field.label}>
                <Input
                  type={actionDef.field.type} disabled={!canEdit}
                  value={String((form.payload ?? {})[actionDef.field.key] ?? "")}
                  onChange={(e) => setForm({ ...form, payload: { [actionDef.field!.key]: actionDef.field!.type === "number" ? Number(e.target.value) : e.target.value } })}
                />
              </F>
            ) : <div />}

            <F label="Start"><Input type="datetime-local" disabled={!canEdit} value={(form.validFrom ?? "").slice(0, 16)} onChange={(e) => setForm({ ...form, validFrom: e.target.value })} /></F>
            <F label="End"><Input type="datetime-local" disabled={!canEdit} value={(form.validTo ?? "").slice(0, 16)} onChange={(e) => setForm({ ...form, validTo: e.target.value })} /></F>
          </div>

          <DialogFooter className="gap-2">
            {editing && editing.state === "draft" && (
              <Button variant="outline" className="mr-auto" disabled={busy} onClick={sendForApproval}>
                <Send className="size-4" /> Send for approval
              </Button>
            )}
            <Button variant="outline" onClick={() => setOpen(false)} disabled={busy}>Close</Button>
            <Button onClick={submit} disabled={busy || !canEdit || !form.title}>
              {busy && <Loader2 className="size-4 animate-spin" />} Save draft
            </Button>
          </DialogFooter>
        </DialogContent>
      </Dialog>

      {cropping && stagedFile && spec && (
        <BannerCropDialog
          file={stagedFile}
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
            if (resized) setStagedFile(resized);
            setCropRect(r);
            setCropping(false);
          }}
        />
      )}
    </>
  );
}

/** Preview that renders exactly the region the server will crop. */
function BannerPreviewImage({ staged, cropRect, current }: {
  staged: File | null; cropRect: CropRect | null; current: string | null;
}) {
  const preview = React.useMemo(() => (staged ? URL.createObjectURL(staged) : null), [staged]);
  React.useEffect(() => () => { if (preview) URL.revokeObjectURL(preview); }, [preview]);
  const src = preview ?? (current ? api.assetUrl(current) : null);
  if (!src) {
    return (
      <div className="flex h-full w-full flex-col items-center justify-center gap-1 text-muted-foreground">
        <ImageIcon className="size-6" /><span className="text-xs">No image</span>
      </div>
    );
  }
  const style: React.CSSProperties = cropRect && cropRect.w && cropRect.h
    ? {
        position: "absolute",
        width: `${100 / cropRect.w}%`,
        height: `${100 / cropRect.h}%`,
        left: `${(-cropRect.x / cropRect.w) * 100}%`,
        top: `${(-cropRect.y / cropRect.h) * 100}%`,
        maxWidth: "none",
      }
    : { objectFit: "cover", width: "100%", height: "100%" };
  // eslint-disable-next-line @next/next/no-img-element
  return <img src={src} alt="banner preview" style={style} />;
}

function F({ label, children }: { label: string; children: React.ReactNode }) {
  return (
    <div className="space-y-1.5">
      <Label className="text-xs text-muted-foreground">{label}</Label>
      {children}
    </div>
  );
}
