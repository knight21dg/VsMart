"use client";

import * as React from "react";
import { keepPreviousData, useQuery, useQueryClient } from "@tanstack/react-query";
import { type ColumnDef } from "@tanstack/react-table";
import { Check, Loader2, Search, ShieldAlert, X } from "lucide-react";
import { toast } from "sonner";
import { api } from "@/lib/api/client";
import { ApiError, type PageMeta } from "@/lib/types";
import { DataTable } from "@/components/data-table";
import { StatusBadge } from "@/components/status-badge";
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
import { inr, titleize } from "@/lib/utils";

export interface CreditApplication {
  id: string;
  userId: string;
  customerName: string;
  customerPhone: string;
  kycStatus: string;
  creditEnabled: boolean;
  status: string;
  occupation: string;
  monthlyIncome: string | number | null;
  familyMembers: number | null;
  houseType: string;
  ownership: string;
  requestedLimit: string | number | null;
  bureauScoreAtSubmit: number | null;
  kycStatusAtSubmit: string;
  approvedLimit: string | number | null;
  rejectionReason: string;
  decisionNote: string;
  decidedById: string | null;
  decidedAt: string | null;
  submittedAt: string | null;
}

interface ApplicationDetail extends CreditApplication {
  account: { creditLimit: number; outstanding: number; status: string } | null;
  bureau: { score: number; band: string; pulledAt: string } | null;
}

const STATUS_FILTERS = [
  { value: "pending", label: "Awaiting decision" },
  { value: "approved", label: "Approved" },
  { value: "rejected", label: "Rejected" },
  { value: "withdrawn", label: "Withdrawn" },
  { value: "", label: "All" },
];

const n = (v: string | number | null | undefined) =>
  v == null || v === "" ? null : Number(v);

