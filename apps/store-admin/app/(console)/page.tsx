"use client";

import { useQuery } from "@tanstack/react-query";
import {
  AlertTriangle,
  BadgeIndianRupee,
  Boxes,
  CalendarClock,
  CreditCard,
  PackageCheck,
  ShoppingCart,
  Truck,
  Users,
  Wallet,
} from "lucide-react";
import Link from "next/link";
import { api } from "@/lib/api/client";
import { useStore } from "@/lib/store/store-context";
import { PageHeader } from "@/components/page-header";
import { StatCard } from "@/components/stat-card";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";
import { AreaTrend, BarTrend } from "@/components/trend-chart";
import { LoadingState, ErrorState, EmptyState } from "@/components/states";
import { ProductLink } from "@/components/product-link";
import { inr, fmtDate, compact } from "@/lib/utils";

interface Dashboard {
  kpis: {
    todaySales: number;
    todayRevenue: number;
    todayOrders: number;
    pendingOrders: number;
    deliveredToday: number;
    codPending: number;
    codPendingCount: number;
    outstandingCredit: number;
    creditOrders: number;
    activeCustomers: number;
    lowStockItems: number;
    expiringItems: number;
    stockValue: number;
    monthlyRevenue: number;
  };
  salesTrend: { date: string; value: number }[];
  ordersTrend: { date: string; value: number }[];
  /** Grouped by OrderItem.name server-side, so these rows carry no product id. */
  topProducts: { name: string; quantity: number; revenue: number }[];
  topCustomers: { customer: string; spend: number; orders: number }[];
  lowStockAlerts: { productId: string; name: string; available: number; reorderLevel: number }[];
  expiryAlerts: { productId: string; name: string; batchNo: string; quantity: number; expiryDate: string; daysLeft: number; expired: boolean }[];
  staffActivity: { actor: string; action: string; at: string }[];
}

