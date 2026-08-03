"use client";

import * as React from "react";
import { keepPreviousData, useQuery, useQueryClient } from "@tanstack/react-query";
import { type ColumnDef } from "@tanstack/react-table";
import { BadgeCheck, Check, Loader2, Search, Star, X } from "lucide-react";
import { toast } from "sonner";
import { api } from "@/lib/api/client";
import { ApiError, type PageMeta } from "@/lib/types";
import { PageHeader } from "@/components/page-header";
import { DataTable } from "@/components/data-table";
import { StatusBadge } from "@/components/status-badge";
import { ProductLink } from "@/components/product-link";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import { Badge } from "@/components/ui/badge";
import { Textarea } from "@/components/ui/textarea";
import {
  Dialog, DialogContent, DialogFooter, DialogHeader, DialogTitle,
} from "@/components/ui/dialog";
import {
  Select, SelectContent, SelectItem, SelectTrigger, SelectValue,
} from "@/components/ui/select";

interface Review {
  id: string;
  productId: string;
  productName: string;
  authorName: string;
  authorPhone: string;
  rating: number;
  title: string;
  body: string;
  status: string;
  isVerifiedPurchase: boolean;
  orderCode: string | null;
  moderationReason: string;
  moderatedByName: string | null;
  moderatedAt: string | null;
  createdAt: string;
}

const FILTERS = [
  { value: "pending", label: "Awaiting moderation" },
  { value: "approved", label: "Approved" },
  { value: "rejected", label: "Rejected" },
  { value: "all", label: "All" },
];

function Stars({ n }: { n: number }) {
  return (
    <span className="inline-flex items-center gap-0.5" aria-label={`${n} out of 5`}>
      {[1, 2, 3, 4, 5].map((i) => (
        <Star
          key={i}
          className={`size-3.5 ${i <= n ? "fill-[var(--color-warning)] text-[var(--color-warning)]" : "text-muted-foreground/40"}`}
        />
      ))}
    </span>
  );
}

export default function ReviewsPage() {
  const qc = useQueryClient();
  const [status, setStatus] = React.useState("pending");
  const [search, setSearch] = React.useState("");
  const [q, setQ] = React.useState("");
  const [page, setPage] = React.useState(1);
  const [open, setOpen] = React.useState<Review | null>(null);

  React.useEffect(() => {
    const t = setTimeout(() => { setQ(search.trim()); setPage(1); }, 300);
    return () => clearTimeout(t);
  }, [search]);

  const query = useQuery({
    queryKey: ["admin", "reviews", status, q, page],
    queryFn: () => api.getPaged<Review>("/admin/reviews", {
      status, search: q || undefined, page,
    }),
    placeholderData: keepPreviousData,
  });

  const columns: ColumnDef<Review, unknown>[] = [
    {
      accessorKey: "productName", header: "Product",
      cell: ({ row }) => <ProductLink id={row.original.productId} name={row.original.productName} className="font-medium" />,
    },
    { id: "rating", header: "Rating", cell: ({ row }) => <Stars n={row.original.rating} /> },
    {
      id: "review", header: "Review",
      cell: ({ row }) => (
        <div className="max-w-[320px]">
          {row.original.title && <p className="truncate font-medium">{row.original.title}</p>}
          <p className="truncate text-xs text-muted-foreground">{row.original.body || "—"}</p>
        </div>
      ),
    },
    {
      accessorKey: "authorName", header: "Author",
      cell: ({ row }) => (
        <div className="flex flex-col">
          <span>{row.original.authorName || "—"}</span>
          {row.original.isVerifiedPurchase ? (
            <span className="inline-flex items-center gap-1 text-xs text-[var(--color-success)]">
              <BadgeCheck className="size-3" /> Verified buyer
            </span>
          ) : (
            <span className="text-xs text-muted-foreground">No purchase found</span>
          )}
        </div>
      ),
    },
    { accessorKey: "status", header: "Status", cell: ({ row }) => <StatusBadge status={row.original.status} /> },
    {
      id: "a", header: "",
      cell: ({ row }) => (
        <Button size="sm" variant="outline" onClick={() => setOpen(row.original)}>
          Review
        </Button>
      ),
    },
  ];

  return (
    <>
      <PageHeader
        title="Reviews"
        description="Reviews from verified buyers publish automatically. Everything else waits here."
      />

      <div className="mb-3 flex flex-wrap items-center gap-2">
        <div className="relative min-w-[240px] flex-1">
          <Search className="pointer-events-none absolute left-3 top-1/2 size-4 -translate-y-1/2 text-muted-foreground" />
          <Input
            value={search} onChange={(e) => setSearch(e.target.value)}
            placeholder="Search product, author or review text…" className="pl-9"
          />
        </div>
        <Select value={status} onValueChange={(v) => { setStatus(v); setPage(1); }}>
          <SelectTrigger className="w-[200px]"><SelectValue /></SelectTrigger>
          <SelectContent>
            {FILTERS.map((f) => <SelectItem key={f.value} value={f.value}>{f.label}</SelectItem>)}
          </SelectContent>
        </Select>
      </div>

      <DataTable
        columns={columns}
        data={query.data?.rows ?? []}
        loading={query.isLoading}
        error={query.isError ? "Failed to load reviews." : null}
        onRetry={() => query.refetch()}
        emptyMessage={status === "pending" ? "Nothing awaiting moderation." : "No reviews match this filter."}
        pageMeta={query.data?.meta as PageMeta | undefined}
        page={page}
        onPageChange={setPage}
      />

      {open && (
        <ModerateDialog
          review={open}
          onClose={() => setOpen(null)}
          onDone={() => {
            qc.invalidateQueries({ queryKey: ["admin", "reviews"] });
            setOpen(null);
          }}
        />
      )}
    </>
  );
}