export function CreditApplicationsTab() {
  const qc = useQueryClient();
  const [status, setStatus] = React.useState("pending");
  const [search, setSearch] = React.useState("");
  const [q, setQ] = React.useState("");
  const [page, setPage] = React.useState(1);
  const [openId, setOpenId] = React.useState<string | null>(null);

  // Debounce the search box. Resetting the page happens in the same callback:
  // a narrower result set would otherwise leave the user on a now-empty page
  // that reads as "no results".
  React.useEffect(() => {
    const t = setTimeout(() => {
      setQ(search.trim());
      setPage(1);
    }, 300);
    return () => clearTimeout(t);
  }, [search]);

  const query = useQuery({
    queryKey: ["admin", "credit", "applications", status, q, page],
    queryFn: () =>
      api.getPaged<CreditApplication>("/admin/credit/applications", {
        status: status || undefined,
        search: q || undefined,
        page,
      }),
    placeholderData: keepPreviousData,
  });

  const columns: ColumnDef<CreditApplication, unknown>[] = [
    {
      accessorKey: "customerName", header: "Customer",
      cell: ({ row }) => (
        <div className="flex flex-col">
          <span className="font-medium">{row.original.customerName || "—"}</span>
          <span className="text-xs text-muted-foreground">{row.original.customerPhone}</span>
        </div>
      ),
    },
    {
      accessorKey: "requestedLimit", header: "Requested",
      cell: ({ row }) => {
        const v = n(row.original.requestedLimit);
        return <span className="tabular-nums">{v == null ? "—" : inr(v)}</span>;
      },
    },
    {
      accessorKey: "monthlyIncome", header: "Monthly income",
      cell: ({ row }) => {
        const v = n(row.original.monthlyIncome);
        return <span className="tabular-nums">{v == null ? "—" : inr(v)}</span>;
      },
    },
    {
      accessorKey: "bureauScoreAtSubmit", header: "CIBIL",
      cell: ({ row }) => (
        <span className="tabular-nums">{row.original.bureauScoreAtSubmit ?? "—"}</span>
      ),
    },
    {
      accessorKey: "kycStatus", header: "KYC",
      cell: ({ row }) => <StatusBadge status={row.original.kycStatus} />,
    },
    {
      accessorKey: "status", header: "Status",
      cell: ({ row }) => (
        <div className="flex flex-col gap-0.5">
          <StatusBadge status={row.original.status} />
          {row.original.approvedLimit != null && (
            <span className="text-xs text-muted-foreground">
              {inr(Number(row.original.approvedLimit))} granted
            </span>
          )}
        </div>
      ),
    },
    {
      id: "a", header: "",
      cell: ({ row }) => (
        <Button size="sm" variant="outline" onClick={() => setOpenId(row.original.id)}>
          Review
        </Button>
      ),
    },
  ];

  return (
    <>
      <div className="mb-3 flex flex-wrap items-center gap-2">
        <div className="relative min-w-[240px] flex-1">
          <Search className="pointer-events-none absolute left-3 top-1/2 size-4 -translate-y-1/2 text-muted-foreground" />
          <Input
            value={search} onChange={(e) => setSearch(e.target.value)}
            placeholder="Search by name or phone…" className="pl-9"
          />
        </div>
        <Select
          value={status || "__all__"}
          onValueChange={(v) => { setStatus(v === "__all__" ? "" : v); setPage(1); }}
        >
          <SelectTrigger className="w-[190px]"><SelectValue /></SelectTrigger>
          <SelectContent>
            {STATUS_FILTERS.map((s) => (
              <SelectItem key={s.value || "__all__"} value={s.value || "__all__"}>
                {s.label}
              </SelectItem>
            ))}
          </SelectContent>
        </Select>
      </div>

      <DataTable
        columns={columns}
        data={query.data?.rows ?? []}
        loading={query.isLoading}
        error={query.isError ? "Failed to load applications." : null}
        onRetry={() => query.refetch()}
        emptyMessage={
          status === "pending"
            ? "Nothing awaiting a decision."
            : "No applications match this filter."
        }
        pageMeta={query.data?.meta as PageMeta | undefined}
        page={page}
        onPageChange={setPage}
      />

      {openId && (
        <ReviewDialog
          applicationId={openId}
          onClose={() => setOpenId(null)}
          onDecided={() => {
            qc.invalidateQueries({ queryKey: ["admin", "credit", "applications"] });
            qc.invalidateQueries({ queryKey: ["admin", "crm", "customers"] });
            setOpenId(null);
          }}
        />
      )}
    </>
  );
}

/**
 * The decision surface. Shows everything a reviewer needs in one place —
 * declared finances, the CIBIL score captured at submission, the live account —
 * so approving a limit isn't done blind.
 */
function ReviewDialog({ applicationId, onClose, onDecided }: {
  applicationId: string;
  onClose: () => void;
  onDecided: () => void;
}) {
  const detail = useQuery({
    queryKey: ["admin", "credit", "application", applicationId],
    queryFn: () => api.get<ApplicationDetail>(`/admin/credit/applications/${applicationId}`),
  });

  return (
    <Dialog open onOpenChange={(o) => !o && onClose()}>
      <DialogContent className="max-h-[90vh] max-w-2xl overflow-y-auto">
        {detail.isLoading && (
          <>
            <DialogHeader><DialogTitle>Credit application</DialogTitle></DialogHeader>
            <div className="grid place-items-center py-10">
              <Loader2 className="size-5 animate-spin text-muted-foreground" />
            </div>
          </>
        )}
        {detail.isError && (
          <>
            <DialogHeader><DialogTitle>Credit application</DialogTitle></DialogHeader>
            <p className="py-6 text-center text-sm text-destructive">
              Failed to load this application.
            </p>
            <DialogFooter><Button variant="outline" onClick={onClose}>Close</Button></DialogFooter>
          </>
        )}
        {/* Body mounts only once the data is in, so form state can be seeded
            straight from props instead of synced in an effect. */}
        {detail.data && (
          <ReviewBody app={detail.data} onClose={onClose} onDecided={onDecided} />
        )}
      </DialogContent>
    </Dialog>
  );
}

