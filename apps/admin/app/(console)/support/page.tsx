"use client";

import * as React from "react";
import { useQuery } from "@tanstack/react-query";
import { type ColumnDef } from "@tanstack/react-table";
import { Loader2, Send } from "lucide-react";
import { api } from "@/lib/api/client";
import { useApiMutation } from "@/lib/api/hooks";
import { PageHeader } from "@/components/page-header";
import { DataTable } from "@/components/data-table";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Badge } from "@/components/ui/badge";
import { StatusBadge } from "@/components/status-badge";
import { StatCard } from "@/components/stat-card";
import { StoreZone, StoreZoneFilter } from "@/components/store-zone";
import { Dialog, DialogContent, DialogHeader, DialogTitle } from "@/components/ui/dialog";
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from "@/components/ui/select";
import { LoadingState } from "@/components/states";
import { cn, fmtDate, titleize } from "@/lib/utils";

interface Ticket {
  id: string; code: string; category: string; priority: string; subject: string; status: string;
  orderCode: string; userName: string; userPhone: string; storeName: string | null; zoneName: string | null;
  assignedToName: string | null; createdAt: string;
}
interface TicketsResp { tickets: Ticket[]; summary: Record<string, number> }
interface Message { id: string; body: string; senderName: string; senderRole: string; createdAt: string }
interface TicketDetail extends Ticket { messages: Message[] }

const STATUSES = [
  { key: "", label: "All" },
  { key: "open", label: "Open" },
  { key: "in_progress", label: "In Progress" },
  { key: "resolved", label: "Resolved" },
  { key: "closed", label: "Closed" },
];
const PRIORITY: Record<string, "destructive" | "warning" | "secondary"> = { high: "destructive", medium: "warning", low: "secondary" };

export default function SupportPage() {
  const [status, setStatus] = React.useState("");
  const [search, setSearch] = React.useState("");
  const [q, setQ] = React.useState("");
  const [store, setStore] = React.useState("");
  const [zone, setZone] = React.useState("");
  const [openCode, setOpenCode] = React.useState<string | null>(null);

  React.useEffect(() => { const t = setTimeout(() => setQ(search.trim()), 300); return () => clearTimeout(t); }, [search]);

  const query = useQuery({
    queryKey: ["support", "tickets", { status, q, store, zone }],
    queryFn: () => api.get<TicketsResp>("/admin/support/tickets", { status: status || undefined, q: q || undefined, store: store || undefined, zone: zone || undefined }),
  });
  const summary = query.data?.summary;

  const columns: ColumnDef<Ticket, unknown>[] = [
    { accessorKey: "code", header: "Ticket", cell: ({ row }) => <span className="font-mono text-xs">{row.original.code}</span> },
    { accessorKey: "subject", header: "Subject", cell: ({ row }) => <span className="font-medium">{row.original.subject}</span> },
    { id: "user", header: "Customer", cell: ({ row }) => <div><p className="text-sm">{row.original.userName || "—"}</p><p className="font-mono text-xs text-muted-foreground">{row.original.userPhone}</p></div> },
    { id: "loc", header: "Store / Zone", cell: ({ row }) => <StoreZone store={row.original.storeName} zone={row.original.zoneName} /> },
    { accessorKey: "priority", header: "Priority", cell: ({ row }) => <Badge variant={PRIORITY[row.original.priority] ?? "secondary"}>{titleize(row.original.priority)}</Badge> },
    { accessorKey: "status", header: "Status", cell: ({ row }) => <StatusBadge status={row.original.status} /> },
    { accessorKey: "createdAt", header: "Opened", cell: ({ row }) => <span className="text-xs text-muted-foreground">{fmtDate(row.original.createdAt, true)}</span> },
  ];

  return (
    <>
      <PageHeader title="Customer Support" description="All tickets across customers — reply, prioritize, resolve." />
      <div className="grid grid-cols-2 gap-4 md:grid-cols-4">
        <StatCard label="Open" value={summary?.open ?? 0} accent={summary?.open ? "gold" : "slate"} loading={query.isLoading} />
        <StatCard label="In Progress" value={summary?.in_progress ?? 0} accent="teal" loading={query.isLoading} />
        <StatCard label="Resolved" value={summary?.resolved ?? 0} accent="green" loading={query.isLoading} />
        <StatCard label="Closed" value={summary?.closed ?? 0} accent="slate" loading={query.isLoading} />
      </div>
      <div className="flex flex-wrap items-center gap-2">
        {STATUSES.map((s) => (
          <button key={s.key} onClick={() => setStatus(s.key)} className={cn("rounded-full border px-3.5 py-1.5 text-sm transition-colors", status === s.key ? "border-primary bg-primary text-primary-foreground" : "bg-card hover:bg-accent")}>{s.label}</button>
        ))}
        <Input value={search} onChange={(e) => setSearch(e.target.value)} placeholder="Search subject…" className="max-w-xs" />
        <div className="ml-auto"><StoreZoneFilter store={store} zone={zone} onStore={setStore} onZone={setZone} /></div>
      </div>
      <DataTable
        columns={columns}
        data={query.data?.tickets ?? []}
        loading={query.isLoading}
        error={query.isError ? "Failed to load tickets." : null}
        onRetry={() => query.refetch()}
        onRowClick={(r) => setOpenCode(r.code)}
        emptyMessage="No tickets match."
      />
      {openCode && <TicketDialog code={openCode} onClose={() => setOpenCode(null)} />}
    </>
  );
}

