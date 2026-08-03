"use client";

import * as React from "react";
import { useQuery } from "@tanstack/react-query";
import { type ColumnDef } from "@tanstack/react-table";
import { Bike, CircleCheck, CircleSlash, Plus, Star, Trash2 } from "lucide-react";
import { api } from "@/lib/api/client";
import { useApiMutation } from "@/lib/api/hooks";
import { PageHeader } from "@/components/page-header";
import { StatCard } from "@/components/stat-card";
import { DataTable } from "@/components/data-table";
import { Tabs, TabsContent, TabsList, TabsTrigger } from "@/components/ui/tabs";
import { Button } from "@/components/ui/button";
import { Card, CardContent } from "@/components/ui/card";
import { Label } from "@/components/ui/label";
import { BoolBadge } from "@/components/status-badge";
import { Badge } from "@/components/ui/badge";
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from "@/components/ui/select";
import { fmtDate, inr, titleize } from "@/lib/utils";

/**
 * Agents — super-admin OVERSIGHT.
 *
 * Agents are store-owned: each store hires and edits its own riders in the store
 * panel, so there is deliberately no roster CRUD here. This console answers the
 * three questions a super-admin actually has across the whole fleet: who is on
 * duty, who performs, and which zones they cover.
 */

interface AgentRow {
  agentId: string; code: string; name: string; phone: string;
  storeId: string | null; storeName: string | null;
  vehicle: string; available: boolean; isActive: boolean; rating: number;
  bagCapacity: number; weightCapacityKg: number; cashCapacity: number; maxStops: number;
  employmentType: string;
  onDuty: boolean; checkInAt: string | null; checkOutAt: string | null;
}
interface LeaderRow {
  agentId: string; code: string; name: string; storeName: string | null; rating: number;
  deliveries: number; failed: number; successRate: number; avgMinutes: number | null;
  acceptanceRate: number;
  collectionsAssigned: number; collected: number; recoveredAmount: number; recoveryRate: number;
}
interface Zone { id: string; name: string; code: string }
interface ZoneAgent { id: string; name: string; phone: string }

export default function AgentsPage() {
  const [tab, setTab] = React.useState("duty");
  return (
    <>
      <PageHeader
        title="Agents"
        description="Fleet oversight — duty, performance and zone coverage. Stores hire and manage their own agents."
      />
      <Tabs value={tab} onValueChange={setTab}>
        <TabsList>
          <TabsTrigger value="duty">Duty &amp; Attendance</TabsTrigger>
          <TabsTrigger value="performance">Performance</TabsTrigger>
          <TabsTrigger value="zones">Zone Coverage</TabsTrigger>
        </TabsList>
        <TabsContent value="duty"><DutyBoard /></TabsContent>
        <TabsContent value="performance"><Leaderboard /></TabsContent>
        <TabsContent value="zones"><ZoneCoverage /></TabsContent>
      </Tabs>
    </>
  );
}

