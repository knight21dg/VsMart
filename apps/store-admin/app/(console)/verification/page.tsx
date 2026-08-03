"use client";

import * as React from "react";
import { useQuery } from "@tanstack/react-query";
import type { ColumnDef } from "@tanstack/react-table";
import { Check, X, UserCheck } from "lucide-react";
import { api, useApiMutation } from "@/lib/api/hooks";
import { useStore } from "@/lib/store/store-context";
import { PageHeader } from "@/components/page-header";
import { DataTable } from "@/components/data-table";
import { RequirePerm } from "@/components/permission-gate";
import { StatusBadge } from "@/components/status-badge";
import { Button } from "@/components/ui/button";
import { Badge } from "@/components/ui/badge";
import { Textarea } from "@/components/ui/textarea";
import {
  Dialog, DialogContent, DialogHeader, DialogTitle, DialogDescription,
} from "@/components/ui/dialog";
import { AuthImage } from "@/components/auth-image";
import { ErrorState, LoadingState } from "@/components/states";
import { KV, Section, sheetClass } from "@/components/detail-sheet";
import { fmtDate, titleize } from "@/lib/utils";

interface KycRow {
  id: string; customerId: string; name: string; phone: string; status: string; submittedAt: string;
}

interface KycDetail {
  id: string; customerId: string; name: string; phone: string; status: string;
  submittedAt: string; reviewedBy: string | null; reviewedAt: string | null; rejectionReason: string;
  documents: { id: string; type: string; numberMasked: string; status: string; fileUrl: string | null }[];
  verifications: { kind: string; provider: string; status: string; verifiedName: string; idMasked: string; nameMatch: boolean | null; verifiedAt: string | null }[];
  credit: {
    score: number; band: string; bureauName: string; bureauPan: string;
    enteredName: string; enteredDob: string; enteredPan: string;
    nameMatch: boolean | null; panMatch: boolean | null; checkedAt: string | null;
  } | null;
  assignment: {
    taskId: string; status: string; agent: string | null; agentId: string | null;
    recommendation: string | null; note: string;
    submittedAt: string | null;
    evidence: { kind: string; photoUrl: string | null; lat: number | null; lng: number | null; at: string }[];
  } | null;
}

interface StoreAgent { id: string; name: string; phone: string }

export default function VerificationPage() {
  return (
    <RequirePerm perm="verification.view">
      <VerificationInner />
    </RequirePerm>
  );
}

function VerificationInner() {
  const { hasPerm } = useStore();
  const canManage = hasPerm("verification.manage");
  const [filter, setFilter] = React.useState("pending");
  const [openId, setOpenId] = React.useState<string | null>(null);

  const q = useQuery({
    queryKey: ["store", "verification", filter],
    queryFn: () => api.get<KycRow[]>("/store/verification", { status: filter }),
  });

  const decide = useApiMutation(
    ({ id, decision }: { id: string; decision: "approve" | "reject" }) =>
      api.post(`/store/verification/${id}/decision`, { decision }),
    { invalidate: [["store", "verification"]], successMessage: "KYC updated" }
  );

  const columns: ColumnDef<KycRow, unknown>[] = [
    {
      header: "Customer",
      cell: ({ row }) => (
        <button onClick={() => setOpenId(row.original.id)} className="text-left">
          <div className="font-medium text-primary hover:underline">{row.original.name}</div>
          <div className="text-xs text-muted-foreground">{row.original.phone}</div>
        </button>
      ),
    },
    { header: "Status", cell: ({ row }) => <StatusBadge status={row.original.status} /> },
    { header: "Submitted", cell: ({ row }) => <span className="text-xs text-muted-foreground">{fmtDate(row.original.submittedAt, true)}</span> },
    {
      header: "", id: "actions",
      cell: ({ row }) => canManage && row.original.status === "pending" ? (
        <div className="flex gap-1.5">
          <Button size="sm" variant="outline" onClick={() => setOpenId(row.original.id)}>Review</Button>
          <Button size="sm" onClick={() => decide.mutate({ id: row.original.id, decision: "approve" })} disabled={decide.isPending}>
            <Check className="size-3.5" /> Approve
          </Button>
        </div>
      ) : null,
    },
  ];

  return (
    <div className="space-y-5">
      <PageHeader title="Verification" description="KYC submissions from your store's customers." />
      <DataTable
        columns={columns}
        data={q.data ?? []}
        loading={q.isLoading}
        error={q.error ? "Couldn't load the KYC queue." : null}
        onRetry={() => q.refetch()}
        emptyMessage="No verifications in this view."
        toolbar={
          <div className="flex gap-2">
            {["pending", "verified", "rejected", "all"].map((s) => (
              <button key={s} onClick={() => setFilter(s)}
                className={`rounded-full px-3 py-1 text-xs font-medium capitalize transition-colors ${filter === s ? "bg-primary text-primary-foreground" : "bg-muted text-muted-foreground hover:bg-accent"}`}>
                {s}
              </button>
            ))}
          </div>
        }
      />
      <KycDetailSheet id={openId} onClose={() => setOpenId(null)} canManage={canManage} />
    </div>
  );
}

