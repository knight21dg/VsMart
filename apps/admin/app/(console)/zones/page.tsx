"use client";

import * as React from "react";
import { useRouter } from "next/navigation";
import { useQuery } from "@tanstack/react-query";
import { type ColumnDef } from "@tanstack/react-table";
import { Download, Loader2, Pencil, Plus, Trash2 } from "lucide-react";
import { toast } from "sonner";
import { api, API_BASE } from "@/lib/api/client";
import { useApiMutation } from "@/lib/api/hooks";
import { useAuth } from "@/lib/auth/auth-context";
import { getAccessToken } from "@/lib/auth/session";
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
  const [exportingId, setExportingId] = React.useState<string | null>(null);

  async function exportZoneOrders(zone: Zone) {
    setExportingId(zone.id);
    try {
      const token = getAccessToken();
      const res = await fetch(`${API_BASE}/admin/zones/${zone.id}/orders/export`, {
        headers: token ? { Authorization: `Bearer ${token}` } : undefined,
      });
      if (!res.ok) {
        toast.error(`Export failed (${res.status}).`);
        return;
      }
      const blob = await res.blob();
      const url = URL.createObjectURL(blob);
      const a = document.createElement("a");
      a.href = url;
      a.download = `${zone.code || zone.name}-orders.csv`;
      document.body.appendChild(a);
      a.click();
      a.remove();
      URL.revokeObjectURL(url);
    } catch {
      toast.error("Couldn't download that zone's order history.");
    } finally {
      setExportingId(null);
    }
  }

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
    (zone: Zone) => {
      // An inactive zone has already been through the "would deactivate" step
      // once — this second delete is the explicit, permanent one. force is
      // harmless to send for an active zone too: the backend only honours it
      // on a zone that's already inactive, so there's no need to branch here.
      const qs = zone.isActive ? "" : "?force=true";
      return api.delWithMessage<{ outcome?: string; ordersDetached?: number }>(
        `/admin/zones/${zone.id}${qs}`
      );
    },
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
            <Button
              variant="ghost"
              size="icon"
              onClick={() => exportZoneOrders(row.original)}
              disabled={exportingId === row.original.id}
              title="Download this zone's order history (CSV)"
            >
              {exportingId === row.original.id
                ? <Loader2 className="size-4 animate-spin" />
                : <Download className="size-4" />}
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
        description={
          toDelete?.isActive
            ? "Customers in this zone will lose serviceability. If it has order history, it will be deactivated instead of deleted this time — delete it again afterwards to remove it for good."
            : "This zone is already deactivated. Deleting it now is permanent: its orders keep their own record, but will no longer show this zone. Download the order history first (the ↓ button) if you want to keep it."
        }
        confirmLabel="Delete"
        destructive
        loading={remove.isPending}
        onConfirm={() => toDelete && remove.mutate(toDelete)}
      />
    </div>
  );
}