/* ── Duty & attendance ─────────────────────────────────────────────────── */
function DutyBoard() {
  const q = useQuery({
    queryKey: ["admin", "agents"],
    queryFn: () => api.get<AgentRow[]>("/admin/agents"),
    refetchInterval: 60_000, // a duty board is only useful if it's current
  });
  const rows = q.data ?? [];
  const onDuty = rows.filter((r) => r.onDuty).length;
  const available = rows.filter((r) => r.available && r.isActive).length;

  const columns: ColumnDef<AgentRow, unknown>[] = [
    {
      header: "Agent",
      cell: ({ row }) => (
        <div className="min-w-0">
          <p className="truncate font-medium">{row.original.name}</p>
          <p className="font-mono text-xs text-muted-foreground">{row.original.code} · {row.original.phone}</p>
        </div>
      ),
    },
    { header: "Store", cell: ({ row }) => <span className="text-sm">{row.original.storeName ?? <span className="text-muted-foreground">Unassigned</span>}</span> },
    {
      header: "Employment",
      cell: ({ row }) => (
        <Badge variant={row.original.employmentType === "monthly" ? "default" : "secondary"}>
          {titleize(row.original.employmentType || "gig")}
        </Badge>
      ),
    },
    { header: "Vehicle", cell: ({ row }) => <span className="text-sm capitalize">{row.original.vehicle}</span> },
    { header: "On duty", cell: ({ row }) => <BoolBadge value={row.original.onDuty} trueLabel="On duty" falseLabel="Off" /> },
    { header: "Available", cell: ({ row }) => <BoolBadge value={row.original.available} trueLabel="Available" falseLabel="Busy" /> },
    {
      header: "Checked in",
      cell: ({ row }) => (
        <span className="text-xs text-muted-foreground">
          {row.original.checkInAt ? fmtDate(row.original.checkInAt, true) : "—"}
          {row.original.checkOutAt ? ` → ${fmtDate(row.original.checkOutAt, true)}` : ""}
        </span>
      ),
    },
    {
      header: "Rating",
      cell: ({ row }) => (
        <span className="inline-flex items-center gap-1 tabular-nums">
          <Star className="size-3.5 text-[var(--color-gold)]" /> {row.original.rating.toFixed(1)}
        </span>
      ),
    },
  ];

  return (
    <div className="space-y-4">
      <div className="grid grid-cols-2 gap-4 md:grid-cols-4">
        <StatCard label="Agents" value={rows.length} loading={q.isLoading} />
        <StatCard label="On Duty Now" value={onDuty} accent="green" loading={q.isLoading} />
        <StatCard label="Available" value={available} loading={q.isLoading} />
        <StatCard label="Off Duty" value={rows.length - onDuty} loading={q.isLoading} />
      </div>
      <DataTable
        columns={columns}
        data={rows}
        loading={q.isLoading}
        error={q.isError ? "Couldn't load the agent roster." : null}
        onRetry={() => q.refetch()}
        emptyMessage="No agents yet — stores onboard their own riders from the store panel."
      />
    </div>
  );
}

/* ── Performance leaderboard ───────────────────────────────────────────── */
function Leaderboard() {
  const q = useQuery({
    queryKey: ["admin", "agents", "leaderboard"],
    queryFn: () => api.get<LeaderRow[]>("/admin/agents/leaderboard"),
  });
  const rows = q.data ?? [];

  const columns: ColumnDef<LeaderRow, unknown>[] = [
    {
      header: "#",
      cell: ({ row }) => <span className="tabular-nums text-muted-foreground">{row.index + 1}</span>,
    },
    {
      header: "Agent",
      cell: ({ row }) => (
        <div className="min-w-0">
          <p className="truncate font-medium">{row.original.name}</p>
          <p className="text-xs text-muted-foreground">{row.original.storeName ?? "Unassigned"}</p>
        </div>
      ),
    },
    { header: "Delivered", cell: ({ row }) => <span className="font-semibold tabular-nums">{row.original.deliveries}</span> },
    { header: "Failed", cell: ({ row }) => <span className="tabular-nums">{row.original.failed}</span> },
    { header: "Success", cell: ({ row }) => <span className="tabular-nums">{row.original.successRate}%</span> },
    {
      header: "Avg time",
      cell: ({ row }) => <span className="tabular-nums">{row.original.avgMinutes != null ? `${row.original.avgMinutes} min` : "—"}</span>,
    },
    { header: "Accepted", cell: ({ row }) => <span className="tabular-nums">{row.original.acceptanceRate}%</span> },
    { header: "Collected", cell: ({ row }) => <span className="tabular-nums">{row.original.collected}/{row.original.collectionsAssigned}</span> },
    { header: "Recovered", cell: ({ row }) => <span className="font-medium tabular-nums">{inr(row.original.recoveredAmount)}</span> },
    { header: "Recovery", cell: ({ row }) => <span className="tabular-nums">{row.original.recoveryRate}%</span> },
  ];

  return (
    <DataTable
      columns={columns}
      data={rows}
      loading={q.isLoading}
      error={q.isError ? "Couldn't load performance." : null}
      onRetry={() => q.refetch()}
      emptyMessage="No performance yet — it appears once agents start completing deliveries and collections."
    />
  );
}

