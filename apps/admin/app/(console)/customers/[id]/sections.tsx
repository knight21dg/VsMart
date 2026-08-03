"use client";

import * as React from "react";
import { useQuery } from "@tanstack/react-query";
import { RefreshCw, Loader2 } from "lucide-react";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";
import { Button } from "@/components/ui/button";
import { StatusBadge } from "@/components/status-badge";
import { EmptyState } from "@/components/states";
import { AreaTrend, BarTrend } from "@/components/trend-chart";
import { api, useApiMutation } from "@/lib/api/hooks";
import { inr, fmtDate, titleize } from "@/lib/utils";
import type {
  Customer360,
  C360Credit,
  C360Orders,
  C360Collections,
  C360Verification,
  C360Network,
  C360Support,
  C360Exposure,
  C360Risk,
  C360TimelineEvent,
  C360Note,
} from "./types";

export function Field({ label, children }: { label: string; children: React.ReactNode }) {
  return (
    <div>
      <p className="text-xs uppercase tracking-wide text-muted-foreground">{label}</p>
      <div className="mt-0.5 text-sm font-medium">{children}</div>
    </div>
  );
}

function Pill({ children }: { children: React.ReactNode }) {
  return (
    <span className="inline-flex items-center rounded-md bg-muted px-2 py-0.5 text-xs font-medium">
      {children}
    </span>
  );
}

// ── Overview: financial exposure + AI insights + risk factors ──
export function OverviewTab({ data }: { data: Customer360 }) {
  const exp = data.financialExposure;
  const insights = data.aiInsights;
  const flags = Object.entries(insights).filter(
    ([k, v]) => k !== "note" && k !== "_note" && v === true
  );
  return (
    <div className="grid gap-4 lg:grid-cols-2">
      <ExposurePanel exp={exp} />
      <Card>
        <CardHeader>
          <CardTitle>Business Insights</CardTitle>
        </CardHeader>
        <CardContent>
          {flags.length ? (
            <div className="flex flex-wrap gap-2">
              {flags.map(([k]) => (
                <span
                  key={k}
                  className="inline-flex items-center rounded-full bg-primary/10 px-3 py-1 text-xs font-medium text-primary"
                >
                  {titleize(k)}
                </span>
              ))}
            </div>
          ) : (
            <p className="text-sm text-muted-foreground">No notable signals.</p>
          )}
        </CardContent>
      </Card>
      <RiskCard risk={data.risk} className="lg:col-span-2" />
    </div>
  );
}

function ExposurePanel({ exp }: { exp: C360Exposure }) {
  return (
    <Card>
      <CardHeader>
        <CardTitle>Financial Exposure</CardTitle>
      </CardHeader>
      <CardContent>
        {exp.hasExposure ? (
          <div className="grid grid-cols-2 gap-4 sm:grid-cols-3">
            <Field label="Total Exposure">{inr(exp.totalExposure)}</Field>
            <Field label="Outstanding">{inr(exp.currentOutstanding)}</Field>
            <Field label="Overdue">{inr(exp.overdueAmount)}</Field>
            <Field label="Expected Recovery">{inr(exp.expectedRecovery)}</Field>
            <Field label="Recovery Probability">
              {Math.round((exp.recoveryProbability ?? 0) * 100)}%
            </Field>
            <Field label="Days Past Due">{exp.daysPastDue ?? 0}</Field>
            <Field label="Risk Bucket">
              <StatusBadge status={exp.riskBucket} />
            </Field>
            <Field label="Projected Loss">
              <span className="text-destructive">{inr(exp.projectedLoss)}</span>
            </Field>
          </div>
        ) : (
          <p className="text-sm text-muted-foreground">No credit exposure.</p>
        )}
      </CardContent>
    </Card>
  );
}

