"use client";

import * as React from "react";
import { useRouter } from "next/navigation";
import { useQuery } from "@tanstack/react-query";
import { type ColumnDef } from "@tanstack/react-table";
import { Info, ShoppingCart } from "lucide-react";
import { api } from "@/lib/api/client";
import { InvNav } from "@/components/inventory/inv-nav";
import { PageHeader } from "@/components/page-header";
import { DataTable } from "@/components/data-table";
import { PODialog } from "@/components/po-dialog";
import { Card } from "@/components/ui/card";
import { Button } from "@/components/ui/button";
import { Badge } from "@/components/ui/badge";
import { ProductLink } from "@/components/product-link";
import type { ReorderItem } from "@/lib/inventory";

export default function ReorderPage() {
  const router = useRouter();
  // The row that's being turned into a purchase order. This page told you what
  // to buy and gave you no way to buy it — the only route to stock was a
  // free-text adjustment with no supplier or cost.
  const [ordering, setOrdering] = React.useState<ReorderItem | null>(null);
  const query = useQuery({ queryKey: ["inv", "reorder"], queryFn: () => api.get<{ leadTimeDays: number; items: ReorderItem[] }>("/inventory/reorder") });

  const columns: ColumnDef<ReorderItem, unknown>[] = [
    { accessorKey: "name", header: "Product", cell: ({ row }) => <ProductLink id={row.original.productId} name={row.original.name} className="font-medium" /> },
    { accessorKey: "warehouse", header: "Store / WH" },
    { accessorKey: "available", header: "Available", cell: ({ row }) => <span className="tabular-nums">{row.original.available}</span> },
    { accessorKey: "avgDailySales", header: "Avg/day", cell: ({ row }) => <span className="tabular-nums">{row.original.avgDailySales}</span> },
    {
      accessorKey: "daysRemaining",
      header: "Days Left",
      cell: ({ row }) => {
        const d = row.original.daysRemaining;
        if (d == null) return <span className="text-muted-foreground">∞</span>;
        return <Badge variant={d <= 3 ? "destructive" : d <= 7 ? "warning" : "secondary"}>{d}d</Badge>;
      },
    },
    { accessorKey: "safetyStock", header: "Safety", cell: ({ row }) => <span className="tabular-nums">{row.original.safetyStock}</span> },
    { accessorKey: "suggestedQty", header: "Suggested Order", cell: ({ row }) => <span className="font-semibold text-primary tabular-nums">{row.original.suggestedQty}</span> },
    {
      id: "actions",
      header: "",
      cell: ({ row }) => (
        <Button
          size="sm"
          variant="outline"
          onClick={(e) => { e.stopPropagation(); setOrdering(row.original); }}
        >
          <ShoppingCart className="size-3.5" /> Order
        </Button>
      ),
    },
  ];

  return (
    <>
      <PageHeader title="Reorder Center" description="Replenishment recommendations from sales velocity." />
      <InvNav />
      <Card className="flex items-start gap-3 border-primary/20 bg-primary/5 p-4 text-sm">
        <Info className="mt-0.5 size-4 shrink-0 text-primary" />
        <p className="text-muted-foreground">
          Suggested order = <span className="font-medium text-foreground">avg daily sales × lead time + safety stock − available</span>.
          Lead time is assumed at <span className="font-medium text-foreground">{query.data?.leadTimeDays ?? 5} days</span> (supplier lead time isn&apos;t tracked in the backend yet).
        </p>
      </Card>
      <DataTable
        columns={columns}
        data={query.data?.items ?? []}
        loading={query.isLoading}
        error={query.isError ? "Failed to load recommendations." : null}
        onRetry={() => query.refetch()}
        onRowClick={(r) => router.push(`/inventory/product/${r.productId}`)}
        emptyMessage="Nothing needs reordering — all stock is healthy."
      />
      {ordering && (
        <PODialog
          prefill={[{
            productId: ordering.productId,
            name: ordering.name,
            quantity: String(ordering.suggestedQty),
            unitCost: "",
          }]}
          prefillWarehouse={ordering.warehouseId}
          onClose={() => setOrdering(null)}
        />
      )}
    </>
  );
}