/* ── Zone coverage ─────────────────────────────────────────────────────── */
function ZoneCoverage() {
  const zonesQ = useQuery({ queryKey: ["admin", "zones"], queryFn: () => api.get<Zone[]>("/admin/zones") });
  const zones = zonesQ.data ?? [];
  const [zoneId, setZoneId] = React.useState("");
  // Default to the first zone once loaded, without a setState-in-effect.
  const activeZone = zoneId || zones[0]?.id || "";

  const assignedQ = useQuery({
    queryKey: ["admin", "zone-agents", activeZone],
    queryFn: () => api.get<ZoneAgent[]>(`/admin/zones/${activeZone}/agents`),
    enabled: !!activeZone,
  });
  const allQ = useQuery({ queryKey: ["admin", "agents"], queryFn: () => api.get<AgentRow[]>("/admin/agents") });

  const assigned = assignedQ.data ?? [];
  const assignedIds = new Set(assigned.map((a) => a.id));
  const unassigned = (allQ.data ?? []).filter((a) => !assignedIds.has(a.agentId) && a.isActive);

  const assign = useApiMutation(
    (agentId: unknown) => api.post(`/admin/zones/${activeZone}/agents`, { agentId }),
    { invalidate: [["admin", "zone-agents", activeZone]], successMessage: "Agent assigned to zone" },
  );
  const unassign = useApiMutation(
    (agentId: unknown) => api.del(`/admin/zones/${activeZone}/agents/${agentId}`),
    { invalidate: [["admin", "zone-agents", activeZone]], successMessage: "Agent removed from zone" },
  );

  return (
    <div className="space-y-4">
      <div className="max-w-xs space-y-1.5">
        <Label>Zone</Label>
        <Select value={activeZone} onValueChange={setZoneId}>
          <SelectTrigger><SelectValue placeholder="Select a zone" /></SelectTrigger>
          <SelectContent>
            {zones.map((z) => <SelectItem key={z.id} value={z.id}>{z.name}</SelectItem>)}
          </SelectContent>
        </Select>
      </div>

      <div className="grid gap-4 md:grid-cols-2">
        <Card>
          <CardContent className="space-y-2 p-5">
            <div className="flex items-center gap-2">
              <CircleCheck className="size-4 text-[var(--color-success)]" />
              <h3 className="font-semibold">Covering this zone</h3>
              <span className="ml-auto text-sm text-muted-foreground">{assigned.length}</span>
            </div>
            {assignedQ.isLoading && <p className="py-6 text-center text-sm text-muted-foreground">Loading…</p>}
            {!assignedQ.isLoading && assigned.length === 0 && (
              <p className="py-6 text-center text-sm text-muted-foreground">
                No agents cover this zone yet — deliveries here have nobody to route to.
              </p>
            )}
            {assigned.map((a) => (
              <div key={a.id} className="flex items-center justify-between rounded-md border px-3 py-2">
                <div className="min-w-0">
                  <p className="truncate text-sm font-medium">{a.name}</p>
                  <p className="font-mono text-xs text-muted-foreground">{a.phone}</p>
                </div>
                <Button variant="ghost" size="icon" className="size-8"
                        disabled={unassign.isPending}
                        onClick={() => unassign.mutate(a.id)}>
                  <Trash2 className="size-4 text-muted-foreground" />
                </Button>
              </div>
            ))}
          </CardContent>
        </Card>

        <Card>
          <CardContent className="space-y-2 p-5">
            <div className="flex items-center gap-2">
              <CircleSlash className="size-4 text-muted-foreground" />
              <h3 className="font-semibold">Not covering this zone</h3>
              <span className="ml-auto text-sm text-muted-foreground">{unassigned.length}</span>
            </div>
            {!allQ.isLoading && unassigned.length === 0 && (
              <p className="py-6 text-center text-sm text-muted-foreground">Every active agent already covers this zone.</p>
            )}
            {unassigned.map((a) => (
              <div key={a.agentId} className="flex items-center justify-between rounded-md border px-3 py-2">
                <div className="min-w-0">
                  <p className="truncate text-sm font-medium">{a.name}</p>
                  <p className="text-xs text-muted-foreground">
                    <Bike className="mr-1 inline size-3" />{a.vehicle} · {a.storeName ?? "Unassigned"}
                  </p>
                </div>
                <Button variant="outline" size="sm"
                        disabled={!activeZone || assign.isPending}
                        onClick={() => assign.mutate(a.agentId)}>
                  <Plus className="size-3.5" /> Assign
                </Button>
              </div>
            ))}
          </CardContent>
        </Card>
      </div>
    </div>
  );
}