function RiskCard({ risk, className }: { risk: C360Risk; className?: string }) {
  return (
    <Card className={className}>
      <CardHeader>
        <CardTitle>Risk Engine</CardTitle>
      </CardHeader>
      <CardContent className="space-y-3">
        <div className="flex items-center gap-3">
          <span className="text-3xl font-bold tracking-tight">{risk.score}</span>
          <StatusBadge status={risk.level} />
        </div>
        <div className="grid grid-cols-2 gap-3 sm:grid-cols-4">
          {Object.entries(risk.factors).map(([k, v]) => (
            <Field key={k} label={titleize(k)}>
              {typeof v === "boolean" ? (v ? "Yes" : "No") : String(v)}
            </Field>
          ))}
        </div>
      </CardContent>
    </Card>
  );
}

// ── Credit intelligence ──
type CibilReport = {
  id: string;
  status: "success" | "no_record";
  score: number;
  band: string;
  nameOnBureau: string;
  pan: string;
  mobile: string;
  provider: string;
  source: string;
  checkedAt: string | null;
};

/** Stored CIBIL bureau score for a customer, with a staff refresh (re-pull).
 * Refresh reuses the customer's own consent — the backend blocks it otherwise. */
export function CibilCard({ customerId }: { customerId: string }) {
  const q = useQuery({
    queryKey: ["admin", "cibil", customerId],
    queryFn: () =>
      api.get<{ report: CibilReport | null }>(`/admin/credit/cibil/${customerId}`),
  });
  const refresh = useApiMutation<void, CibilReport>(
    () => api.post<CibilReport>(`/admin/credit/cibil/${customerId}`),
    {
      invalidate: [["admin", "cibil", customerId]],
      successMessage: "CIBIL score refreshed",
    }
  );
  const report = q.data?.report ?? null;
  const hasScore = report?.status === "success";
  return (
    <Card>
      <CardHeader className="flex flex-row items-center justify-between space-y-0">
        <CardTitle>CIBIL Score</CardTitle>
        {report && (
          <Button
            size="sm"
            variant="outline"
            onClick={() => refresh.mutate()}
            disabled={refresh.isPending}
          >
            {refresh.isPending ? (
              <Loader2 className="mr-1.5 h-4 w-4 animate-spin" />
            ) : (
              <RefreshCw className="mr-1.5 h-4 w-4" />
            )}
            Refresh
          </Button>
        )}
      </CardHeader>
      <CardContent>
        {q.isLoading ? (
          <p className="text-sm text-muted-foreground">Loading…</p>
        ) : !report ? (
          <EmptyState
            title="No score on file"
            description="The customer hasn't run a CIBIL check in the app yet."
          />
        ) : !hasScore ? (
          <p className="text-sm text-muted-foreground">
            No bureau record was found for this customer.
          </p>
        ) : (
          <div className="grid grid-cols-2 gap-4 sm:grid-cols-4">
            <Field label="Score">
              <span className="text-2xl font-bold">{report.score}</span>
            </Field>
            <Field label="Band">
              <StatusBadge status={report.band} />
            </Field>
            <Field label="Name">{report.nameOnBureau || "—"}</Field>
            <Field label="PAN">{report.pan || "—"}</Field>
            <Field label="Mobile">{report.mobile || "—"}</Field>
            <Field label="Checked">{fmtDate(report.checkedAt)}</Field>
            <Field label="Source">{titleize(report.source)}</Field>
            <Field label="Provider">{report.provider || "—"}</Field>
          </div>
        )}
      </CardContent>
    </Card>
  );
}