function TicketDialog({ code, onClose }: { code: string; onClose: () => void }) {
  const [reply, setReply] = React.useState("");
  const query = useQuery({ queryKey: ["support", "ticket", code], queryFn: () => api.get<TicketDetail>(`/admin/support/tickets/${code}`) });
  const t = query.data;
  const send = useApiMutation((body: string) => api.post(`/admin/support/tickets/${code}/reply`, { body }), {
    invalidate: [["support", "ticket", code], ["support", "tickets"]], successMessage: "Reply sent.", onDone: () => setReply(""),
  });
  const update = useApiMutation((vars: Record<string, unknown>) => api.patch(`/admin/support/tickets/${code}/status`, vars), {
    invalidate: [["support", "ticket", code], ["support", "tickets"]], successMessage: "Updated.",
  });

  return (
    <Dialog open onOpenChange={(o) => !o && onClose()}>
      <DialogContent className="max-w-2xl">
        <DialogHeader><DialogTitle>{t?.subject ?? code}</DialogTitle></DialogHeader>
        {query.isLoading || !t ? (
          <LoadingState />
        ) : (
          <div className="space-y-4">
            <div className="flex flex-wrap items-center gap-3 text-sm">
              <span className="font-mono text-xs text-muted-foreground">{t.code}</span>
              <span>{t.userName} · {t.userPhone}</span>
              <div className="ml-auto flex items-center gap-2">
                <Select value={t.priority} onValueChange={(v) => update.mutate({ priority: v })}>
                  <SelectTrigger className="h-8 w-28"><SelectValue /></SelectTrigger>
                  <SelectContent>{["low", "medium", "high"].map((p) => <SelectItem key={p} value={p}>{titleize(p)}</SelectItem>)}</SelectContent>
                </Select>
                <Select value={t.status} onValueChange={(v) => update.mutate({ status: v })}>
                  <SelectTrigger className="h-8 w-36"><SelectValue /></SelectTrigger>
                  <SelectContent>{["open", "in_progress", "resolved", "closed"].map((s) => <SelectItem key={s} value={s}>{titleize(s)}</SelectItem>)}</SelectContent>
                </Select>
              </div>
            </div>

            <div className="max-h-72 space-y-2 overflow-y-auto rounded-lg border bg-muted/30 p-3 scrollbar-thin">
              {t.messages.length === 0 ? (
                <p className="py-6 text-center text-sm text-muted-foreground">No replies yet.</p>
              ) : (
                t.messages.map((m) => (
                  <div key={m.id} className={cn("max-w-[80%] rounded-lg px-3 py-2 text-sm", m.senderRole === "customer" ? "bg-card" : "ml-auto bg-primary text-primary-foreground")}>
                    <p>{m.body}</p>
                    <p className={cn("mt-1 text-[10px]", m.senderRole === "customer" ? "text-muted-foreground" : "text-primary-foreground/70")}>{m.senderName} · {fmtDate(m.createdAt, true)}</p>
                  </div>
                ))
              )}
            </div>

            <div className="flex gap-2">
              <Input value={reply} onChange={(e) => setReply(e.target.value)} placeholder="Type a reply…" onKeyDown={(e) => { if (e.key === "Enter" && reply.trim()) send.mutate(reply); }} />
              <Button onClick={() => send.mutate(reply)} disabled={send.isPending || !reply.trim()}>{send.isPending ? <Loader2 className="size-4 animate-spin" /> : <Send />}</Button>
            </div>
          </div>
        )}
      </DialogContent>
    </Dialog>
  );
}
