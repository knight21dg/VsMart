"use client";

import * as React from "react";
import { useQuery } from "@tanstack/react-query";
import { type ColumnDef } from "@tanstack/react-table";
import { api } from "@/lib/api/client";
import { PageHeader } from "@/components/page-header";
import { StatCard } from "@/components/stat-card";
import { DataTable } from "@/components/data-table";
import { Badge } from "@/components/ui/badge";
import { BoolBadge } from "@/components/status-badge";
import { NotWiredYet } from "@/components/states";
import { cn, fmtDate, titleize } from "@/lib/utils";

interface Employee { id: string; name: string; phone: string; email: string; role: string; isActive: boolean; onDuty: boolean | null; zones: string[]; createdAt: string }
interface Resp { employees: Employee[]; summary: { superadmin: number; admin: number; agent: number; store_staff: number; total: number } }

const ROLE_VARIANT: Record<string, "default" | "secondary" | "success"> = { superadmin: "default", admin: "success", agent: "secondary", store_staff: "secondary" };

export default function EmployeesPage() {
  const [role, setRole] = React.useState("");
  const query = useQuery({ queryKey: ["employees", role], queryFn: () => api.get<Resp>("/admin/employees", { role: role || undefined }) });
  const s = query.data?.summary;

  const columns: ColumnDef<Employee, unknown>[] = [
    { accessorKey: "name", header: "Name", cell: ({ row }) => <span className="font-medium">{row.original.name}</span> },
    { accessorKey: "phone", header: "Phone", cell: ({ row }) => <span className="font-mono text-xs">{row.original.phone}</span> },
    { accessorKey: "role", header: "Role", cell: ({ row }) => <Badge variant={ROLE_VARIANT[row.original.role] ?? "secondary"}>{titleize(row.original.role)}</Badge> },
    {
      id: "zones",
      header: "Zones",
      cell: ({ row }) =>
        row.original.role !== "agent" ? <span className="text-muted-foreground">—</span> :
        row.original.zones.length === 0 ? <span className="text-xs text-muted-foreground">Unassigned</span> :
        <div className="flex flex-wrap gap-1">{row.original.zones.slice(0, 3).map((z) => <Badge key={z} variant="secondary">{z}</Badge>)}{row.original.zones.length > 3 && <span className="text-xs text-muted-foreground">+{row.original.zones.length - 3}</span>}</div>,
    },
    {
      id: "duty",
      header: "On Duty",
      cell: ({ row }) => row.original.onDuty == null ? <span className="text-muted-foreground">—</span> : <BoolBadge value={row.original.onDuty} trueLabel="On duty" falseLabel="Off" />,
    },
    { accessorKey: "isActive", header: "Status", cell: ({ row }) => <BoolBadge value={row.original.isActive} trueLabel="Active" falseLabel="Inactive" /> },
    { accessorKey: "createdAt", header: "Joined", cell: ({ row }) => <span className="text-xs text-muted-foreground">{fmtDate(row.original.createdAt)}</span> },
  ];

  const FILTERS = [
    { k: "", l: "All" },
    { k: "admin", l: "Admins" },
    { k: "agent", l: "Agents" },
    { k: "superadmin", l: "Super Admins" },
    { k: "store_staff", l: "Store Staff" },
  ];

  return (
    <>
      <PageHeader title="Employees" description="Staff directory across the network." />
      <div className="grid grid-cols-2 gap-4 md:grid-cols-5">
        <StatCard label="Total Staff" value={s?.total ?? 0} loading={query.isLoading} />
        <StatCard label="Admins" value={s?.admin ?? 0} accent="green" loading={query.isLoading} />
        <StatCard label="Agents" value={s?.agent ?? 0} accent="teal" loading={query.isLoading} />
        <StatCard label="Super Admins" value={s?.superadmin ?? 0} accent="slate" loading={query.isLoading} />
        <StatCard label="Store Staff" value={s?.store_staff ?? 0} accent="gold" loading={query.isLoading} />
      </div>

      <div className="flex flex-wrap gap-2">
        {FILTERS.map((f) => (
          <button key={f.k} onClick={() => setRole(f.k)} className={cn("rounded-full border px-3.5 py-1.5 text-sm transition-colors", role === f.k ? "border-primary bg-primary text-primary-foreground" : "bg-card hover:bg-accent")}>{f.l}</button>
        ))}
      </div>

      <DataTable
        columns={columns}
        data={query.data?.employees ?? []}
        loading={query.isLoading}
        error={query.isError ? "Failed to load employees." : null}
        onRetry={() => query.refetch()}
        emptyMessage="No employees."
      />

      <NotWiredYet note="Departments, leave management and per-employee attendance history aren't modelled in the backend yet — agent on-duty status is shown from the attendance roster." />
    </>
  );
}
