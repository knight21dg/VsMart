"use client";

import { useRouter } from "next/navigation";
import { useQuery } from "@tanstack/react-query";
import {
  AlertTriangle,
  Banknote,
  Boxes,
  Clock,
  Layers,
  PackageX,
  Recycle,
  Skull,
  Timer,
  TrendingDown,
  TrendingUp,
  Truck,
} from "lucide-react";
import { api } from "@/lib/api/client";
import { InvNav } from "@/components/inventory/inv-nav";
import { PageHeader } from "@/components/page-header";
import { ProductLink } from "@/components/product-link";
import { StatCard } from "@/components/stat-card";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";
import { Tabs, TabsContent, TabsList, TabsTrigger } from "@/components/ui/tabs";
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from "@/components/ui/table";
import { Badge } from "@/components/ui/badge";
import { LoadingState } from "@/components/states";
import { compact, fmtDate, inr } from "@/lib/utils";
import type { DeadStockItem, InvOverview, Mover, StoreRollup } from "@/lib/inventory";

function HealthDot({ score }: { score: number }) {
  const color = score >= 90 ? "bg-[var(--color-success)]" : score >= 75 ? "bg-[var(--color-warning)]" : "bg-destructive";
  return <span className={`inline-block size-2 rounded-full ${color}`} />;
}

export default function InventoryCommandCenter() {
  const router = useRouter();
  const overview = useQuery({ queryKey: ["inv", "overview"], queryFn: () => api.get<InvOverview>("/inventory/overview") });
  const stores = useQuery({ queryKey: ["inv", "stores"], queryFn: () => api.get<StoreRollup[]>("/inventory/stores") });
  const movers = useQuery({ queryKey: ["inv", "movers"], queryFn: () => api.get<{ fast: Mover[]; slow: Mover[] }>("/inventory/movers", { days: 30, limit: 8 }) });
  const dead = useQuery({ queryKey: ["inv", "dead"], queryFn: () => api.get<{ items: DeadStockItem[] }>("/inventory/dead-stock", { days: 90 }) });

  const o = overview.data;
  const ld = overview.isLoading;

  const alerts = o
    ? [
        { label: "Out of stock", value: o.outOfStock, tone: "red", icon: <PackageX /> },
        { label: "Dead stock (90d+)", value: o.deadStockCount, tone: "red", icon: <Skull /> },
        { label: "Low stock", value: o.lowStock, tone: "gold", icon: <AlertTriangle /> },
        { label: "Near expiry", value: inr(o.nearExpiryValue), tone: "gold", icon: <Timer /> },
        { label: "Pending transfers", value: o.pendingTransfers, tone: "slate", icon: <Truck /> },
        { label: "Pending POs", value: o.pendingPurchaseOrders, tone: "slate", icon: <Clock /> },
      ]
    : [];

  return (
    <>
      <PageHeader title="Inventory Command Center" description="Network-wide stock health, intelligence and control." />
      <InvNav />

      {/* KPI grid */}
      <div className="grid grid-cols-2 gap-4 lg:grid-cols-4">
        <StatCard label="Inventory Value" value={inr(o?.totalInventoryValue)} icon={<Banknote />} accent="green" loading={ld} />
        <StatCard label="Total SKUs" value={compact(o?.totalSkus)} icon={<Layers />} accent="teal" loading={ld} />
        <StatCard label="Total Units" value={compact(o?.totalUnits)} icon={<Boxes />} accent="teal" loading={ld} />
        <StatCard label="Out of Stock" value={o?.outOfStock ?? 0} icon={<PackageX />} accent={o?.outOfStock ? "red" : "slate"} loading={ld} />
        <StatCard label="Dead Stock Value" value={inr(o?.deadStockValue)} icon={<Skull />} accent="red" loading={ld} />
        <StatCard label="Near-Expiry Value" value={inr(o?.nearExpiryValue)} icon={<Timer />} accent="gold" loading={ld} />
        <StatCard label="Damaged Value" value={inr(o?.damagedValue)} icon={<Recycle />} accent="gold" loading={ld} />
        <StatCard label="Consumed Today" value={compact(o?.consumptionToday)} icon={<TrendingDown />} accent="slate" loading={ld} hint="units sold today" />
      </div>

      {/* Alerts */}
      <Card>
        <CardHeader><CardTitle>Alerts Center</CardTitle></CardHeader>
        <CardContent>
          <div className="grid grid-cols-2 gap-3 sm:grid-cols-3 lg:grid-cols-6">
            {alerts.map((a) => (
              <div key={a.label} className="rounded-lg border p-3">
                <div className={`mb-1.5 flex size-7 items-center justify-center rounded-md [&_svg]:size-4 ${a.tone === "red" ? "bg-destructive/10 text-destructive" : a.tone === "gold" ? "bg-[color-mix(in_oklab,var(--color-warning)_18%,transparent)] text-[var(--color-warning)]" : "bg-muted text-muted-foreground"}`}>{a.icon}</div>
                <p className="text-lg font-bold">{a.value}</p>
                <p className="text-xs text-muted-foreground">{a.label}</p>
              </div>
            ))}
          </div>
        </CardContent>
      </Card>

      {/* Store comparison */}
      <Card>
        <CardHeader><CardTitle>Store Health</CardTitle></CardHeader>
        <CardContent className="p-0">
          {stores.isLoading ? (
            <LoadingState />
          ) : (
            <Table>
              <TableHeader>
                <TableRow className="hover:bg-transparent">
                  <TableHead>Store</TableHead>
                  <TableHead>Inventory Value</TableHead>
                  <TableHead>SKUs</TableHead>
                  <TableHead>OOS</TableHead>
                  <TableHead>Low</TableHead>
                  <TableHead>Fill Rate</TableHead>
                  <TableHead>Health</TableHead>
                  <TableHead>Sales Today</TableHead>
                </TableRow>
              </TableHeader>
              <TableBody>
                {(stores.data ?? []).map((s) => (
                  <TableRow key={s.warehouseId} className="cursor-pointer" onClick={() => router.push(`/inventory/store/${s.warehouseId}`)}>
                    <TableCell className="font-medium">{s.storeName}</TableCell>
                    <TableCell>{inr(s.inventoryValue)}</TableCell>
                    <TableCell>{s.skuCount}</TableCell>
                    <TableCell>{s.outOfStock > 0 ? <Badge variant="destructive">{s.outOfStock}</Badge> : "0"}</TableCell>
                    <TableCell>{s.lowStock > 0 ? <Badge variant="warning">{s.lowStock}</Badge> : "0"}</TableCell>
                    <TableCell>{s.fillRate}%</TableCell>
                    <TableCell><span className="flex items-center gap-1.5"><HealthDot score={s.healthScore} />{s.healthScore}</span></TableCell>
                    <TableCell>{s.salesToday}</TableCell>
                  </TableRow>
                ))}
                {(stores.data ?? []).length === 0 && (
                  <TableRow><TableCell colSpan={8} className="py-8 text-center text-sm text-muted-foreground">No stores with a warehouse assigned.</TableCell></TableRow>
                )}
              </TableBody>
            </Table>
          )}
        </CardContent>
      </Card>

      {/* Intelligence: movers / dead stock */}
      <Card>
        <CardHeader><CardTitle>Movement Intelligence</CardTitle></CardHeader>
        <CardContent>
          <Tabs defaultValue="fast">
            <TabsList>
              <TabsTrigger value="fast"><TrendingUp className="mr-1 size-3.5" /> Fast Movers</TabsTrigger>
              <TabsTrigger value="slow"><TrendingDown className="mr-1 size-3.5" /> Slow Movers</TabsTrigger>
              <TabsTrigger value="dead"><Skull className="mr-1 size-3.5" /> Dead Stock</TabsTrigger>
            </TabsList>
            <TabsContent value="fast"><MoverTable rows={movers.data?.fast ?? []} loading={movers.isLoading} onOpen={(id) => router.push(`/inventory/product/${id}`)} /></TabsContent>
            <TabsContent value="slow"><MoverTable rows={movers.data?.slow ?? []} loading={movers.isLoading} onOpen={(id) => router.push(`/inventory/product/${id}`)} /></TabsContent>
            <TabsContent value="dead"><DeadTable rows={dead.data?.items ?? []} loading={dead.isLoading} onOpen={(id) => router.push(`/inventory/product/${id}`)} /></TabsContent>
          </Tabs>
        </CardContent>
      </Card>
    </>
  );
}

