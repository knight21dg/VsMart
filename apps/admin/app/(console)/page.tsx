"use client";

import { useQuery } from "@tanstack/react-query";
import {
  Banknote,
  CreditCard,
  IdCard,
  PackageCheck,
  ShoppingCart,
  TriangleAlert,
  Users,
  Wallet,
} from "lucide-react";
import { api } from "@/lib/api/client";
import { PageHeader } from "@/components/page-header";
import { StatCard } from "@/components/stat-card";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";
import { AreaTrend, BarTrend } from "@/components/trend-chart";
import { ErrorState, LoadingState } from "@/components/states";
import { compact, inr } from "@/lib/utils";

interface Dashboard {
  ordersToday: number;
  gmvToday: number;
  activeCreditOutstanding: number;
  overdueStatements: number;
  customers: number;
  agents: number;
}
interface Overview {
  periodDays: number;
  orders: number;
  gmv: number;
  revenue: number;
  platformFeeCollected: number;
  averageOrderValue: number;
  newCustomers: number;
  creditOutstanding: number;
  overdueStatements: number;
  repaymentsCollected: number;
}
interface SalesPoint {
  date: string;
  orders: number;
  gmv: number;
}
interface TopProduct {
  productId: string;
  name: string;
  units: number;
  revenue: number;
}
interface ZoneStat {
  zone: string;
  orders: number;
  gmv: number;
}
interface LiveOps {
  summary: {
    agentsOnDuty: number;
    totalAgents: number;
    agentsOnline: number;
    activeDeliveries: number;
    activeCollections: number;
    ordersOutForDelivery: number;
  };
  agents: {
    id: string;
    name: string;
    onDuty: boolean;
    online: boolean;
    lastSeenAt: string | null;
    activeDeliveries: number;
  }[];
}

export default function DashboardPage() {
  const dash = useQuery({ queryKey: ["admin", "dashboard"], queryFn: () => api.get<Dashboard>("/admin/dashboard") });
  const overview = useQuery({
    queryKey: ["admin", "overview", 30],
    queryFn: () => api.get<Overview>("/admin/analytics/overview", { days: 30 }),
  });
  const sales = useQuery({
    queryKey: ["admin", "sales", 30],
    queryFn: () => api.get<SalesPoint[]>("/admin/analytics/sales", { days: 30 }),
  });
  const top = useQuery({
    queryKey: ["admin", "top-products"],
    queryFn: () => api.get<TopProduct[]>("/admin/analytics/top-products"),
  });
  const zones = useQuery({
    queryKey: ["admin", "zone-sales"],
    queryFn: () => api.get<ZoneStat[]>("/admin/analytics/zones"),
  });
  const live = useQuery({
    queryKey: ["admin", "ops", "live"],
    queryFn: () => api.get<LiveOps>("/admin/ops/live"),
    refetchInterval: 15000, // live: re-poll every 15s
  });

  const d = dash.data;
  const o = overview.data;
  const loading = dash.isLoading;

  const salesData = (sales.data ?? []).map((p) => ({ ...p, label: p.date.slice(5) }));
  const topData = (top.data ?? []).map((p) => ({ ...p, label: p.name.length > 14 ? p.name.slice(0, 14) + "…" : p.name }));

  return (
    <>
      <PageHeader title="Executive Dashboard" description="Real-time business visibility across VS Mart operations." />

      {/* KPI grid */}
      <div className="grid grid-cols-2 gap-4 lg:grid-cols-4">
        <StatCard label="Revenue Today" value={inr(d?.gmvToday)} icon={<Banknote />} accent="green" loading={loading} />
        <StatCard label="Orders Today" value={d?.ordersToday ?? 0} icon={<ShoppingCart />} accent="teal" loading={loading} />
        <StatCard
          label="Outstanding Credit"
          value={inr(d?.activeCreditOutstanding)}
          icon={<CreditCard />}
          accent="gold"
          loading={loading}
        />
        <StatCard
          label="Overdue Statements"
          value={d?.overdueStatements ?? 0}
          icon={<TriangleAlert />}
          accent={d?.overdueStatements ? "red" : "slate"}
          loading={loading}
        />
        <StatCard label="Active Customers" value={compact(d?.customers)} icon={<Users />} accent="teal" loading={loading} />
        <StatCard label="Agents" value={d?.agents ?? 0} icon={<IdCard />} accent="slate" loading={loading} />
        <StatCard
          label="Repayments (30d)"
          value={inr(o?.repaymentsCollected)}
          icon={<Wallet />}
          accent="green"
          loading={overview.isLoading}
        />
        <StatCard
          label="Avg Order Value"
          value={inr(o?.averageOrderValue)}
          icon={<PackageCheck />}
          accent="slate"
          loading={overview.isLoading}
        />
      </div>

      {/* Charts */}
      <div className="grid gap-4 lg:grid-cols-3">
        <Card className="lg:col-span-2">
          <CardHeader>
            <CardTitle>Revenue & Orders — last 30 days</CardTitle>
          </CardHeader>
          <CardContent>
            {sales.isLoading ? (
              <LoadingState />
            ) : sales.isError ? (
              <ErrorState onRetry={() => sales.refetch()} />
            ) : (
              <AreaTrend
                data={salesData}
                xKey="label"
                series={[
                  { key: "gmv", label: "GMV", color: "var(--color-chart-1)" },
                  { key: "orders", label: "Orders", color: "var(--color-chart-2)" },
                ]}
              />
            )}
          </CardContent>
        </Card>

        <Card>
          <CardHeader>
            <CardTitle>Sales by Zone</CardTitle>
          </CardHeader>
          <CardContent>
            {zones.isLoading ? (
              <LoadingState />
            ) : (zones.data ?? []).length === 0 ? (
              <p className="py-10 text-center text-sm text-muted-foreground">No zone sales yet.</p>
            ) : (
              <div className="space-y-3 pt-2">
                {(zones.data ?? []).map((z) => (
                  <div key={z.zone}>
                    <div className="mb-1 flex items-center justify-between text-sm">
                      <span className="font-medium">{z.zone}</span>
                      <span className="text-muted-foreground">{inr(z.gmv)}</span>
                    </div>
                    <div className="h-2 overflow-hidden rounded-full bg-muted">
                      <div
                        className="h-full rounded-full bg-primary"
                        style={{
                          width: `${Math.min(
                            100,
                            (z.gmv / Math.max(...(zones.data ?? []).map((x) => x.gmv), 1)) * 100
                          )}%`,
                        }}
                      />
                    </div>
                    <p className="mt-0.5 text-xs text-muted-foreground">{z.orders} orders</p>
                  </div>
                ))}
              </div>
            )}
          </CardContent>
        </Card>
      </div>

      <div className="grid gap-4 lg:grid-cols-3">
        <Card className="lg:col-span-2">
          <CardHeader>
            <CardTitle>Top Products</CardTitle>
          </CardHeader>
          <CardContent>
            {top.isLoading ? (
              <LoadingState />
            ) : topData.length === 0 ? (
              <p className="py-10 text-center text-sm text-muted-foreground">No product sales yet.</p>
            ) : (
              <BarTrend data={topData} xKey="label" barKey="revenue" label="Revenue" />
            )}
          </CardContent>
        </Card>

        <Card>
          <CardHeader className="flex-row items-center justify-between">
            <CardTitle>Live Operations</CardTitle>
            {live.data && (
              <span className="flex items-center gap-1.5 text-xs text-muted-foreground">
                <span className="size-2 animate-pulse rounded-full bg-[var(--color-success)]" /> Live
              </span>
            )}
          </CardHeader>
          <CardContent>
            {live.isLoading ? (
              <LoadingState />
            ) : live.isError || !live.data ? (
              <ErrorState message="Couldn't load live operations." onRetry={() => live.refetch()} />
            ) : (
              <LiveOpsWidget live={live.data} />
            )}
          </CardContent>
        </Card>
      </div>
    </>
  );
}