export function CreditTab({
  credit,
  customerId,
}: {
  credit: C360Credit;
  customerId: string;
}) {
  if (!credit.hasAccount) {
    return (
      <div className="space-y-4">
        <CibilCard customerId={customerId} />
        <EmptyState title="No credit account" />
      </div>
    );
  }
  const trend = credit.usageTrend ?? [];
  return (
    <div className="space-y-4">
      <CibilCard customerId={customerId} />
      <Card>
        <CardHeader>
          <CardTitle>Credit Summary</CardTitle>
        </CardHeader>
        <CardContent className="grid grid-cols-2 gap-4 sm:grid-cols-4">
          <Field label="Limit">{inr(credit.creditLimit)}</Field>
          <Field label="Used">{inr(credit.usedCredit)}</Field>
          <Field label="Available">{inr(credit.availableCredit)}</Field>
          <Field label="Overdue">{inr(credit.overdue)}</Field>
          <Field label="Next Due">{fmtDate(credit.nextDueDate)}</Field>
          <Field label="Avg Monthly Usage">{inr(credit.averageMonthlyUsage)}</Field>
          <Field label="Max Utilization">{credit.maximumUtilization ?? 0}%</Field>
          <Field label="Repayment Rate">{credit.repaymentRate ?? 0}%</Field>
          <Field label="Late Payments">{credit.latePayments ?? 0}</Field>
          <Field label="Missed Payments">{credit.missedPayments ?? 0}</Field>
          <Field label="Risk Category">
            <StatusBadge status={credit.riskCategory} />
          </Field>
          <Field label="Status">
            <StatusBadge status={credit.status} />
          </Field>
        </CardContent>
      </Card>
      {trend.length > 0 && (
        <Card>
          <CardHeader>
            <CardTitle>Credit Usage Trend</CardTitle>
          </CardHeader>
          <CardContent>
            <AreaTrend
              data={trend as unknown as Record<string, unknown>[]}
              xKey="period"
              series={[
                { key: "balance", label: "Balance" },
                { key: "purchases", label: "Purchases" },
                { key: "payments", label: "Payments" },
              ]}
            />
          </CardContent>
        </Card>
      )}
    </div>
  );
}

// ── Order analytics ──
export function OrdersTab({ orders }: { orders: C360Orders }) {
  return (
    <div className="space-y-4">
      <Card>
        <CardHeader>
          <CardTitle>Order Summary</CardTitle>
        </CardHeader>
        <CardContent className="grid grid-cols-2 gap-4 sm:grid-cols-4">
          <Field label="Total Orders">{orders.totalOrders}</Field>
          <Field label="Delivered">{orders.delivered}</Field>
          <Field label="Cancelled">{orders.cancelled}</Field>
          <Field label="Returned">{orders.returned}</Field>
          <Field label="Avg Order Value">{inr(orders.averageOrderValue)}</Field>
          <Field label="Highest Order">{inr(orders.highestOrder)}</Field>
          <Field label="Monthly Spend">{inr(orders.monthlySpend)}</Field>
          <Field label="Preferred Hour">
            {orders.preferredPurchaseHour != null ? `${orders.preferredPurchaseHour}:00` : "—"}
          </Field>
        </CardContent>
      </Card>
      <div className="grid gap-4 lg:grid-cols-2">
        <Card>
          <CardHeader>
            <CardTitle>Favorite Categories</CardTitle>
          </CardHeader>
          <CardContent className="flex flex-wrap gap-2">
            {orders.favoriteCategories.length ? (
              orders.favoriteCategories.map((c) => <Pill key={c}>{c}</Pill>)
            ) : (
              <p className="text-sm text-muted-foreground">—</p>
            )}
          </CardContent>
        </Card>
        <Card>
          <CardHeader>
            <CardTitle>Favorite Brands</CardTitle>
          </CardHeader>
          <CardContent className="flex flex-wrap gap-2">
            {orders.favoriteBrands.length ? (
              orders.favoriteBrands.map((b) => <Pill key={b}>{b}</Pill>)
            ) : (
              <p className="text-sm text-muted-foreground">—</p>
            )}
          </CardContent>
        </Card>
      </div>
      {orders.charts.byMonth.length > 0 && (
        <Card>
          <CardHeader>
            <CardTitle>Revenue by Month</CardTitle>
          </CardHeader>
          <CardContent>
            <AreaTrend
              data={orders.charts.byMonth as unknown as Record<string, unknown>[]}
              xKey="month"
              series={[{ key: "revenue", label: "Revenue" }]}
            />
          </CardContent>
        </Card>
      )}
      {orders.charts.categorySpend.length > 0 && (
        <Card>
          <CardHeader>
            <CardTitle>Category Spend</CardTitle>
          </CardHeader>
          <CardContent>
            <BarTrend
              data={orders.charts.categorySpend as unknown as Record<string, unknown>[]}
              xKey="category"
              barKey="spend"
              label="Spend"
            />
          </CardContent>
        </Card>
      )}
    </div>
  );
}