function MoverTable({ rows, loading, onOpen }: { rows: Mover[]; loading: boolean; onOpen: (id: string) => void }) {
  if (loading) return <LoadingState />;
  if (rows.length === 0) return <p className="py-8 text-center text-sm text-muted-foreground">No movement in this window.</p>;
  return (
    <Table>
      <TableHeader>
        <TableRow className="hover:bg-transparent">
          <TableHead>Product</TableHead><TableHead>Units Sold</TableHead><TableHead>Revenue</TableHead><TableHead>On Hand</TableHead><TableHead>Value</TableHead><TableHead>Last Sale</TableHead>
        </TableRow>
      </TableHeader>
      <TableBody>
        {rows.map((r) => (
          <TableRow key={r.productId} className="cursor-pointer" onClick={() => onOpen(r.productId)}>
            <TableCell className="font-medium">
              <ProductLink id={r.productId} name={r.name} archived={r.archived} />
            </TableCell>
            <TableCell className="tabular-nums">{r.unitsSold}</TableCell>
            <TableCell>{inr(r.revenue)}</TableCell>
            <TableCell className="tabular-nums">{r.onHand}</TableCell>
            <TableCell>{inr(r.value)}</TableCell>
            <TableCell className="text-muted-foreground">{r.lastSale ? fmtDate(r.lastSale) : "—"}</TableCell>
          </TableRow>
        ))}
      </TableBody>
    </Table>
  );
}

function DeadTable({ rows, loading, onOpen }: { rows: DeadStockItem[]; loading: boolean; onOpen: (id: string) => void }) {
  if (loading) return <LoadingState />;
  if (rows.length === 0) return <p className="py-8 text-center text-sm text-muted-foreground">No dead stock — everything is moving.</p>;
  return (
    <Table>
      <TableHeader>
        <TableRow className="hover:bg-transparent">
          <TableHead>Product</TableHead><TableHead>Qty</TableHead><TableHead>Locked Value</TableHead><TableHead>Last Sale</TableHead><TableHead>Days Idle</TableHead>
        </TableRow>
      </TableHeader>
      <TableBody>
        {rows.map((r) => (
          <TableRow key={r.productId} className="cursor-pointer" onClick={() => onOpen(r.productId)}>
            <TableCell className="font-medium">
              <ProductLink id={r.productId} name={r.name} archived={r.archived} />
            </TableCell>
            <TableCell className="tabular-nums">{r.quantity}</TableCell>
            <TableCell className="font-medium text-destructive">{inr(r.value)}</TableCell>
            <TableCell className="text-muted-foreground">{r.lastSale ? fmtDate(r.lastSale) : "Never sold"}</TableCell>
            <TableCell>{r.daysSinceSale ?? "—"}</TableCell>
          </TableRow>
        ))}
      </TableBody>
    </Table>
  );
}