function ReviewBody({ app, onClose, onDecided }: {
  app: ApplicationDetail;
  onClose: () => void;
  onDecided: () => void;
}) {
  const applicationId = app.id;
  // Seeded with what the customer asked for — the common case is approving that
  // amount, and it anchors the reviewer to a real number.
  const [limit, setLimit] = React.useState(
    app.requestedLimit != null ? String(Number(app.requestedLimit)) : ""
  );
  const [note, setNote] = React.useState("");
  const [reason, setReason] = React.useState("");
  const [busy, setBusy] = React.useState(false);
  const [mode, setMode] = React.useState<"idle" | "reject">("idle");

  const decided = !["submitted", "under_review"].includes(app.status);

  async function decide(decision: "approve" | "reject") {
    setBusy(true);
    try {
      await api.post(`/admin/credit/applications/${applicationId}/decision`,
        decision === "approve"
          ? { decision, approvedLimit: Number(limit), note }
          : { decision, reason, note });
      toast.success(decision === "approve" ? "Credit approved." : "Application rejected.");
      onDecided();
    } catch (e) {
      toast.error(e instanceof ApiError ? e.message : "Could not save the decision.");
    } finally {
      setBusy(false);
    }
  }

  return (
    <>
      <DialogHeader>
        <DialogTitle className="flex items-center gap-2">
          Credit application
          <StatusBadge status={app.status} />
        </DialogTitle>
      </DialogHeader>

      <div className="space-y-4">
            {app.kycStatus !== "verified" && (
              <div className="flex items-start gap-2 rounded-md border border-amber-500/40 bg-amber-500/10 p-2.5 text-xs text-amber-700 dark:text-amber-400">
                <ShieldAlert className="mt-0.5 size-4 shrink-0" />
                <span>
                  This customer&apos;s KYC is <strong>{titleize(app.kycStatus)}</strong>. Identity
                  should be verified before a credit line is granted.
                </span>
              </div>
            )}

            <Section title="Customer">
              <Row label="Name" value={app.customerName || "—"} />
              <Row label="Phone" value={app.customerPhone} />
              <Row label="KYC" value={titleize(app.kycStatus)} />
              <Row label="Credit currently enabled" value={app.creditEnabled ? "Yes" : "No"} />
            </Section>

            <Section title="Declared by the customer">
              <Row label="Occupation" value={app.occupation || "—"} />
              <Row label="Monthly income" value={n(app.monthlyIncome) == null ? "—" : inr(Number(app.monthlyIncome))} />
              <Row label="Family members" value={app.familyMembers?.toString() ?? "—"} />
              <Row label="House" value={[titleize(app.houseType), titleize(app.ownership)].filter(Boolean).join(" · ") || "—"} />
              <Row label="Requested limit" value={n(app.requestedLimit) == null ? "—" : inr(Number(app.requestedLimit))} />
            </Section>

            <Section title="Underwriting context">
              <Row
                label="CIBIL at submission"
                value={app.bureauScoreAtSubmit ? String(app.bureauScoreAtSubmit) : "Not pulled"}
              />
              <Row
                label="CIBIL now"
                value={app.bureau ? `${app.bureau.score} (${app.bureau.band})` : "No report"}
              />
              <Row
                label="Existing account"
                value={app.account
                  ? `${inr(app.account.creditLimit)} limit · ${inr(app.account.outstanding)} outstanding · ${titleize(app.account.status)}`
                  : "None"}
              />
            </Section>

            {decided ? (
              <Section title="Decision">
                <Row label="Outcome" value={titleize(app.status)} />
                {app.approvedLimit != null && (
                  <Row label="Approved limit" value={inr(Number(app.approvedLimit))} />
                )}
                {app.rejectionReason && <Row label="Reason given" value={app.rejectionReason} />}
                {app.decisionNote && <Row label="Internal note" value={app.decisionNote} />}
              </Section>
            ) : mode === "reject" ? (
              <div className="space-y-3 rounded-md border p-3">
                <div className="space-y-1.5">
                  <Label className="text-xs text-muted-foreground">
                    Reason (shown to the customer)
                  </Label>
                  <Textarea
                    rows={2} value={reason} maxLength={300}
                    onChange={(e) => setReason(e.target.value)}
                    placeholder="e.g. Declared income does not support the requested limit."
                  />
                </div>
                <div className="space-y-1.5">
                  <Label className="text-xs text-muted-foreground">Internal note (optional)</Label>
                  <Textarea rows={2} value={note} maxLength={300}
                            onChange={(e) => setNote(e.target.value)} />
                </div>
              </div>
            ) : (
              <div className="space-y-3 rounded-md border p-3">
                <div className="space-y-1.5">
                  <Label className="text-xs text-muted-foreground">
                    Approved limit (₹) — this is what the customer can actually spend
                  </Label>
                  <Input
                    type="number" min={1} value={limit}
                    onChange={(e) => setLimit(e.target.value)}
                  />
                  {n(app.requestedLimit) != null && Number(limit) !== Number(app.requestedLimit) && (
                    <p className="text-xs text-muted-foreground">
                      Customer requested {inr(Number(app.requestedLimit))}.
                    </p>
                  )}
                </div>
                <div className="space-y-1.5">
                  <Label className="text-xs text-muted-foreground">Internal note (optional)</Label>
                  <Textarea rows={2} value={note} maxLength={300}
                            onChange={(e) => setNote(e.target.value)}
                            placeholder="Not shown to the customer." />
                </div>
              </div>
            )}
      </div>

      <DialogFooter className="gap-2">
          {decided ? (
            <Button variant="outline" onClick={onClose}>Close</Button>
          ) : mode === "reject" ? (
            <>
              <Button variant="outline" onClick={() => setMode("idle")} disabled={busy}>Back</Button>
              <Button
                variant="destructive" disabled={busy || !reason.trim()}
                onClick={() => decide("reject")}
              >
                {busy && <Loader2 className="size-4 animate-spin" />} Confirm rejection
              </Button>
            </>
          ) : (
            <>
              <Button
                variant="ghost" className="mr-auto text-destructive hover:text-destructive"
                disabled={busy} onClick={() => setMode("reject")}
              >
                <X className="size-4" /> Reject
              </Button>
              <Button variant="outline" onClick={onClose} disabled={busy}>Cancel</Button>
              <Button
                disabled={busy || !(Number(limit) > 0)}
                onClick={() => decide("approve")}
              >
                {busy ? <Loader2 className="size-4 animate-spin" /> : <Check className="size-4" />}
                Approve {Number(limit) > 0 ? inr(Number(limit)) : ""}
              </Button>
            </>
          )}
      </DialogFooter>
    </>
  );
}

