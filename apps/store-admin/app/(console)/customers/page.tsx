"use client";

import * as React from "react";
import { useQuery } from "@tanstack/react-query";
import type { ColumnDef } from "@tanstack/react-table";
import { RefreshCw, Loader2 } from "lucide-react";
import { api } from "@/lib/api/client";
import { useApiMutation } from "@/lib/api/hooks";
import { PageHeader } from "@/components/page-header";
import { DataTable } from "@/components/data-table";
import { RequirePerm } from "@/components/permission-gate";
import { StatusBadge } from "@/components/status-badge";
import { Badge } from "@/components/ui/badge";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import {
  Dialog, DialogContent, DialogHeader, DialogTitle, DialogDescription,
} from "@/components/ui/dialog";
import { ErrorState, LoadingState } from "@/components/states";
import { KV, Section, sheetClass } from "@/components/detail-sheet";
import { inr, fmtDate, titleize } from "@/lib/utils";

interface CustomerRow {
  id: string; vsId: string; name: string; phone: string; kycStatus: string;
  vsScore: number | null; outstanding: number; orders: number; revenue: number;
  lastActiveAt: string | null; active: boolean; risk: string;
}

interface Customer360 {
  header: {
    vsId: string; name: string | null; phone: string; customerSince: string | null;
    zone: string | null; store: string | null; collectionAgent: string | null;
    deliveryAgent: string | null; status: string; risk: string;
  };
  health: {
    lifetimeRevenue: number; orders: number; creditUsed: number; collections: number;
    outstanding: number; vsScore: number | null; collectionEfficiency: number | null; retentionMonths: number;
  };
  creditIntelligence: {
    hasAccount: boolean; status?: string; creditLimit?: number; availableCredit?: number;
    usedCredit?: number; outstanding?: number; overdue?: number; nextDueDate?: string | null;
    repaymentRate?: number; latePayments?: number; missedPayments?: number;
  };
  orderAnalytics: {
    totalOrders: number; delivered: number; cancelled: number; returned: number;
    averageOrderValue: number; highestOrder: number; monthlySpend: number;
    favoriteCategories: string[]; favoriteBrands: string[];
  };
  collectionAnalytics: {
    totalCollections: number; totalCount: number; pending: number; failed: number;
    averageRecoveryDays: number; lastCollectionAt: string | null; collectionAgent: string | null;
  };
  verification: {
    aadhaar: string; pan: string; selfie: string; house: string; gps: string;
    agentVerified: boolean; verifiedAt: string | null; verifiedBy: string | null;
  };
  risk: { score: number; level: string };
}

const RISK_VARIANT: Record<string, "success" | "warning" | "destructive" | "secondary"> = {
  low: "success", medium: "warning", high: "destructive", critical: "destructive",
};

export default function CustomersPage() {
  return (
    <RequirePerm perm="customers.view">
      <CustomersInner />
    </RequirePerm>
  );
}

function CustomersInner() {
  const [q, setQ] = React.useState("");
  const [openId, setOpenId] = React.useState<string | null>(null);
  const query = useQuery({
    queryKey: ["store", "customers", q],
    queryFn: () => api.get<CustomerRow[]>("/store/customers", q ? { q } : {}),
  });

  const columns: ColumnDef<CustomerRow, unknown>[] = [
    {
      header: "Customer",
      cell: ({ row }) => (
        <button onClick={() => setOpenId(row.original.id)} className="text-left">
          <div className="font-medium text-primary hover:underline">{row.original.name || "—"}</div>
          <div className="text-xs text-muted-foreground">{row.original.phone} · {row.original.vsId}</div>
        </button>
      ),
    },
    { header: "VS Score", cell: ({ row }) => <span className="text-sm">{row.original.vsScore ?? "—"}</span> },
    { header: "Orders", accessorKey: "orders" },
    { header: "Revenue", cell: ({ row }) => <span className="text-sm">{inr(row.original.revenue)}</span> },
    { header: "Outstanding", cell: ({ row }) => <span className={row.original.outstanding > 0 ? "font-medium text-destructive" : "text-muted-foreground"}>{inr(row.original.outstanding)}</span> },
    { header: "KYC", cell: ({ row }) => <StatusBadge status={row.original.kycStatus} /> },
    { header: "Risk", cell: ({ row }) => <Badge variant={RISK_VARIANT[row.original.risk] ?? "secondary"}>{titleize(row.original.risk)}</Badge> },
    { header: "Last active", cell: ({ row }) => <span className="text-xs text-muted-foreground">{fmtDate(row.original.lastActiveAt)}</span> },
  ];

  return (
    <div className="space-y-5">
      <PageHeader title="Customers" description="People who order from your store." />
      <DataTable
        columns={columns}
        data={query.data ?? []}
        loading={query.isLoading}
        error={query.error ? "Couldn't load customers." : null}
        onRetry={() => query.refetch()}
        emptyMessage="No customers yet."
        toolbar={<Input placeholder="Search name or phone…" value={q} onChange={(e) => setQ(e.target.value)} className="max-w-xs" />}
      />
      <CustomerDetailSheet id={openId} onClose={() => setOpenId(null)} />
    </div>
  );
}