const VERIF_OK = ["verified", "success", "approved", "match"];

function KycDetailSheet({ id, onClose, canManage }: { id: string | null; onClose: () => void; canManage: boolean }) {
  const open = id !== null;
  const [reason, setReason] = React.useState("");

  const q = useQuery({
    queryKey: ["store", "verification", "detail", id],
    queryFn: () => api.get<KycDetail>(`/store/verification/${id}`),
    enabled: open,
  });

  function close() {
    setReason("");
    onClose();
  }

  const decide = useApiMutation(
    ({ decision }: { decision: "approve" | "reject" }) =>
      api.post(`/store/verification/${id}/decision`, { decision, note: reason.trim() }),
    {
      invalidate: [["store", "verification"], ["store", "verification", "detail", id]],
      successMessage: "KYC updated",
    },
  );

  const [agentId, setAgentId] = React.useState("");
  const agentsQ = useQuery({
    queryKey: ["store", "verification", "agents"],
    queryFn: () => api.get<StoreAgent[]>("/store/verification/agents"),
    enabled: open && canManage,
  });
  const assign = useApiMutation<void>(
    () => api.post(`/store/verification/${id}/assign`, { agentId }),
    {
      invalidate: [["store", "verification", "detail", id]],
      successMessage: "Agent assigned to verify documents",
    },
  );

  const d = q.data;
  const pending = d?.status === "pending";

  return (
    <Dialog open={open} onOpenChange={(o) => !o && close()}>
      <DialogContent className={sheetClass}>
        <DialogHeader>
          <DialogTitle>{d?.name || "KYC review"}</DialogTitle>
          <DialogDescription>
            {d ? `${d.phone} · submitted ${fmtDate(d.submittedAt, true)}` : "Verification detail"}
          </DialogDescription>
        </DialogHeader>

        {q.isLoading ? (
          <LoadingState label="Loading submission…" />
        ) : q.error || !d ? (
          <ErrorState message="Couldn't load this submission." onRetry={() => q.refetch()} />
        ) : (
          <div className="space-y-5 text-sm">
            <div className="flex flex-wrap items-center gap-2">
              <StatusBadge status={d.status} />
              {d.reviewedBy && (
                <span className="ml-auto text-xs text-muted-foreground">
                  by {d.reviewedBy}{d.reviewedAt ? ` · ${fmtDate(d.reviewedAt)}` : ""}
                </span>
              )}
            </div>

            <Section title={`Documents (${d.documents.length})`}>
              {d.documents.length === 0 ? (
                <p className="text-muted-foreground">No documents submitted.</p>
              ) : (
                <div className="grid grid-cols-2 gap-3">
                  {d.documents.map((doc) => (
                    <div key={doc.id} className="overflow-hidden rounded-lg border">
                      {doc.fileUrl ? (
                        <AuthImage path={doc.fileUrl} alt={doc.type} className="h-32 w-full" />
                      ) : (
                        <div className="flex h-32 w-full items-center justify-center bg-muted text-xs text-muted-foreground">No file</div>
                      )}
                      <div className="flex items-center justify-between gap-2 px-2 py-1.5">
                        <div className="min-w-0">
                          <p className="truncate text-xs font-medium">{titleize(doc.type)}</p>
                          {doc.numberMasked && <p className="truncate text-[10px] text-muted-foreground">{doc.numberMasked}</p>}
                        </div>
                        <Badge variant={VERIF_OK.includes(doc.status) ? "success" : "secondary"} className="shrink-0 text-[10px]">
                          {titleize(doc.status)}
                        </Badge>
                      </div>
                    </div>
                  ))}
                </div>
              )}
            </Section>

            {d.verifications.length > 0 && (
              <Section title="Gov-source verification">
                {d.verifications.map((v, i) => (
                  <div key={i} className="rounded-lg border p-2.5">
                    <div className="flex items-center justify-between">
                      <span className="font-medium">{titleize(v.kind)}{v.provider ? ` · ${v.provider}` : ""}</span>
                      <Badge variant={VERIF_OK.includes(v.status) ? "success" : "secondary"}>{titleize(v.status)}</Badge>
                    </div>
                    {v.verifiedName && <KV label="Name" value={v.verifiedName} />}
                    {v.idMasked && <KV label="ID" value={v.idMasked} />}
                    {v.nameMatch != null && <KV label="Name match" value={v.nameMatch ? "Yes" : "No"} />}
                  </div>
                ))}
              </Section>
            )}

            {d.credit && (
              <Section title="Credit-bureau check (CIBIL)">
                <div className="rounded-lg border p-2.5">
                  <div className="flex items-center justify-between">
                    <span className="text-lg font-bold">{d.credit.score || "—"}</span>
                    {d.credit.band && <Badge variant="secondary">{d.credit.band}</Badge>}
                  </div>
                  <KV label="Name on record" value={d.credit.bureauName || "—"} />
                  <KV label="Entered name" value={d.credit.enteredName || "—"} />
                  <KV label="Entered DOB" value={d.credit.enteredDob || "—"} />
                  <KV label="PAN" value={d.credit.bureauPan || d.credit.enteredPan || "—"} />
                  <div className="mt-1.5 flex gap-2">
                    <Badge variant={d.credit.nameMatch ? "success" : "secondary"}>
                      Name {d.credit.nameMatch ? "matched" : "not matched"}
                    </Badge>
                    <Badge variant={d.credit.panMatch ? "success" : "secondary"}>
                      PAN {d.credit.panMatch ? "matched" : "not matched"}
                    </Badge>
                  </div>
                </div>
              </Section>
            )}

            {d.assignment && (
              <Section title="Field verification">
                <KV label="Agent" value={d.assignment.agent || "Unassigned"} />
                <KV label="Task status" value={titleize(d.assignment.status)} />
                {d.assignment.recommendation && (
                  <div className="flex items-center gap-2 py-1">
                    <span className="text-sm text-muted-foreground">Agent recommends</span>
                    <Badge
                      variant={
                        d.assignment.recommendation === "approve" ? "success"
                          : d.assignment.recommendation === "reject" ? "destructive"
                          : "secondary"
                      }
                    >
                      {titleize(d.assignment.recommendation)}
                    </Badge>
                    <span className="text-xs text-muted-foreground">(advisory — you decide)</span>
                  </div>
                )}
                {d.assignment.note && (
                  <KV label="Agent note" value={d.assignment.note} />
                )}
                {d.assignment.evidence.length > 0 && (
                  <div className="space-y-1.5 pt-1">
                    <p className="text-xs font-semibold uppercase tracking-wider text-muted-foreground">Evidence</p>
                    <div className="flex flex-wrap gap-2">
                      {d.assignment.evidence.map((e, i) =>
                        e.photoUrl ? (
                          <AuthImage
                            key={i}
                            path={e.photoUrl}
                            alt={e.kind}
                            className="size-20 rounded-md border object-cover"
                          />
                        ) : (
                          <span key={i} className="rounded-md border px-2 py-1 text-xs text-muted-foreground">
                            {titleize(e.kind)}{e.lat != null ? ` · ${e.lat.toFixed(4)}, ${e.lng?.toFixed(4)}` : ""}
                          </span>
                        ),
                      )}
                    </div>
                  </div>
                )}
              </Section>
            )}

            {d.status === "rejected" && d.rejectionReason && (
              <Section title="Rejection reason">
                <p className="text-muted-foreground">{d.rejectionReason}</p>
              </Section>
            )}

            {canManage && pending && (
              <div className="space-y-3 border-t pt-4">
                {/* Assign a field agent to verify documents, or decide directly. */}
                <div className="space-y-1.5">
                  <p className="text-xs font-semibold uppercase tracking-wider text-muted-foreground">Assign an agent (optional)</p>
                  <div className="flex gap-2">
                    <select
                      value={agentId}
                      onChange={(e) => setAgentId(e.target.value)}
                      className="h-9 flex-1 rounded-md border bg-background px-2 text-sm"
                    >
                      <option value="">Select a field agent…</option>
                      {(agentsQ.data ?? []).map((a) => (
                        <option key={a.id} value={a.id}>{a.name} · {a.phone}</option>
                      ))}
                    </select>
                    <Button
                      size="sm"
                      variant="outline"
                      disabled={assign.isPending || !agentId}
                      onClick={() => assign.mutate()}
                    >
                      <UserCheck className="size-3.5" /> Assign
                    </Button>
                  </div>
                </div>

                <p className="text-xs font-semibold uppercase tracking-wider text-muted-foreground">Reject reason (required to reject)</p>
                <Textarea
                  value={reason}
                  onChange={(e) => setReason(e.target.value)}
                  placeholder="Why is this submission being rejected?"
                />
                <div className="flex gap-2 pt-1">
                  <Button size="sm" disabled={decide.isPending} onClick={() => decide.mutate({ decision: "approve" })}>
                    <Check className="size-3.5" /> Approve
                  </Button>
                  <Button
                    size="sm"
                    variant="outline"
                    disabled={decide.isPending || reason.trim().length === 0}
                    onClick={() => decide.mutate({ decision: "reject" })}
                  >
                    <X className="size-3.5" /> Reject
                  </Button>
                </div>
              </div>
            )}
          </div>
        )}
      </DialogContent>
    </Dialog>
  );
}