function Section({ title, children }: { title: string; children: React.ReactNode }) {
  return (
    <div className="rounded-md border">
      <div className="border-b bg-muted/40 px-3 py-2">
        <span className="text-xs font-medium uppercase tracking-wide text-muted-foreground">
          {title}
        </span>
      </div>
      <div className="divide-y">{children}</div>
    </div>
  );
}

function Row({ label, value }: { label: string; value: string }) {
  return (
    <div className="flex items-start justify-between gap-4 px-3 py-2 text-sm">
      <span className="text-muted-foreground">{label}</span>
      <span className="text-right font-medium">{value}</span>
    </div>
  );
}

/** Small badge flagging a non-empty queue on the tab. */
export function PendingApplicationsBadge() {
  const query = useQuery({
    queryKey: ["admin", "credit", "applications", "pendingCount"],
    queryFn: () =>
      api.getPaged<CreditApplication>("/admin/credit/applications", { status: "pending" }),
  });
  // Read the total from pagination meta, not rows.length — the list is paged at
  // 20, so a backlog of 50 would otherwise always read "20 awaiting".
  const meta = query.data?.meta as PageMeta | undefined;
  const count = meta?.total ?? query.data?.rows.length ?? 0;
  if (!count) return null;
  return <Badge variant="warning">{count} awaiting</Badge>;
}
