"use client";

import * as React from "react";
import { useQuery } from "@tanstack/react-query";
import { ChevronRight, FolderTree, Loader2, Pencil, Plus, Trash2 } from "lucide-react";
import { api } from "@/lib/api/client";
import { useApiMutation } from "@/lib/api/hooks";
import { PageHeader } from "@/components/page-header";
import { ImageUpload } from "@/components/image-upload";
import { Card } from "@/components/ui/card";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import { Switch } from "@/components/ui/switch";
import { ConfirmDialog } from "@/components/confirm-dialog";
import { LoadingState, ErrorState, EmptyState } from "@/components/states";
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from "@/components/ui/table";
import { Dialog, DialogContent, DialogFooter, DialogHeader, DialogTitle } from "@/components/ui/dialog";
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from "@/components/ui/select";

interface Category {
  id: string;
  name: string;
  slug: string;
  parentId: number | string | null;
  iconName: string;
  imageUrl: string | null;
  productCount: number;
  sortOrder: number;
  isActive: boolean;
  // Content translations — resolved per request language on the customer API.
  nameTe?: string;
  nameHi?: string;
}
type Form = Partial<Category>;

const NONE = "__none__"; // Select can't use "" as an item value.

export default function CategoriesPage() {
  const [open, setOpen] = React.useState(false);
  const [editing, setEditing] = React.useState<Category | null>(null);
  const [form, setForm] = React.useState<Form>({});
  const [slugTouched, setSlugTouched] = React.useState(false);
  const [toDelete, setToDelete] = React.useState<Category | null>(null);

  const query = useQuery({
    queryKey: ["admin", "categories"],
    queryFn: () => api.getPaged<Category>("/admin/catalog/categories"),
  });
  const rows = query.data?.rows ?? [];
  const tops = rows.filter((c) => c.parentId == null).sort((a, b) => a.sortOrder - b.sortOrder);
  const childrenOf = (id: string) =>
    rows.filter((c) => c.parentId != null && String(c.parentId) === String(id)).sort((a, b) => a.sortOrder - b.sortOrder);

  const save = useApiMutation(
    (body: Form) => (editing ? api.patch(`/admin/catalog/categories/${editing.id}`, body) : api.post("/admin/catalog/categories", body)),
    { invalidate: [["admin", "categories"]], successMessage: "Category saved.", onDone: () => setOpen(false) }
  );
  const remove = useApiMutation((id: string) => api.del(`/admin/catalog/categories/${id}`), {
    invalidate: [["admin", "categories"]],
    successMessage: "Category deleted.",
    onDone: () => setToDelete(null),
  });

  function openCreate(parentId?: string) {
    setEditing(null);
    setSlugTouched(false);
    setForm({ parentId: parentId ?? null, sortOrder: 0, isActive: true });
    setOpen(true);
  }
  function openEdit(c: Category) {
    setEditing(c);
    setSlugTouched(true);
    setForm(c);
    setOpen(true);
  }

  function setName(name: string) {
    setForm((f) => ({ ...f, name, slug: slugTouched ? f.slug : slugify(name) }));
  }

  function submit() {
    const body: Form = {
      name: form.name,
      slug: form.slug || slugify(form.name ?? ""),
      parentId: form.parentId ?? null,
      imageUrl: form.imageUrl || null,
      iconName: form.iconName,
      sortOrder: Number(form.sortOrder ?? 0),
      isActive: form.isActive ?? true,
      nameTe: form.nameTe ?? "",
      nameHi: form.nameHi ?? "",
    };
    save.mutate(body);
  }

  // Active toggle inline from the table.
  const toggle = useApiMutation(
    ({ id, isActive }: { id: string; isActive: boolean }) => api.patch(`/admin/catalog/categories/${id}`, { isActive }),
    { invalidate: [["admin", "categories"]], successMessage: "Updated." }
  );

  return (
    <>
      <PageHeader
        title="Categories"
        description="Top-level categories and their sub-categories. Sub-categories nest under a parent."
        actions={<Button onClick={() => openCreate()}><Plus /> New Category</Button>}
      />

      {query.isLoading ? (
        <LoadingState />
      ) : query.isError ? (
        <ErrorState message="Failed to load categories." onRetry={() => query.refetch()} />
      ) : tops.length === 0 ? (
        <EmptyState
          icon={<FolderTree className="size-5" />}
          title="No categories yet"
          description="Create your first top-level category to start organising the catalog."
          action={<Button onClick={() => openCreate()}><Plus /> New Category</Button>}
        />
      ) : (
        <Card className="overflow-hidden">
          <Table>
            <TableHeader>
              <TableRow>
                <TableHead>Name</TableHead>
                <TableHead>Slug</TableHead>
                <TableHead className="text-right">Products</TableHead>
                <TableHead>Status</TableHead>
                <TableHead className="text-right">Actions</TableHead>
              </TableRow>
            </TableHeader>
            <TableBody>
              {tops.map((top) => {
                const subs = childrenOf(top.id);
                return (
                  <React.Fragment key={top.id}>
                    <TableRow className="bg-muted/30">
                      <TableCell>
                        <span className="flex items-center gap-2 font-semibold">
                          <FolderTree className="size-4 text-muted-foreground" />
                          {top.name}
                        </span>
                      </TableCell>
                      <TableCell><span className="font-mono text-xs text-muted-foreground">{top.slug}</span></TableCell>
                      <TableCell className="text-right tabular-nums">{top.productCount}</TableCell>
                      <TableCell>
                        <Switch checked={top.isActive} onCheckedChange={(v) => toggle.mutate({ id: top.id, isActive: v })} />
                      </TableCell>
                      <TableCell>
                        <div className="flex justify-end gap-1">
                          <Button variant="ghost" size="icon" title="Add sub-category" onClick={() => openCreate(top.id)}><Plus className="size-4" /></Button>
                          <Button variant="ghost" size="icon" title="Edit" onClick={() => openEdit(top)}><Pencil className="size-4" /></Button>
                          <Button variant="ghost" size="icon" title="Delete" onClick={() => setToDelete(top)}><Trash2 className="size-4 text-destructive" /></Button>
                        </div>
                      </TableCell>
                    </TableRow>
                    {subs.map((sub) => (
                      <TableRow key={sub.id}>
                        <TableCell>
                          <span className="flex items-center gap-2 pl-6 text-muted-foreground">
                            <ChevronRight className="size-3.5" />
                            <span className="text-foreground">{sub.name}</span>
                          </span>
                        </TableCell>
                        <TableCell><span className="font-mono text-xs text-muted-foreground">{sub.slug}</span></TableCell>
                        <TableCell className="text-right tabular-nums">{sub.productCount}</TableCell>
                        <TableCell>
                          <Switch checked={sub.isActive} onCheckedChange={(v) => toggle.mutate({ id: sub.id, isActive: v })} />
                        </TableCell>
                        <TableCell>
                          <div className="flex justify-end gap-1">
                            <Button variant="ghost" size="icon" title="Edit" onClick={() => openEdit(sub)}><Pencil className="size-4" /></Button>
                            <Button variant="ghost" size="icon" title="Delete" onClick={() => setToDelete(sub)}><Trash2 className="size-4 text-destructive" /></Button>
                          </div>
                        </TableCell>
                      </TableRow>
                    ))}
                    {subs.length === 0 && (
                      <TableRow>
                        <TableCell colSpan={5} className="py-1.5 pl-12 text-xs text-muted-foreground">
                          No sub-categories.
                        </TableCell>
                      </TableRow>
                    )}
                  </React.Fragment>
                );
              })}
            </TableBody>
          </Table>
        </Card>
      )}

      <Dialog open={open} onOpenChange={setOpen}>
        <DialogContent className="max-w-lg">
          <DialogHeader>
            <DialogTitle className="flex items-center gap-2">
              <FolderTree className="size-4" /> {editing ? "Edit Category" : "New Category"}
            </DialogTitle>
          </DialogHeader>
          <div className="grid grid-cols-2 gap-3">
            <div className="col-span-2 space-y-1.5">
              <Label>Name</Label>
              <Input value={form.name ?? ""} onChange={(e) => setName(e.target.value)} />
            </div>
            {/* Category names are data, not UI strings — the app's language
                files can't translate them. Blank falls back to English. */}
            <div className="space-y-1.5">
              <Label>Name (తెలుగు)</Label>
              <Input value={form.nameTe ?? ""} onChange={(e) => setForm({ ...form, nameTe: e.target.value })} />
            </div>
            <div className="space-y-1.5">
              <Label>Name (हिन्दी)</Label>
              <Input value={form.nameHi ?? ""} onChange={(e) => setForm({ ...form, nameHi: e.target.value })} />
            </div>
            <div className="col-span-2 space-y-1.5">
              <Label>Slug</Label>
              <Input
                value={form.slug ?? ""}
                onChange={(e) => { setSlugTouched(true); setForm({ ...form, slug: e.target.value }); }}
                placeholder="auto-generated-from-name"
                className="font-mono text-sm"
              />
            </div>
            <div className="col-span-2 space-y-1.5">
              <Label>Parent</Label>
              <Select
                value={form.parentId != null ? String(form.parentId) : NONE}
                onValueChange={(v) => setForm({ ...form, parentId: v === NONE ? null : v })}
              >
                <SelectTrigger><SelectValue /></SelectTrigger>
                <SelectContent>
                  <SelectItem value={NONE}>— None (top-level) —</SelectItem>
                  {tops
                    .filter((t) => !editing || String(t.id) !== String(editing.id))
                    .map((t) => <SelectItem key={t.id} value={String(t.id)}>{t.name}</SelectItem>)}
                </SelectContent>
              </Select>
            </div>
            <div className="col-span-2 space-y-1.5">
              <Label>Category image</Label>
              <ImageUpload value={form.imageUrl ?? null} onChange={(url) => setForm({ ...form, imageUrl: url })} category="category" />
            </div>
            <div className="space-y-1.5">
              <Label>Sort order</Label>
              <Input type="number" value={form.sortOrder ?? 0} onChange={(e) => setForm({ ...form, sortOrder: e.target.value as unknown as number })} />
            </div>
            <div className="flex items-center justify-between rounded-md border px-3 py-2">
              <Label className="cursor-pointer">Active</Label>
              <Switch checked={form.isActive ?? true} onCheckedChange={(v) => setForm({ ...form, isActive: v })} />
            </div>
          </div>
          <DialogFooter className="gap-2">
            <Button variant="outline" onClick={() => setOpen(false)} disabled={save.isPending}>Cancel</Button>
            <Button onClick={submit} disabled={save.isPending || !form.name}>
              {save.isPending && <Loader2 className="size-4 animate-spin" />} Save
            </Button>
          </DialogFooter>
        </DialogContent>
      </Dialog>

      <ConfirmDialog
        open={!!toDelete}
        onOpenChange={(o) => !o && setToDelete(null)}
        title={`Delete ${toDelete?.name}?`}
        description={
          toDelete && toDelete.parentId == null
            ? "Top-level categories delete their sub-categories too. Products in this category may be affected."
            : "This sub-category will be removed."
        }
        confirmLabel="Delete"
        destructive
        loading={remove.isPending}
        onConfirm={() => toDelete && remove.mutate(toDelete.id)}
      />
    </>
  );
}

function slugify(s: string): string {
  return s
    .toLowerCase()
    .trim()
    .replace(/[^a-z0-9\s-]/g, "")
    .replace(/[\s_]+/g, "-")
    .replace(/-+/g, "-")
    .replace(/^-|-$/g, "");
}
