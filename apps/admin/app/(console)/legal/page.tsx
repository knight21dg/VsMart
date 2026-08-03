"use client";

import * as React from "react";
import { useQuery } from "@tanstack/react-query";
import { Loader2, Lock, Plus } from "lucide-react";
import { api } from "@/lib/api/client";
import { useApiMutation } from "@/lib/api/hooks";
import { useAuth } from "@/lib/auth/auth-context";
import { PageHeader } from "@/components/page-header";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import { Badge } from "@/components/ui/badge";
import { Switch } from "@/components/ui/switch";
import {
  Dialog,
  DialogContent,
  DialogFooter,
  DialogHeader,
  DialogTitle,
} from "@/components/ui/dialog";
import { LoadingState, ErrorState, EmptyState } from "@/components/states";
import { cn, fmtDate } from "@/lib/utils";

interface LegalPage {
  id: string;
  slug: string;
  title: string;
  body: string;
  type: string;
  is_active: boolean;
  sort_order: number;
  updated_at?: string;
}

interface PagesResp {
  pages: LegalPage[];
}

export default function LegalPage() {
  const { user } = useAuth();
  const canWrite = user?.role === "superadmin" || user?.role === "admin";

  const [activeSlug, setActiveSlug] = React.useState<string | null>(null);
  const [draft, setDraft] = React.useState<{ title: string; body: string; is_active: boolean }>({
    title: "",
    body: "",
    is_active: true,
  });
  const [newOpen, setNewOpen] = React.useState(false);

  const query = useQuery({
    queryKey: ["admin", "pages"],
    queryFn: () => api.get<PagesResp>("/admin/pages"),
  });
  const pages = React.useMemo(
    () => [...(query.data?.pages ?? [])].sort((a, b) => a.sort_order - b.sort_order),
    [query.data]
  );

  // Select the first page once data arrives (or keep the current one if still present).
  React.useEffect(() => {
    if (pages.length === 0) return;
    setActiveSlug((cur) => (cur && pages.some((p) => p.slug === cur) ? cur : pages[0].slug));
  }, [pages]);

  const active = pages.find((p) => p.slug === activeSlug) ?? null;

  // Load the selected page into the editable draft.
  React.useEffect(() => {
    if (active) setDraft({ title: active.title, body: active.body, is_active: active.is_active });
  }, [active?.slug, active?.updated_at]); // eslint-disable-line react-hooks/exhaustive-deps

  const save = useApiMutation(
    (vars: { slug: string; body: Partial<LegalPage> }) =>
      api.patch<LegalPage>(`/admin/pages/${vars.slug}`, vars.body),
    { invalidate: [["admin", "pages"]], successMessage: "Page saved." }
  );

  const create = useApiMutation((body: Partial<LegalPage>) => api.post<LegalPage>("/admin/pages", body), {
    invalidate: [["admin", "pages"]],
    successMessage: "Page created.",
    onDone: (page) => {
      setNewOpen(false);
      setActiveSlug(page.slug);
    },
  });

  const dirty =
    !!active &&
    (draft.title !== active.title ||
      draft.body !== active.body ||
      draft.is_active !== active.is_active);

  function submit() {
    if (!active) return;
    save.mutate({
      slug: active.slug,
      body: { title: draft.title, body: draft.body, is_active: draft.is_active },
    });
  }

  return (
    <>
      <PageHeader
        title="Legal / CMS"
        description="Edit the public legal & content pages — privacy, terms, about, contact and more."
        actions={
          canWrite ? (
            <Button variant="outline" onClick={() => setNewOpen(true)}>
              <Plus className="size-4" /> New page
            </Button>
          ) : (
            <span className="flex items-center gap-1.5 text-xs text-muted-foreground">
              <Lock className="size-3.5" /> Read only
            </span>
          )
        }
      />

      {query.isLoading ? (
        <LoadingState />
      ) : query.isError ? (
        <ErrorState message="Couldn't load content pages." onRetry={() => query.refetch()} />
      ) : pages.length === 0 ? (
        <EmptyState title="No content pages yet" description="Create your first page to get started." />
      ) : (
        <div className="grid gap-4 lg:grid-cols-[260px_1fr]">
          {/* Page list */}
          <Card className="h-fit">
            <CardHeader>
              <CardTitle className="text-sm">Pages</CardTitle>
            </CardHeader>
            <CardContent className="space-y-1">
              {pages.map((p) => (
                <button
                  key={p.slug}
                  onClick={() => setActiveSlug(p.slug)}
                  className={cn(
                    "flex w-full items-center justify-between gap-2 rounded-lg px-3 py-2 text-left text-sm transition-colors",
                    p.slug === activeSlug ? "bg-primary/10 text-primary" : "hover:bg-accent"
                  )}
                >
                  <span className="min-w-0">
                    <span className="block truncate font-medium">{p.title}</span>
                    <span className="block truncate font-mono text-[11px] text-muted-foreground">/{p.slug}</span>
                  </span>
                  {!p.is_active && (
                    <Badge variant="secondary" className="shrink-0">
                      Hidden
                    </Badge>
                  )}
                </button>
              ))}
            </CardContent>
          </Card>

          {/* Editor */}
          {active ? (
            <Card>
              <CardHeader className="flex-row items-center justify-between gap-3 space-y-0">
                <div className="min-w-0 space-y-0.5">
                  <CardTitle className="truncate">{active.title}</CardTitle>
                  <p className="font-mono text-xs text-muted-foreground">/{active.slug}</p>
                </div>
                <Badge variant="outline" className="shrink-0 capitalize">
                  {active.type}
                </Badge>
              </CardHeader>
              <CardContent className="space-y-4">
                <div className="space-y-1.5">
                  <Label htmlFor="legal-title">Title</Label>
                  <Input
                    id="legal-title"
                    value={draft.title}
                    onChange={(e) => setDraft((d) => ({ ...d, title: e.target.value }))}
                    disabled={!canWrite}
                  />
                </div>

                <div className="space-y-1.5">
                  <Label htmlFor="legal-body">Body (HTML)</Label>
                  <textarea
                    id="legal-body"
                    value={draft.body}
                    onChange={(e) => setDraft((d) => ({ ...d, body: e.target.value }))}
                    disabled={!canWrite}
                    spellCheck={false}
                    rows={18}
                    className="flex w-full rounded-md border border-input bg-card px-3 py-2 font-mono text-xs leading-relaxed shadow-sm focus:outline-none focus:ring-2 focus:ring-ring disabled:cursor-not-allowed disabled:opacity-60"
                  />
                  <p className="text-xs text-muted-foreground">
                    Raw HTML — rendered as-is on the public page.
                  </p>
                </div>

                <div className="flex items-center justify-between rounded-lg border p-3">
                  <div className="space-y-0.5">
                    <Label htmlFor="legal-active">Active</Label>
                    <p className="text-xs text-muted-foreground">When off, the page is hidden from the public site.</p>
                  </div>
                  <Switch
                    id="legal-active"
                    checked={draft.is_active}
                    onCheckedChange={(v) => setDraft((d) => ({ ...d, is_active: v }))}
                    disabled={!canWrite}
                  />
                </div>

                <div className="flex items-center justify-between gap-3 border-t pt-4">
                  <p className="text-xs text-muted-foreground">
                    {active.updated_at ? `Last updated ${fmtDate(active.updated_at, true)}` : "Never updated"}
                  </p>
                  {canWrite && (
                    <Button onClick={submit} disabled={!dirty || save.isPending}>
                      {save.isPending && <Loader2 className="size-4 animate-spin" />}
                      Save
                    </Button>
                  )}
                </div>
              </CardContent>
            </Card>
          ) : (
            <Card>
              <CardContent className="py-16">
                <EmptyState title="Select a page" description="Pick a page from the list to edit it." />
              </CardContent>
            </Card>
          )}
        </div>
      )}

      <NewPageDialog
        open={newOpen}
        onOpenChange={setNewOpen}
        pending={create.isPending}
        onCreate={(body) => create.mutate(body)}
      />
    </>
  );
}

