"use client";

import * as React from "react";
import { useQuery } from "@tanstack/react-query";
import type { ColumnDef } from "@tanstack/react-table";
import { Download, Search } from "lucide-react";
import { api } from "@/lib/api/client";
import { PageHeader } from "@/components/page-header";
import { DataTable } from "@/components/data-table";
import { RequirePerm } from "@/components/permission-gate";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { downloadCsv } from "@/lib/csv";
import { fmtDate, titleize } from "@/lib/utils";

interface AuditRow { actor: string; action: string; targetType: string; targetId: string; at: string; }

/** Debounce a fast-changing value so we don't refetch on every keystroke. */
function useDebounced<T>(value: T, ms = 350): T {
  const [v, setV] = React.useState(value);
  React.useEffect(() => {
    const t = setTimeout(() => setV(value), ms);
    return () => clearTimeout(t);
  }, [value, ms]);
  return v;
}

export default function AuditPage() {
  return (
    <RequirePerm perm="audit.view">
      <AuditInner />
    </RequirePerm>
  );
}

function AuditInner() {
  const [actor, setActor] = React.useState("");
  const [action, setAction] = React.useState("");
  const [from, setFrom] = React.useState("");
  const [to, setTo] = React.useState("");

  const dActor = useDebounced(actor);
  const dAction = useDebounced(action);

  const params = React.useMemo(
    () => ({
      actor: dActor || undefined,
      action: dAction || undefined,
      from: from || undefined,
      to: to || undefined,
    }),
    [dActor, dAction, from, to],
  );

  const q = useQuery({
    queryKey: ["store", "audit", params],
    queryFn: () => api.get<AuditRow[]>("/store/audit", params),
  });

  const rows = q.data ?? [];

  const columns: ColumnDef<AuditRow, unknown>[] = [
    { header: "Who", accessorKey: "actor", cell: ({ row }) => <span className="font-medium">{row.original.actor}</span> },
    { header: "Action", cell: ({ row }) => <span className="font-mono text-xs">{row.original.action}</span> },
    { header: "Target", cell: ({ row }) => <span className="text-sm text-muted-foreground">{titleize(row.original.targetType)} {row.original.targetId && `#${row.original.targetId}`}</span> },
    { header: "When", cell: ({ row }) => <span className="text-xs text-muted-foreground">{fmtDate(row.original.at, true)}</span> },
  ];

  return (
    <div className="space-y-5">
      <PageHeader
        title="Audit Log"
        description="Every action your staff take — append-only, nothing is deleted."
        actions={
          rows.length > 0 ? (
            <Button
              variant="outline"
              size="sm"
              onClick={() => downloadCsv(`audit-${new Date().toISOString().slice(0, 10)}.csv`,
                ["at", "actor", "action", "targetType", "targetId"], rows)}
            >
              <Download className="size-3.5" /> Export CSV
            </Button>
          ) : null
        }
      />
      <DataTable
        columns={columns}
        data={rows}
        loading={q.isLoading}
        error={q.error ? "Couldn't load the audit log." : null}
        onRetry={() => q.refetch()}
        emptyMessage="No activity matches these filters."
        toolbar={
          <div className="flex flex-wrap items-center gap-2">
            <div className="relative">
              <Search className="absolute left-2.5 top-2.5 size-4 text-muted-foreground" />
              <Input placeholder="Search staff…" value={actor} onChange={(e) => setActor(e.target.value)} className="h-9 w-[180px] pl-8" />
            </div>
            <Input placeholder="Action contains…" value={action} onChange={(e) => setAction(e.target.value)} className="h-9 w-[170px]" />
            <Input type="date" value={from} max={to || undefined} onChange={(e) => setFrom(e.target.value)} className="h-9 w-[150px]" />
            <span className="text-sm text-muted-foreground">to</span>
            <Input type="date" value={to} min={from || undefined} onChange={(e) => setTo(e.target.value)} className="h-9 w-[150px]" />
          </div>
        }
      />
    </div>
  );
}