function LiveOpsWidget({ live }: { live: LiveOps }) {
  const s = live.summary;
  const active = live.agents.filter((a) => a.onDuty || a.online).slice(0, 8);
  const stat = (label: string, value: number | string) => (
    <div className="rounded-lg bg-muted/50 p-2.5">
      <p className="text-xs text-muted-foreground">{label}</p>
      <p className="text-lg font-bold tabular-nums">{value}</p>
    </div>
  );
  return (
    <div className="space-y-4">
      <div className="grid grid-cols-3 gap-2">
        {stat("On Duty", `${s.agentsOnDuty}/${s.totalAgents}`)}
        {stat("Online", s.agentsOnline)}
        {stat("Out for Delivery", s.ordersOutForDelivery)}
        {stat("Active Deliveries", s.activeDeliveries)}
        {stat("Active Collections", s.activeCollections)}
        {stat("Agents", s.totalAgents)}
      </div>
      <div>
        <p className="mb-2 text-xs font-medium uppercase tracking-wide text-muted-foreground">
          Agents on the field
        </p>
        {active.length === 0 ? (
          <p className="py-4 text-center text-sm text-muted-foreground">No agents on duty right now.</p>
        ) : (
          <ul className="divide-y text-sm">
            {active.map((a) => (
              <li key={a.id} className="flex items-center justify-between py-2">
                <span className="flex items-center gap-2">
                  <span
                    className={
                      "size-2 rounded-full " +
                      (a.online ? "bg-[var(--color-success)]" : a.onDuty ? "bg-[var(--color-warning)]" : "bg-muted-foreground")
                    }
                  />
                  <span className="font-medium">{a.name}</span>
                </span>
                <span className="text-xs text-muted-foreground">
                  {a.activeDeliveries > 0 ? `${a.activeDeliveries} active` : a.online ? "online" : "on duty"}
                </span>
              </li>
            ))}
          </ul>
        )}
      </div>
    </div>
  );
}
