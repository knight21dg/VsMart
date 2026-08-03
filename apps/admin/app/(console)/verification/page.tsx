"use client";

import * as React from "react";
import { keepPreviousData, useQuery } from "@tanstack/react-query";
import { type ColumnDef } from "@tanstack/react-table";
import { BadgeCheck, Check, Loader2, X } from "lucide-react";
import { api } from "@/lib/api/client";
import { useApiMutation } from "@/lib/api/hooks";
import { PageHeader } from "@/components/page-header";
import { DataTable } from "@/components/data-table";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import { Badge } from "@/components/ui/badge";
import { StatCard } from "@/components/stat-card";
import { StatusBadge } from "@/components/status-badge";
import { StoreZone, StoreZoneFilter } from "@/components/store-zone";
import { AuthImage } from "@/components/auth-image";
import { Dialog, DialogContent, DialogFooter, DialogHeader, DialogTitle } from "@/components/ui/dialog";
import type { PageMeta } from "@/lib/types";
import { cn, fmtDate, titleize } from "@/lib/utils";

interface Step { step: string; status: string; note: string }
interface Doc {
  id: string;
  type: string;
  numberMasked: string;
  status: string;
  /** API-relative path to the permission-gated document image, or null. */
  fileUrl: string | null;
}
/** One gov-source verification attempt (PAN / Aadhaar / bank / DigiLocker). */
interface Verification {
  id: string;
  kind: string;
  status: string;
  verifiedName: string;
  verifiedDob: string;
  idMasked: string;
  nameMatch: boolean | null;
  provider: string;
  verifiedAt: string | null;
}
interface FieldEvidence { kind: string; photoUrl: string | null; lat: number | null; lng: number | null }
interface FieldVerification {
  taskId: string; status: string; agent: string | null;
  recommendation: string | null; note: string; submittedAt: string | null;
  evidence: FieldEvidence[];
}
interface KycApp {
  id: string;
  status: string;
  submittedAt: string | null;
  reviewedAt: string | null;
  rejectionReason: string;
  steps: Step[];
  documents: Doc[];
  verifications: Verification[];
  userId: string;
  userName: string;
  userPhone: string;
  storeName: string | null;
  zoneName: string | null;
  fieldVerification: FieldVerification | null;
}
interface QueueResp { applications: KycApp[]; summary: Record<string, number> }

const FILTERS = [
  { key: "pending", label: "Pending" },
  { key: "verified", label: "Verified" },
  { key: "rejected", label: "Rejected" },
  { key: "", label: "All" },
];