const DOC_OK = ["approved", "verified", "captured"];

type StoreCibil = {
  id: string; status: "success" | "no_record"; score: number; band: string;
  nameOnBureau: string; pan: string; mobile: string; provider: string;
  source: string; checkedAt: string | null;
};

/** CIBIL score for a customer, with a staff refresh (re-pull). Refresh reuses the
 * customer's own consent — the backend blocks it if they never consented. */
function CibilSection({ customerId }: { customerId: string }) {
  const q = useQuery({
    queryKey: ["store", "cibil", customerId],
    queryFn: () =>
      api.get<{ report: StoreCibil | null }>(`/store/credit/${customerId}/cibil`),
  });
  const refresh = useApiMutation<void, { report: StoreCibil | null }>(
    () => api.post<{ report: StoreCibil | null }>(`/store/credit/${customerId}/cibil`),
    { invalidate: [["store", "cibil", customerId]], successMessage: "CIBIL score refreshed" }
  );
  const r = q.data?.report ?? null;
  return (
    <Section title="CIBIL Score">
      {q.isLoading ? (
        <p className="text-xs text-muted-foreground">Loading…</p>
      ) : !r ? (
        <p className="text-xs text-muted-foreground">
          No score on file — the customer hasn&apos;t run a CIBIL check yet.
        </p>
      ) : r.status !== "success" ? (
        <p className="text-xs text-muted-foreground">No bureau record found.</p>
      ) : (
        <>
          <KV label="Score" value={<span className="font-semibold">{r.score} · {r.band}</span>} />
          {r.nameOnBureau && <KV label="Name" value={r.nameOnBureau} />}
          {r.pan && <KV label="PAN" value={r.pan} />}
          {r.checkedAt && <KV label="Checked" value={fmtDate(r.checkedAt)} />}
        </>
      )}
      {r && (
        <Button
          size="sm"
          variant="outline"
          className="mt-2"
          onClick={() => refresh.mutate()}
          disabled={refresh.isPending}
        >
          {refresh.isPending ? (
            <Loader2 className="mr-1.5 h-3.5 w-3.5 animate-spin" />
          ) : (
            <RefreshCw className="mr-1.5 h-3.5 w-3.5" />
          )}
          Refresh
        </Button>
      )}
    </Section>
  );
}