// ── Collections ──
export function CollectionsTab({ col }: { col: C360Collections }) {
  return (
    <Card>
      <CardHeader>
        <CardTitle>Collection Analytics</CardTitle>
      </CardHeader>
      <CardContent className="grid grid-cols-2 gap-4 sm:grid-cols-4">
        <Field label="Total Collected">{inr(col.totalCollections)}</Field>
        <Field label="Collections">{col.totalCount}</Field>
        <Field label="Pending">{inr(col.pending)}</Field>
        <Field label="Failed">{col.failed}</Field>
        <Field label="Avg Recovery Days">{col.averageRecoveryDays}</Field>
        <Field label="Last Collection">{fmtDate(col.lastCollectionAt)}</Field>
        <Field label="Collector">{col.collectionAgent ?? "—"}</Field>
      </CardContent>
    </Card>
  );
}

// ── KYC / Verification ──
export function KycTab({ v }: { v: C360Verification }) {
  const rows: [string, string][] = [
    ["Aadhaar", v.aadhaar],
    ["PAN", v.pan],
    ["Selfie", v.selfie],
    ["House", v.house],
    ["GPS", v.gps],
  ];
  return (
    <div className="space-y-4">
      <Card>
        <CardHeader>
          <CardTitle>Verification Center</CardTitle>
        </CardHeader>
        <CardContent className="space-y-4">
          <div className="grid grid-cols-2 gap-4 sm:grid-cols-3">
            {rows.map(([label, status]) => (
              <Field key={label} label={label}>
                <StatusBadge status={status} />
              </Field>
            ))}
            <Field label="Agent Verified">{v.agentVerified ? "Yes" : "No"}</Field>
            <Field label="Verified On">{fmtDate(v.verifiedAt)}</Field>
            <Field label="Verified By">{v.verifiedBy ?? "—"}</Field>
          </div>
          {v.evidence.length > 0 && (
            <div>
              <p className="mb-2 text-xs uppercase tracking-wide text-muted-foreground">
                Evidence
              </p>
              <div className="flex flex-wrap gap-2">
                {v.evidence.map((e, i) => (
                  <Pill key={i}>
                    {e.kind}
                    {e.lat != null ? ` · ${e.lat.toFixed(3)}, ${e.lng?.toFixed(3)}` : ""}
                  </Pill>
                ))}
              </div>
            </div>
          )}
        </CardContent>
      </Card>
    </div>
  );
}

// ── Network ──
export function NetworkTab({ net }: { net: C360Network }) {
  return (
    <div className="grid gap-4 lg:grid-cols-3">
      <Card>
        <CardHeader>
          <CardTitle>Family</CardTitle>
        </CardHeader>
        <CardContent>
          {net.familyMembers.length ? (
            <ul className="divide-y text-sm">
              {net.familyMembers.map((m, i) => (
                <li key={i} className="flex items-center justify-between py-2">
                  <span>{m.phone}</span>
                  <span className="text-muted-foreground">{m.relationship || "—"}</span>
                  <StatusBadge status={m.status} />
                </li>
              ))}
            </ul>
          ) : (
            <p className="text-sm text-muted-foreground">No family members.</p>
          )}
        </CardContent>
      </Card>
      <Card>
        <CardHeader>
          <CardTitle>Same Household</CardTitle>
        </CardHeader>
        <CardContent>
          {net.sameHousehold.length ? (
            <ul className="divide-y text-sm">
              {net.sameHousehold.map((u) => (
                <li key={u.id} className="flex items-center justify-between py-2">
                  <span>{u.name || "—"}</span>
                  <span className="text-muted-foreground">{u.phone}</span>
                </li>
              ))}
            </ul>
          ) : (
            <p className="text-sm text-muted-foreground">None found.</p>
          )}
        </CardContent>
      </Card>
      <Card>
        <CardHeader>
          <CardTitle>Referrals</CardTitle>
        </CardHeader>
        <CardContent>
          {net.referrals.length ? (
            <ul className="divide-y text-sm">
              {net.referrals.map((r) => (
                <li key={r.id} className="flex items-center justify-between py-2">
                  <span className="font-mono text-xs">{r.code}</span>
                  <StatusBadge status={r.status} />
                </li>
              ))}
            </ul>
          ) : (
            <p className="text-sm text-muted-foreground">No referrals.</p>
          )}
        </CardContent>
      </Card>
    </div>
  );
}

