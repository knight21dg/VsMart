"use client";

import * as React from "react";
import { useRouter } from "next/navigation";
import { useQuery } from "@tanstack/react-query";
import { type ColumnDef } from "@tanstack/react-table";
import { Pencil, Plus, Trash2 } from "lucide-react";
import { toast } from "sonner";
import { api } from "@/lib/api/client";
import { useApiMutation } from "@/lib/api/hooks";
import { useAuth } from "@/lib/auth/auth-context";
import { PageHeader } from "@/components/page-header";
import { DataTable } from "@/components/data-table";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";
import { Button } from "@/components/ui/button";
import { BoolBadge } from "@/components/status-badge";
import { ConfirmDialog } from "@/components/confirm-dialog";
import { LoadingState } from "@/components/states";
import { inr } from "@/lib/utils";

interface Zone {
  id: string;
  name: string;
  code: string;
  storeName: string | null;
  isActive: boolean;
  creditEnabled: boolean;
  deliveryFee: number | null;
}
interface Expansion { id: string; name: string; mobile: string; village: string; area: string; pincode: string; createdAt: string }

export default function ZonesPage() {
  const { user } = useAuth();
  const router = useRouter();
  const canWrite = user?.role === "superadmin";
  const [toDelete, setToDelete] = React.useState<Zone | null>(null);

  const zones = useQuery({ queryKey: ["admin", "zones"], queryFn: () => api.getPaged<Zone>("/admin/zones") });
  const expansion = useQuery({
    queryKey: ["admin", "expansion"],
    queryFn: () => api.getPaged<Expansion>("/admin/expansion-requests"),
    enabled: canWrite,
    retry: false,
  });

  // A zone that has already served orders is deactivated rather than row-deleted
  // (history stays attributable), so the row is still in the list afterwards —
  // just inactive. Toasting a flat "Zone deleted." over that reads as a bug. Use
  // the server's own coded message, which names the outcome and the order count.
  const remove = useApiMutation(
    (id: string) => api.delWithMessage<{ outcome?: string }>(`/admin/zones/${id}`),
    {
      invalidate: [["admin", "zones"]],
      onDone: (res) => {
        toast.success(res.message || "Zone deleted.");
        setToDelete(null);
      },
    }
  );

  const columns: ColumnDef<Zone, unknown>[] = [
    { accessorKey: "name", header: "Zone", cell: ({ row }) => <span className="font-medium">{row.original.name}</span> },
    { accessorKey: "code", header: "Code", cell: ({ row }) => <span className="font-mono text-xs">{row.original.code}</span> },
    { accessorKey: "storeName", header: "Store", cell: ({ row }) => row.original.storeName || "—" },
    { accessorKey: "isActive", header: "Active", cell: ({ row }) => <BoolBadge value={row.original.isActive} /> },
    { accessorKey: "creditEnabled", header: "Credit", cell: ({ row }) => <BoolBadge value={row.original.creditEnabled} /> },
    { accessorKey: "deliveryFee", header: "Delivery Fee", cell: ({ row }) => inr(row.original.deliveryFee ?? 0) },
    {
      id: "actions",
      header: "",
      cell: ({ row }) =>
        canWrite ? (
          <div className="flex justify-end gap-1" onClick={(e) => e.stopPropagation()}>
            <Button variant="ghost" size="icon" onClick={() => router.push(`/zones/${row.original.id}/edit`)} title="Edit zone">
              <Pencil className="size-4" />
            </Button>
            <Button variant="ghost" size="icon" onClick={() => setToDelete(row.original)} title="Delete zone">
              <Trash2 className="size-4 text-destructive" />
            </Button>
          </div>
        ) : null,
    },
  ];

  return (
    <div className="space-y-6">
      <PageHeader
        title="Zone Management"
        description="Serviceability polygons, store assignment and delivery rules."
        actions={canWrite && <Button onClick={() => router.push("/zones/new")}><Plus /> New Zone</Button>}
      />

      <DataTable
        columns={columns}
        data={zones.data?.rows ?? []}
        loading={zones.isLoading}
        error={zones.isError ? "Failed to load zones." : null}
        onRetry={() => zones.refetch()}
        emptyMessage="No zones yet."
        onRowClick={canWrite ? (z) => router.push(`/zones/${z.id}/edit`) : undefined}
      />

      {canWrite && (
        <Card>
          <CardHeader>
            <CardTitle>Expansion Requests</CardTitle>
          </CardHeader>
          <CardContent>
            {expansion.isLoading ? (
              <LoadingState />
            ) : (expansion.data?.rows ?? []).length === 0 ? (
              <p className="py-6 text-center text-sm text-muted-foreground">No not-serviceable demand captured yet.</p>
            ) : (
              <ul className="divide-y text-sm">
                {(expansion.data?.rows ?? []).map((e) => (
                  <li key={e.id} className="flex flex-wrap items-center justify-between gap-2 py-2">
                    <span className="font-medium">{e.name || "—"} <span className="font-normal text-muted-foreground">{e.mobile}</span></span>
                    <span className="text-muted-foreground">{[e.area, e.village, e.pincode].filter(Boolean).join(", ")}</span>
                  </li>
                ))}
              </ul>
            )}
          </CardContent>
        </Card>
      )}

      <ConfirmDialog
        open={!!toDelete}
        onOpenChange={(o) => !o && setToDelete(null)}
        title={`Delete ${toDelete?.name}?`}
        description="Customers in this zone will lose serviceability."
        confirmLabel="Delete"
        destructive
        loading={remove.isPending}
        onConfirm={() => toDelete && remove.mutate(toDelete.id)}
      />
    </div>
  );
}