function CustomerDetailSheet({ id, onClose }: { id: string | null; onClose: () => void }) {
  const open = id !== null;
  const q = useQuery({
    queryKey: ["store", "customers", "detail", id],
    queryFn: () => api.get<Customer360>(`/store/customers/${id}`),
    enabled: open,
  });
  const d = q.data;

  return (
    <Dialog open={open} onOpenChange={(o) => !o && onClose()}>
      <DialogContent className={sheetClass}>
        <DialogHeader>
          <DialogTitle>{d?.header.name || "Customer"}</DialogTitle>
          <DialogDescription>
            {d ? `${d.header.phone} · ${d.header.vsId}` : "Customer 360"}
          </DialogDescription>
        </DialogHeader>

        {q.isLoading ? (
          <LoadingState label="Loading customer…" />
        ) : q.error || !d ? (
          <ErrorState message="Couldn't load this customer." onRetry={() => q.refetch()} />
        ) : (
          <div className="space-y-5 text-sm">
            <div className="flex flex-wrap items-center gap-2">
              <StatusBadge status={d.header.status} />
              <Badge variant={RISK_VARIANT[d.header.risk] ?? "secondary"}>
                {titleize(d.header.risk)} risk · {d.risk.score}
              </Badge>
              {d.health.vsScore != null && (
                <span className="ml-auto rounded-full bg-muted px-2 py-0.5 text-xs text-muted-foreground">
                  VS Score {d.health.vsScore}
                </span>
              )}
            </div>

            <Section title="Profile">
              {d.header.customerSince && <KV label="Customer since" value={fmtDate(d.header.customerSince)} />}
              {(d.header.zone || d.header.store) && (
                <KV label="Zone / Store" value={[d.header.zone, d.header.store].filter(Boolean).join(" · ") || "—"} />
              )}
              {d.header.deliveryAgent && <KV label="Delivery agent" value={d.header.deliveryAgent} />}
              {d.header.collectionAgent && <KV label="Collection agent" value={d.header.collectionAgent} />}
            </Section>

            <Section title="Health">
              <KV label="Lifetime revenue" value={inr(d.health.lifetimeRevenue)} />
              <KV label="Orders" value={String(d.health.orders)} />
              <KV label="Outstanding" value={<span className={d.health.outstanding > 0 ? "text-destructive" : ""}>{inr(d.health.outstanding)}</span>} />
              <KV label="Collections" value={inr(d.health.collections)} />
              <KV
                label="Collection efficiency"
                value={d.health.collectionEfficiency == null ? "—" : `${d.health.collectionEfficiency}%`}
              />
              <KV label="Retention" value={`${d.health.retentionMonths} mo`} />
            </Section>

            {d.creditIntelligence.hasAccount && (
              <Section title="Credit">
                <KV label="Status" value={titleize(d.creditIntelligence.status ?? "")} />
                <KV label="Limit" value={inr(d.creditIntelligence.creditLimit ?? 0)} />
                <KV label="Available" value={inr(d.creditIntelligence.availableCredit ?? 0)} />
                <KV label="Used" value={inr(d.creditIntelligence.usedCredit ?? 0)} />
                {(d.creditIntelligence.overdue ?? 0) > 0 && (
                  <KV label="Overdue" value={<span className="text-destructive">{inr(d.creditIntelligence.overdue ?? 0)}</span>} />
                )}
                {d.creditIntelligence.nextDueDate && <KV label="Next due" value={fmtDate(d.creditIntelligence.nextDueDate)} />}
                <KV label="Repayment rate" value={`${d.creditIntelligence.repaymentRate ?? 0}%`} />
                {(d.creditIntelligence.latePayments ?? 0) > 0 && <KV label="Late payments" value={String(d.creditIntelligence.latePayments)} />}
              </Section>
            )}

            {id && <CibilSection customerId={id} />}

            <Section title="Orders">
              <KV label="Total / Delivered" value={`${d.orderAnalytics.totalOrders} · ${d.orderAnalytics.delivered} delivered`} />
              {d.orderAnalytics.cancelled > 0 && <KV label="Cancelled / Returned" value={`${d.orderAnalytics.cancelled} · ${d.orderAnalytics.returned}`} />}
              <KV label="Avg order value" value={inr(d.orderAnalytics.averageOrderValue)} />
              <KV label="Highest order" value={inr(d.orderAnalytics.highestOrder)} />
              <KV label="This month" value={inr(d.orderAnalytics.monthlySpend)} />
              {d.orderAnalytics.favoriteCategories.length > 0 && (
                <KV label="Top categories" value={d.orderAnalytics.favoriteCategories.slice(0, 3).join(", ")} />
              )}
            </Section>

            {d.collectionAnalytics.totalCount > 0 && (
              <Section title="Collections">
                <KV label="Collected" value={`${inr(d.collectionAnalytics.totalCollections)} (${d.collectionAnalytics.totalCount})`} />
                {d.collectionAnalytics.pending > 0 && <KV label="Pending" value={inr(d.collectionAnalytics.pending)} />}
                <KV label="Avg recovery" value={`${d.collectionAnalytics.averageRecoveryDays} days`} />
                {d.collectionAnalytics.lastCollectionAt && <KV label="Last collection" value={fmtDate(d.collectionAnalytics.lastCollectionAt)} />}
              </Section>
            )}

            <Section title="Verification">
              <div className="grid grid-cols-2 gap-1.5">
                {([
                  ["Aadhaar", d.verification.aadhaar], ["PAN", d.verification.pan],
                  ["Selfie", d.verification.selfie], ["Residence", d.verification.house],
                  ["GPS", d.verification.gps],
                ] as const).map(([label, val]) => (
                  <Badge key={label} variant={DOC_OK.includes(val) ? "success" : "secondary"} className="justify-start">
                    {label}: {titleize(val)}
                  </Badge>
                ))}
              </div>
              {d.verification.verifiedBy && (
                <p className="pt-1 text-xs text-muted-foreground">
                  Verified by {d.verification.verifiedBy}{d.verification.verifiedAt ? ` · ${fmtDate(d.verification.verifiedAt)}` : ""}
                </p>
              )}
            </Section>
          </div>
        )}
      </DialogContent>
    </Dialog>
  );
}
