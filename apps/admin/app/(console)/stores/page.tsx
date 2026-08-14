"use client";

import * as React from "react";
import { useRouter } from "next/navigation";
import { useQuery } from "@tanstack/react-query";
import { type ColumnDef } from "@tanstack/react-table";
import { Pencil, Plus, Trash2, UserCog } from "lucide-react";
import { toast } from "sonner";
import { api } from "@/lib/api/client";
import { useApiMutation } from "@/lib/api/hooks";
import { useAuth } from "@/lib/auth/auth-context";
import { PageHeader } from "@/components/page-header";
import { DataTable } from "@/components/data-table";
import { Button } from "@/components/ui/button";
import { StatusBadge } from "@/components/status-badge";
import { ConfirmDialog } from "@/components/confirm-dialog";

interface Store {
  id: string;
  code: string;
  name: string;
  address: string;
  phone: string;
  status: string;
}

export default function StoresPage() {
  const { user } = useAuth();
  const router = useRouter();
  const canWrite = user?.role === "superadmin";
  const [toDelete, setToDelete] = React.useState<Store | null>(null);

  const stores = useQuery({ queryKey: ["admin", "stores"], queryFn: () => api.getPaged<Store>("/admin/stores") });

  // A store with orders, products or staff is deactivated rather than deleted,
  // so the row is still listed afterwards. "Store deleted." over a store that is
  // plainly still there reads as a failure — use the server's coded message,
  // which names which of the two happened and why.
  const remove = useApiMutation(
    (id: string) => api.delWithMessage(`/admin/stores/${id}`),
    {
      invalidate: [["admin", "stores"]],
      onDone: (res) => {
        toast.success(res.message || "Store deleted.");
        setToDelete(null);
      },
    }
  );

  const columns: ColumnDef<Store, unknown>[] = [
    { accessorKey: "name", header: "Store", cell: ({ row }) => <span className="font-medium">{row.original.name}</span> },
    { accessorKey: "code", header: "Code", cell: ({ row }) => <span className="font-mono text-xs">{row.original.code}</span> },
    { accessorKey: "phone", header: "Phone" },
    { accessorKey: "status", header: "Status", cell: ({ row }) => <StatusBadge status={row.original.status} /> },
    { accessorKey: "address", header: "Address", cell: ({ row }) => <span className="text-muted-foreground">{row.original.address || "—"}</span> },
    {
      id: "actions",
      header: "",
      cell: ({ row }) =>
        canWrite ? (
          <div className="flex justify-end gap-1" onClick={(e) => e.stopPropagation()}>
            <Button variant="ghost" size="sm" onClick={() => router.push(`/stores/${row.original.id}/admin`)} title="Manage store admin">
              <UserCog className="size-4" /> Admin
            </Button>
            <Button variant="ghost" size="icon" onClick={() => router.push(`/stores/${row.original.id}/edit`)} title="Edit store">
              <Pencil className="size-4" />
            </Button>
            <Button variant="ghost" size="icon" onClick={() => setToDelete(row.original)} title="Delete store">
              <Trash2 className="size-4 text-destructive" />
            </Button>
          </div>
        ) : null,
    },
  ];

  return (
    <div className="space-y-6">
      <PageHeader
        title="Store Management"
        description="Physical stores, their exact location and operating window."
        actions={canWrite && <Button onClick={() => router.push("/stores/new")}><Plus /> New Store</Button>}
      />
      <DataTable
        columns={columns}
        data={stores.data?.rows ?? []}
        loading={stores.isLoading}
        error={stores.isError ? "Failed to load stores." : null}
        onRetry={() => stores.refetch()}
        emptyMessage="No stores yet."
        onRowClick={canWrite ? (s) => router.push(`/stores/${s.id}/edit`) : undefined}
      />

      <ConfirmDialog
        open={!!toDelete}
        onOpenChange={(o) => !o && setToDelete(null)}
        title={`Delete ${toDelete?.name}?`}
        description="This cannot be undone."
        confirmLabel="Delete"
        destructive
        loading={remove.isPending}
        onConfirm={() => toDelete && remove.mutate(toDelete.id)}
      />
    </div>
  );
}