// ── Support ──
export function SupportTab({ s }: { s: C360Support }) {
  return (
    <Card>
      <CardHeader>
        <CardTitle>Support History</CardTitle>
      </CardHeader>
      <CardContent className="grid grid-cols-2 gap-4 sm:grid-cols-3">
        <Field label="Tickets">{s.tickets}</Field>
        <Field label="Open">{s.open}</Field>
        <Field label="Complaints">{s.complaints}</Field>
        <Field label="Escalations">{s.escalations}</Field>
        <Field label="Returns">{s.returns}</Field>
        <Field label="Refunds">{inr(s.refunds)}</Field>
      </CardContent>
    </Card>
  );
}

// ── Timeline ──
export function TimelineTab({ events }: { events: C360TimelineEvent[] }) {
  if (!events.length) return <EmptyState title="No activity yet" />;
  return (
    <Card>
      <CardContent className="pt-6">
        <ol className="relative space-y-4 border-l pl-6">
          {events.map((e, i) => (
            <li key={i} className="relative">
              <span className="absolute -left-[1.65rem] top-1 size-3 rounded-full border-2 border-card bg-primary" />
              <div className="flex items-center justify-between gap-2">
                <p className="text-sm font-medium">{e.label}</p>
                {e.amount ? <span className="text-sm">{inr(e.amount)}</span> : null}
              </div>
              <p className="text-xs text-muted-foreground">{fmtDate(e.at, true)}</p>
            </li>
          ))}
        </ol>
      </CardContent>
    </Card>
  );
}

// ── Notes ──
export function NotesTab({
  notes,
  onAdd,
  adding,
}: {
  notes: Record<string, C360Note[]>;
  onAdd: (category: string, body: string) => void;
  adding: boolean;
}) {
  const cats = ["admin", "collection", "delivery", "verification"];
  return (
    <div className="grid gap-4 lg:grid-cols-2">
      {cats.map((cat) => (
        <NoteColumn key={cat} category={cat} notes={notes[cat] ?? []} onAdd={onAdd} adding={adding} />
      ))}
    </div>
  );
}

function NoteColumn({
  category,
  notes,
  onAdd,
  adding,
}: {
  category: string;
  notes: C360Note[];
  onAdd: (category: string, body: string) => void;
  adding: boolean;
}) {
  const [text, setText] = React.useState("");
  return (
    <Card>
      <CardHeader>
        <CardTitle>{titleize(category)} Notes</CardTitle>
      </CardHeader>
      <CardContent className="space-y-3">
        {notes.length ? (
          <ul className="space-y-2 text-sm">
            {notes.map((n) => (
              <li key={n.id} className="rounded-md bg-muted/50 p-2">
                <p>{n.body}</p>
                <p className="mt-1 text-xs text-muted-foreground">
                  {n.author ?? "System"} · {fmtDate(n.at, true)}
                </p>
              </li>
            ))}
          </ul>
        ) : (
          <p className="text-sm text-muted-foreground">No notes.</p>
        )}
        <div className="flex gap-2">
          <input
            className="flex-1 rounded-md border bg-background px-2 py-1 text-sm"
            placeholder="Add a note…"
            value={text}
            onChange={(e) => setText(e.target.value)}
          />
          <button
            className="rounded-md bg-primary px-3 py-1 text-sm font-medium text-primary-foreground disabled:opacity-50"
            disabled={adding || !text.trim()}
            onClick={() => {
              onAdd(category, text.trim());
              setText("");
            }}
          >
            Add
          </button>
        </div>
      </CardContent>
    </Card>
  );
}