function ModerateDialog({ review, onClose, onDone }: {
  review: Review; onClose: () => void; onDone: () => void;
}) {
  const [reason, setReason] = React.useState("");
  const [busy, setBusy] = React.useState(false);
  const [rejecting, setRejecting] = React.useState(false);
  const decided = review.status !== "pending";

  async function decide(decision: "approve" | "reject") {
    setBusy(true);
    try {
      await api.post(`/admin/reviews/${review.id}/moderate`, { decision, reason });
      toast.success(decision === "approve" ? "Review published." : "Review removed.");
      onDone();
    } catch (e) {
      toast.error(e instanceof ApiError ? e.message : "Could not save the decision.");
    } finally {
      setBusy(false);
    }
  }

  return (
    <Dialog open onOpenChange={(o) => !o && onClose()}>
      <DialogContent className="max-w-lg">
        <DialogHeader>
          <DialogTitle className="flex items-center gap-2">
            Review <StatusBadge status={review.status} />
          </DialogTitle>
        </DialogHeader>

        <div className="space-y-3">
          <div className="rounded-md border p-3">
            <div className="flex items-center justify-between">
              <ProductLink id={review.productId} name={review.productName} className="font-medium" />
              <Stars n={review.rating} />
            </div>
            {review.title && <p className="mt-2 font-medium">{review.title}</p>}
            <p className="mt-1 whitespace-pre-wrap text-sm text-muted-foreground">
              {review.body || "(no text)"}
            </p>
          </div>

          <div className="rounded-md border divide-y text-sm">
            <div className="flex justify-between px-3 py-2">
              <span className="text-muted-foreground">Author</span>
              <span>{review.authorName} · {review.authorPhone}</span>
            </div>
            <div className="flex justify-between px-3 py-2">
              <span className="text-muted-foreground">Verified purchase</span>
              <span>
                {review.isVerifiedPurchase
                  ? <Badge variant="success">Yes{review.orderCode ? ` · ${review.orderCode}` : ""}</Badge>
                  : <Badge variant="secondary">No matching delivered order</Badge>}
              </span>
            </div>
            {decided && review.moderatedByName && (
              <div className="flex justify-between px-3 py-2">
                <span className="text-muted-foreground">Moderated by</span>
                <span>{review.moderatedByName}</span>
              </div>
            )}
            {review.moderationReason && (
              <div className="flex justify-between gap-4 px-3 py-2">
                <span className="text-muted-foreground">Reason</span>
                <span className="text-right">{review.moderationReason}</span>
              </div>
            )}
          </div>

          {rejecting && (
            <div className="space-y-1.5">
              <Label className="text-xs text-muted-foreground">
                Reason for removal (internal)
              </Label>
              <Textarea
                rows={2} value={reason} maxLength={300}
                onChange={(e) => setReason(e.target.value)}
                placeholder="e.g. Abusive language / not about this product / spam."
              />
            </div>
          )}
        </div>

        <DialogFooter className="gap-2">
          {decided && !rejecting ? (
            <>
              <Button variant="outline" onClick={onClose}>Close</Button>
              {review.status === "approved" && (
                <Button variant="destructive" onClick={() => setRejecting(true)}>
                  <X className="size-4" /> Take down
                </Button>
              )}
              {review.status === "rejected" && (
                <Button disabled={busy} onClick={() => decide("approve")}>
                  <Check className="size-4" /> Restore
                </Button>
              )}
            </>
          ) : rejecting ? (
            <>
              <Button variant="outline" onClick={() => setRejecting(false)} disabled={busy}>Back</Button>
              <Button variant="destructive" disabled={busy || !reason.trim()}
                      onClick={() => decide("reject")}>
                {busy && <Loader2 className="size-4 animate-spin" />} Confirm removal
              </Button>
            </>
          ) : (
            <>
              <Button variant="ghost" className="mr-auto text-destructive hover:text-destructive"
                      disabled={busy} onClick={() => setRejecting(true)}>
                <X className="size-4" /> Reject
              </Button>
              <Button variant="outline" onClick={onClose} disabled={busy}>Cancel</Button>
              <Button disabled={busy} onClick={() => decide("approve")}>
                {busy ? <Loader2 className="size-4 animate-spin" /> : <Check className="size-4" />}
                Approve
              </Button>
            </>
          )}
        </DialogFooter>
      </DialogContent>
    </Dialog>
  );
}