function NewPageDialog({
  open,
  onOpenChange,
  pending,
  onCreate,
}: {
  open: boolean;
  onOpenChange: (v: boolean) => void;
  pending: boolean;
  onCreate: (body: { slug: string; title: string; body: string; type: string; is_active: boolean }) => void;
}) {
  const [slug, setSlug] = React.useState("");
  const [title, setTitle] = React.useState("");
  const [body, setBody] = React.useState("");

  React.useEffect(() => {
    if (open) {
      setSlug("");
      setTitle("");
      setBody("");
    }
  }, [open]);

  const slugClean = slug
    .trim()
    .toLowerCase()
    .replace(/[^a-z0-9]+/g, "-")
    .replace(/^-+|-+$/g, "");
  const valid = slugClean.length > 0 && title.trim().length > 0;

  return (
    <Dialog open={open} onOpenChange={onOpenChange}>
      <DialogContent>
        <DialogHeader>
          <DialogTitle>New content page</DialogTitle>
        </DialogHeader>
        <div className="space-y-4">
          <div className="space-y-1.5">
            <Label htmlFor="new-slug">Slug</Label>
            <Input
              id="new-slug"
              value={slug}
              onChange={(e) => setSlug(e.target.value)}
              placeholder="e.g. refund-policy"
            />
            {slug && (
              <p className="font-mono text-xs text-muted-foreground">/{slugClean || "…"}</p>
            )}
          </div>
          <div className="space-y-1.5">
            <Label htmlFor="new-title">Title</Label>
            <Input
              id="new-title"
              value={title}
              onChange={(e) => setTitle(e.target.value)}
              placeholder="Refund Policy"
            />
          </div>
          <div className="space-y-1.5">
            <Label htmlFor="new-body">Body (HTML)</Label>
            <textarea
              id="new-body"
              value={body}
              onChange={(e) => setBody(e.target.value)}
              spellCheck={false}
              rows={8}
              placeholder="<h1>Refund Policy</h1>…"
              className="flex w-full rounded-md border border-input bg-card px-3 py-2 font-mono text-xs leading-relaxed shadow-sm focus:outline-none focus:ring-2 focus:ring-ring"
            />
          </div>
        </div>
        <DialogFooter>
          <Button variant="outline" onClick={() => onOpenChange(false)} disabled={pending}>
            Cancel
          </Button>
          <Button
            onClick={() =>
              onCreate({ slug: slugClean, title: title.trim(), body, type: "legal", is_active: true })
            }
            disabled={!valid || pending}
          >
            {pending && <Loader2 className="size-4 animate-spin" />}
            Create page
          </Button>
        </DialogFooter>
      </DialogContent>
    </Dialog>
  );
}