export default function DashboardPage() {
  const { me } = useStore();
  const { data, isLoading, error, refetch } = useQuery({
    queryKey: ["store", "dashboard"],
    queryFn: () => api.get<Dashboard>("/store/dashboard"),
    refetchInterval: 60_000,
  });

  if (isLoading) return <LoadingState label="Loading your store…" />;
  if (error || !data) return <ErrorState message="Couldn't load the dashboard." onRetry={() => refetch()} />;

  const k = data.kpis;
  const chartData = data.salesTrend.map((s, i) => ({
    date: s.date.slice(5),
    sales: s.value,
    orders: data.ordersTrend[i]?.value ?? 0,
  }));

  return (
    <div className="space-y-6">
      <PageHeader
        title={`Good day, ${me?.user.name?.split(" ")[0] || "there"}`}
        description={`${me?.store.name} · today's control center`}
      />

      {/* Primary KPIs */}
      <div className="grid grid-cols-2 gap-3 lg:grid-cols-4">
        <StatCard label="Today's Revenue" value={inr(k.todayRevenue)} icon={<BadgeIndianRupee />} accent="teal"
          hint={`${k.todayOrders} order${k.todayOrders === 1 ? "" : "s"} today`} />
        <StatCard label="Pending Orders" value={k.pendingOrders} icon={<ShoppingCart />} accent="gold"
          hint="Awaiting pack / dispatch" />
        <StatCard label="Delivered Today" value={k.deliveredToday} icon={<PackageCheck />} accent="green" />
        <StatCard label="Monthly Revenue" value={inr(k.monthlyRevenue)} icon={<Wallet />} accent="teal" />
        <StatCard label="COD Pending" value={inr(k.codPending)} icon={<Truck />} accent="slate"
          hint={`${k.codPendingCount} order${k.codPendingCount === 1 ? "" : "s"}`} />
        <StatCard label="Outstanding Credit" value={inr(k.outstandingCredit)} icon={<CreditCard />} accent="red"
          hint={`${k.creditOrders} credit order${k.creditOrders === 1 ? "" : "s"}`} />
        <StatCard label="Active Customers" value={k.activeCustomers} icon={<Users />} accent="green"
          hint="Last 30 days" />
        <StatCard label="Stock Value" value={inr(k.stockValue)} icon={<Boxes />} accent="slate" />
      </div>

      {/* Trends */}
      <div className="grid gap-4 lg:grid-cols-2">
        <Card>
          <CardHeader><CardTitle className="text-sm">Sales — last 14 days</CardTitle></CardHeader>
          <CardContent className="pt-0">
            <AreaTrend data={chartData} xKey="date" series={[{ key: "sales", label: "Sales (₹)" }]} />
          </CardContent>
        </Card>
        <Card>
          <CardHeader><CardTitle className="text-sm">Orders — last 14 days</CardTitle></CardHeader>
          <CardContent className="pt-0">
            <BarTrend data={chartData} xKey="date" barKey="orders" label="Orders" />
          </CardContent>
        </Card>
      </div>

      {/* Alerts row */}
      <div className="grid gap-4 lg:grid-cols-2">
        <Card>
          <CardHeader className="flex-row items-center justify-between">
            <CardTitle className="flex items-center gap-2 text-sm">
              <AlertTriangle className="size-4 text-warning" /> Low Stock ({k.lowStockItems})
            </CardTitle>
            <Link href="/inventory" className="text-xs text-primary hover:underline">View inventory</Link>
          </CardHeader>
          <CardContent className="pt-0">
            {data.lowStockAlerts.length === 0 ? (
              <EmptyState title="All stocked up" description="No items below reorder level." />
            ) : (
              <ul className="divide-y text-sm">
                {data.lowStockAlerts.map((r, i) => (
                  <li key={i} className="flex items-center justify-between py-2">
                    <ProductLink id={r.productId} name={r.name} className="truncate" />
                    <span className="text-muted-foreground">
                      <span className="font-semibold text-destructive">{r.available}</span> / {r.reorderLevel}
                    </span>
                  </li>
                ))}
              </ul>
            )}
          </CardContent>
        </Card>

        <Card>
          <CardHeader className="flex-row items-center justify-between">
            <CardTitle className="flex items-center gap-2 text-sm">
              <CalendarClock className="size-4 text-warning" /> Expiring Soon ({k.expiringItems})
            </CardTitle>
            <Link href="/inventory" className="text-xs text-primary hover:underline">Manage</Link>
          </CardHeader>
          <CardContent className="pt-0">
            {data.expiryAlerts.length === 0 ? (
              <EmptyState title="Nothing expiring" description="No batches within 30 days." />
            ) : (
              <ul className="divide-y text-sm">
                {data.expiryAlerts.map((r, i) => (
                  <li key={i} className="flex items-center justify-between py-2">
                    <span className="truncate">
                      <ProductLink id={r.productId} name={r.name} />{" "}
                      <span className="text-xs text-muted-foreground">#{r.batchNo}</span>
                    </span>
                    <span className={r.expired ? "text-destructive font-medium" : "text-muted-foreground"}>
                      {r.expired ? "Expired" : `${r.daysLeft}d`} · {fmtDate(r.expiryDate)}
                    </span>
                  </li>
                ))}
              </ul>
            )}
          </CardContent>
        </Card>
      </div>

      {/* Top products / customers / activity */}
      <div className="grid gap-4 lg:grid-cols-3">
        <Card>
          <CardHeader><CardTitle className="text-sm">Top Products</CardTitle></CardHeader>
          <CardContent className="pt-0">
            {data.topProducts.length === 0 ? <EmptyState title="No sales yet" /> : (
              <ul className="space-y-2 text-sm">
                {data.topProducts.map((p, i) => (
                  <li key={i} className="flex items-center justify-between gap-2">
                    {/* Aggregated by name on the server — no product id to link to. */}
                    <ProductLink name={p.name} className="truncate" />
                    <span className="shrink-0 text-muted-foreground">{compact(p.quantity)} · {inr(p.revenue)}</span>
                  </li>
                ))}
              </ul>
            )}
          </CardContent>
        </Card>
        <Card>
          <CardHeader><CardTitle className="text-sm">Top Customers</CardTitle></CardHeader>
          <CardContent className="pt-0">
            {data.topCustomers.length === 0 ? <EmptyState title="No customers yet" /> : (
              <ul className="space-y-2 text-sm">
                {data.topCustomers.map((c, i) => (
                  <li key={i} className="flex items-center justify-between gap-2">
                    <span className="truncate">{c.customer}</span>
                    <span className="shrink-0 text-muted-foreground">{inr(c.spend)} · {c.orders}</span>
                  </li>
                ))}
              </ul>
            )}
          </CardContent>
        </Card>
        <Card>
          <CardHeader><CardTitle className="text-sm">Staff Activity</CardTitle></CardHeader>
          <CardContent className="pt-0">
            {data.staffActivity.length === 0 ? <EmptyState title="No recent activity" /> : (
              <ul className="space-y-2 text-sm">
                {data.staffActivity.map((a, i) => (
                  <li key={i} className="flex items-start justify-between gap-2">
                    <span className="truncate"><span className="font-medium">{a.actor}</span> · {a.action}</span>
                    <span className="shrink-0 text-xs text-muted-foreground">{fmtDate(a.at, true)}</span>
                  </li>
                ))}
              </ul>
            )}
          </CardContent>
        </Card>
      </div>
    </div>
  );
}