export default function VerificationPage() {
  const [status, setStatus] = React.useState("pending");
  const [store, setStore] = React.useState("");
  const [zone, setZone] = React.useState("");
  const [selected, setSelected] = React.useState<KycApp | null>(null);
  const [note, setNote] = React.useState("");
  const [page, setPage] = React.useState(1);

  // Any filter change must return to page 1 — staying on page N of a now-shorter
  // queue would show an empty table. Adjusted DURING render (React's "reset state
  // when a value changes" pattern) because this project lints
  // setState-inside-an-effect as an error.
  const filterKey = `${status}|${store}|${zone}`;
  const [prevFilterKey, setPrevFilterKey] = React.useState(filterKey);
  if (prevFilterKey !== filterKey) {
    setPrevFilterKey(filterKey);
    setPage(1);
  }

  const query = useQuery({
    queryKey: ["admin", "kyc", status, store, zone, page],
    queryFn: () => api.getWithMeta<QueueResp>("/admin/kyc/queue", { status: status || undefined, store: store || undefined, zone: zone || undefined, page }),
    placeholderData: keepPreviousData,
  });
  const summary = query.data?.data?.summary;
  const applications = query.data?.data?.applications ?? [];
  const pageMeta = query.data?.meta as PageMeta | undefined;

  // A rejection is only actionable for the customer if it says why — the backend
  // rejects a blank reason, so block it here too rather than round-tripping a 400.
  const rejectReason = note.trim();

  const decide = useApiMutation(
    (vars: { id: string; decision: "approve" | "reject"; note?: string }) =>
      api.post(`/admin/kyc/${vars.id}/decision`, { decision: vars.decision, note: vars.note }),
    {
      invalidate: [["admin", "kyc"]],
      successMessage: "Decision recorded.",
      onDone: () => setSelected(null),
    }
  );

  const columns: ColumnDef<KycApp, unknown>[] = [
    {
      id: "applicant",
      header: "Applicant",
      cell: ({ row }) => (
        <div>
          <p className="font-medium">{row.original.userName || "—"}</p>
          <p className="font-mono text-xs text-muted-foreground">{row.original.userPhone}</p>
        </div>
      ),
    },
    { id: "loc", header: "Store / Zone", cell: ({ row }) => <StoreZone store={row.original.storeName} zone={row.original.zoneName} /> },
    { accessorKey: "status", header: "Status", cell: ({ row }) => <StatusBadge status={row.original.status} /> },
    {
      id: "steps",
      header: "Steps",
      cell: ({ row }) => (
        <div className="flex flex-wrap gap-1">
          {row.original.steps.map((s) => (
            <Badge key={s.step} variant={s.status === "approved" ? "success" : s.status === "rejected" ? "destructive" : "secondary"}>
              {titleize(s.step)}
            </Badge>
          ))}
        </div>
      ),
    },
    { id: "docs", header: "Docs", cell: ({ row }) => <span className="text-muted-foreground">{row.original.documents.length}</span> },
    { accessorKey: "submittedAt", header: "Submitted", cell: ({ row }) => fmtDate(row.original.submittedAt, true) },
    {
      id: "actions",
      header: "",
      cell: ({ row }) => (
        <Button variant="outline" size="sm" onClick={() => { setSelected(row.original); setNote(""); }}>
          Review
        </Button>
      ),
    },
  ];

  return (
    <>
      <PageHeader title="Verification" description="Customer KYC review and decisions, by store and zone." />

      <div className="grid grid-cols-3 gap-4">
        <StatCard label="Pending" value={summary?.pending ?? 0} accent={summary?.pending ? "gold" : "slate"} loading={query.isLoading} />
        <StatCard label="Verified" value={summary?.verified ?? 0} accent="green" loading={query.isLoading} />
        <StatCard label="Rejected" value={summary?.rejected ?? 0} accent="red" loading={query.isLoading} />
      </div>

      <div className="flex flex-wrap items-center gap-2">
        {FILTERS.map((f) => (
          <button
            key={f.key}
            onClick={() => setStatus(f.key)}
            className={cn(
              "rounded-full border px-3.5 py-1.5 text-sm transition-colors",
              status === f.key ? "border-primary bg-primary text-primary-foreground" : "bg-card hover:bg-accent"
            )}
          >
            {f.label}
          </button>
        ))}
        <div className="ml-auto"><StoreZoneFilter store={store} zone={zone} onStore={setStore} onZone={setZone} /></div>
      </div>

      <DataTable
        columns={columns}
        data={applications}
        loading={query.isLoading}
        error={query.isError ? "Failed to load verification queue." : null}
        onRetry={() => query.refetch()}
        emptyMessage="No applications in this queue."
        pageMeta={pageMeta}
        page={page}
        onPageChange={setPage}
      />

      <Dialog open={!!selected} onOpenChange={(o) => !o && setSelected(null)}>
        <DialogContent className="max-h-[85vh] max-w-2xl overflow-y-auto">
          <DialogHeader>
            <DialogTitle className="flex items-center gap-2">
              <BadgeCheck className="size-4" /> {selected?.userName || "Applicant"} — KYC
            </DialogTitle>
          </DialogHeader>

          {selected && (
            <div className="space-y-4">
              <div className="flex items-center justify-between text-sm">
                <span className="font-mono text-muted-foreground">{selected.userPhone}</span>
                <StatusBadge status={selected.status} />
              </div>

              {/* The document image IS the thing being reviewed. Without it the
                  reviewer was deciding on a masked number and a status chip. Served
                  through the permission-gated file endpoint, same as field evidence. */}
              <div>
                <p className="mb-1.5 text-xs font-semibold uppercase text-muted-foreground">Documents</p>
                {selected.documents.length === 0 ? (
                  <p className="text-sm text-muted-foreground">No documents submitted.</p>
                ) : (
                  <div className="grid gap-2 sm:grid-cols-2">
                    {selected.documents.map((d) => (
                      <div key={d.id} className="space-y-2 rounded-md border p-2">
                        <div className="flex items-center justify-between gap-2 text-sm">
                          <span className="font-medium">{titleize(d.type)}</span>
                          <StatusBadge status={d.status} />
                        </div>
                        {d.fileUrl ? (
                          <AuthImage
                            path={d.fileUrl}
                            alt={`${d.type} document`}
                            className="h-40 w-full rounded border object-cover"
                          />
                        ) : (
                          <div className="flex h-40 w-full items-center justify-center rounded border bg-muted text-xs text-muted-foreground">
                            No image uploaded
                          </div>
                        )}
                        <p className="font-mono text-xs text-muted-foreground">{d.numberMasked || "—"}</p>
                      </div>
                    ))}
                  </div>
                )}
              </div>

              {/* Gov-source verification result vs. what the customer declared. The
                  backend has stored this all along but never showed it, so a name
                  mismatch flagged by the provider was invisible at decision time. */}
              <div>
                <p className="mb-1.5 text-xs font-semibold uppercase text-muted-foreground">API verification</p>
                {selected.verifications.length === 0 ? (
                  <p className="text-sm text-muted-foreground">
                    No gov-source verification on record — decide on the documents and field evidence alone.
                  </p>
                ) : (
                  <div className="space-y-2">
                    {selected.verifications.map((v) => (
                      <div key={v.id} className="rounded-md border p-3">
                        <div className="mb-2 flex flex-wrap items-center gap-2 text-sm">
                          <span className="font-medium">{titleize(v.kind)}</span>
                          <StatusBadge status={v.status} />
                          {v.nameMatch === true && <Badge variant="success">Name match</Badge>}
                          {v.nameMatch === false && <Badge variant="destructive">Name mismatch</Badge>}
                          {v.provider && (
                            <span className="text-xs text-muted-foreground">via {v.provider}</span>
                          )}
                        </div>
                        <div className="grid grid-cols-2 gap-3 text-xs">
                          <div className="space-y-1">
                            <p className="uppercase text-muted-foreground">Customer declared</p>
                            <p className="font-medium">{selected.userName || "—"}</p>
                            <p className="font-mono text-muted-foreground">{selected.userPhone}</p>
                          </div>
                          <div className="space-y-1">
                            <p className="uppercase text-muted-foreground">Source returned</p>
                            <p className={cn("font-medium", v.nameMatch === false && "text-destructive")}>
                              {v.verifiedName || "—"}
                            </p>
                            <p className="text-muted-foreground">
                              DOB {v.verifiedDob || "—"}
                              {v.idMasked ? ` · ${v.idMasked}` : ""}
                            </p>
                          </div>
                        </div>
                        {v.verifiedAt && (
                          <p className="mt-2 text-xs text-muted-foreground">
                            Verified {fmtDate(v.verifiedAt, true)}
                          </p>
                        )}
                      </div>
                    ))}
                  </div>
                )}
              </div>

              <div>
                <p className="mb-1.5 text-xs font-semibold uppercase text-muted-foreground">Verification steps</p>
                <div className="flex flex-wrap gap-1.5">
                  {selected.steps.map((s) => (
                    <Badge key={s.step} variant={s.status === "approved" ? "success" : s.status === "rejected" ? "destructive" : "secondary"}>
                      {titleize(s.step)}: {s.status}
                    </Badge>
                  ))}
                </div>
              </div>

              {/* Field agent's on-site findings — advisory input into this decision. */}
              {selected.fieldVerification && (
                <div>
                  <p className="mb-1.5 text-xs font-semibold uppercase text-muted-foreground">Field verification</p>
                  <div className="space-y-2 rounded-md border p-3 text-sm">
                    <div className="flex items-center gap-2">
                      <span className="text-muted-foreground">
                        {selected.fieldVerification.agent || "Unassigned"} · {titleize(selected.fieldVerification.status)}
                      </span>
                      {selected.fieldVerification.recommendation && (
                        <Badge variant={
                          selected.fieldVerification.recommendation === "approve" ? "success"
                            : selected.fieldVerification.recommendation === "reject" ? "destructive"
                            : "secondary"
                        }>
                          Recommends {titleize(selected.fieldVerification.recommendation)}
                        </Badge>
                      )}
                    </div>
                    {selected.fieldVerification.note && (
                      <p className="text-muted-foreground">{selected.fieldVerification.note}</p>
                    )}
                    {selected.fieldVerification.evidence.length > 0 && (
                      <div className="flex flex-wrap gap-2">
                        {selected.fieldVerification.evidence.map((e, i) =>
                          e.photoUrl ? (
                            <AuthImage key={i} path={e.photoUrl} alt={e.kind}
                              className="size-20 rounded-md border object-cover" />
                          ) : (
                            <span key={i} className="rounded-md border px-2 py-1 text-xs text-muted-foreground">
                              {titleize(e.kind)}{e.lat != null ? ` · ${e.lat.toFixed(4)}, ${e.lng?.toFixed(4)}` : ""}
                            </span>
                          ),
                        )}
                      </div>
                    )}
                    <p className="text-xs text-muted-foreground">Advisory — you make the final decision below.</p>
                  </div>
                </div>
              )}

              <div className="space-y-1.5">
                <Label htmlFor="note">
                  Rejection reason <span className="text-destructive">*</span>
                </Label>
                <Input
                  id="note"
                  value={note}
                  onChange={(e) => setNote(e.target.value)}
                  placeholder="e.g. Aadhaar image unreadable — please re-upload"
                />
                <p className="text-xs text-muted-foreground">
                  Required to reject. The customer sees this — it is the only thing telling them what to fix.
                </p>
              </div>
            </div>
          )}

          <DialogFooter className="gap-2">
            <Button
              variant="destructive"
              disabled={decide.isPending || !rejectReason}
              title={rejectReason ? undefined : "Enter a rejection reason first"}
              onClick={() => selected && decide.mutate({ id: selected.id, decision: "reject", note: rejectReason })}
            >
              {decide.isPending ? <Loader2 className="size-4 animate-spin" /> : <X />} Reject
            </Button>
            <Button
              disabled={decide.isPending}
              onClick={() => selected && decide.mutate({ id: selected.id, decision: "approve" })}
            >
              {decide.isPending ? <Loader2 className="size-4 animate-spin" /> : <Check />} Approve
            </Button>
          </DialogFooter>
        </DialogContent>
      </Dialog>
    </>
  );
}
