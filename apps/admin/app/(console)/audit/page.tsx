"use client";

import * as React from "react";
import { keepPreviousData, useQuery } from "@tanstack/react-query";
import { type ColumnDef } from "@tanstack/react-table";
import { api } from "@/lib/api/client";
import { PageHeader } from "@/components/page-header";
import { DataTable } from "@/components/data-table";
import { Input } from "@/components/ui/input";
import { Badge } from "@/components/ui/badge";
import { Button } from "@/components/ui/button";
import {
  Dialog,
  DialogContent,
  DialogHeader,
  DialogTitle,
} from "@/components/ui/dialog";
import type { CursorMeta, Paged } from "@/lib/types";
import { fmtDate } from "@/lib/utils";

interface AuditLog {
  id: string;
  actor: string;
  action: string;
  targetType: string;
  targetId: string;
  before: unknown;
  after: unknown;
  createdAt: string;
}

export default function AuditPage() {
  const [action, setAction] = React.useState("");
  const [actor, setActor] = React.useState("");
  const [debounced, setDebounced] = React.useState({ action: "", actor: "" });
  const [cursor, setCursor] = React.useState<string | null>(null);
  const [selected, setSelected] = React.useState<AuditLog | null>(null);

  React.useEffect(() => {
    const t = setTimeout(() => {
      setDebounced({ action: action.trim(), actor: actor.trim() });
      setCursor(null);
    }, 300);
    return () => clearTimeout(t);
  }, [action, actor]);

  const query = useQuery({
    queryKey: ["audit", debounced, cursor],
    queryFn: () =>
      api.getPaged<AuditLog>("/audit/logs", {
        action: debounced.action || undefined,
        actor: debounced.actor || undefined,
        cursor: cursor || undefined,
      }),
    placeholderData: keepPreviousData,
  });
  const data: Paged<AuditLog> | undefined = query.data;

  // cursor param is a full URL from DRF; extract just the cursor value.
  function extractCursor(url: string | null): string | null {
    if (!url) return null;
    try {
      return new URL(url).searchParams.get("cursor");
    } catch {
      return url;
    }
  }

  const columns: ColumnDef<AuditLog, unknown>[] = [
    { accessorKey: "createdAt", header: "Time", cell: ({ row }) => <span className="text-xs text-muted-foreground">{fmtDate(row.original.createdAt, true)}</span> },
    { accessorKey: "actor", header: "Actor", cell: ({ row }) => <span className="font-medium">{row.original.actor || "—"}</span> },
    { accessorKey: "action", header: "Action", cell: ({ row }) => <Badge variant="secondary" className="font-mono">{row.original.action}</Badge> },
    {
      id: "target",
      header: "Target",
      cell: ({ row }) => (
        <span className="text-xs text-muted-foreground">
          {row.original.targetType}
          {row.original.targetId ? `#${row.original.targetId}` : ""}
        </span>
      ),
    },
    {
      id: "details",
      header: "",
      cell: ({ row }) => (
        <Button variant="ghost" size="sm" onClick={() => setSelected(row.original)}>
          Details
        </Button>
      ),
    },
  ];

  const meta = data?.meta as CursorMeta | undefined;

  return (
    <>
      <PageHeader title="Audit & Compliance" description="Every privileged action, append-only." />
      <DataTable
        columns={columns}
        data={data?.rows ?? []}
        loading={query.isLoading}
        error={query.isError ? "Failed to load audit logs." : null}
        onRetry={() => query.refetch()}
        emptyMessage="No audit entries match."
        cursorMeta={
          meta
            ? { pageSize: meta.pageSize, nextCursor: extractCursor(meta.nextCursor), previousCursor: extractCursor(meta.previousCursor) }
            : undefined
        }
        onCursor={(c) => setCursor(c)}
        toolbar={
          <div className="flex flex-wrap gap-2">
            <Input value={action} onChange={(e) => setAction(e.target.value)} placeholder="Filter by action…" className="max-w-xs" />
            <Input value={actor} onChange={(e) => setActor(e.target.value)} placeholder="Filter by actor…" className="max-w-xs" />
          </div>
        }
      />

      <Dialog open={!!selected} onOpenChange={(o) => !o && setSelected(null)}>
        <DialogContent className="max-w-2xl">
          <DialogHeader>
            <DialogTitle className="font-mono text-base">{selected?.action}</DialogTitle>
          </DialogHeader>
          <div className="grid gap-4 sm:grid-cols-2">
            <div>
              <p className="mb-1 text-xs font-semibold uppercase text-muted-foreground">Before</p>
              <pre className="max-h-72 overflow-auto rounded-md bg-muted p-3 text-xs scrollbar-thin">
                {JSON.stringify(selected?.before ?? null, null, 2)}
              </pre>
            </div>
            <div>
              <p className="mb-1 text-xs font-semibold uppercase text-muted-foreground">After</p>
              <pre className="max-h-72 overflow-auto rounded-md bg-muted p-3 text-xs scrollbar-thin">
                {JSON.stringify(selected?.after ?? null, null, 2)}
              </pre>
            </div>
          </div>
        </DialogContent>
      </Dialog>
    </>
  );
}
