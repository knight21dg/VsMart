"use client";

import * as React from "react";
import Link from "next/link";
import { useQuery } from "@tanstack/react-query";
import { UserPlus, Loader2, Pencil, Wallet, Star } from "lucide-react";
import { api, useApiMutation } from "@/lib/api/hooks";
import { useStore } from "@/lib/store/store-context";
import { PageHeader } from "@/components/page-header";
import { RequirePerm } from "@/components/permission-gate";
import { LoadingState, ErrorState, EmptyState } from "@/components/states";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import { Badge } from "@/components/ui/badge";
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from "@/components/ui/select";
import {
  Dialog, DialogContent, DialogHeader, DialogTitle, DialogDescription, DialogFooter,
} from "@/components/ui/dialog";

interface Agent {
  id: string;
  name: string;
  phone: string;
  /** The app LOGIN. Distinct from `available` (on shift / off shift). */
  isActive: boolean;
  available: boolean;
  vehicle: string;
  rating: number;
  bagCapacity: number;
  weightCapacityKg: number;
  cashCapacity: number;
  maxStops: number;
  activeLoad?: number;
  /** "gig" (paid per task — the app shows them earnings) or "monthly" (salaried
   *  — the app hides earnings and defaults them to their task list). */
  employmentType: "gig" | "monthly";
}

/** Must match AgentProfile.EmploymentType on the backend. */
const EMPLOYMENT_TYPES: { value: Agent["employmentType"]; label: string; hint: string }[] = [
  { value: "gig", label: "Freelance / Gig", hint: "Paid per task — sees earnings in the app" },
  { value: "monthly", label: "Monthly employee", hint: "Salaried — earnings are hidden, app opens on their tasks" },
];
interface LiveAgent {
  id: string; name: string; phone: string; vehicle: string | null;
  onDuty: boolean; online: boolean; lat: number | null; lng: number | null;
  activeDeliveries: number;
}
interface LiveOps {
  summary: { totalAgents: number; agentsOnDuty: number; agentsOnline: number; activeDeliveries: number };
  agents: LiveAgent[];
}

/** Must match AgentProfile.Vehicle on the backend. */
const VEHICLES = [
  { value: "bike", label: "Bike" },
  { value: "scooter", label: "Scooter" },
  { value: "cycle", label: "Cycle" },
  { value: "van", label: "Van" },
  { value: "foot", label: "On foot" },
];

export default function AgentsPage() {
  return (
    <RequirePerm perm="delivery.view">
      <AgentsInner />
    </RequirePerm>
  );
}

function AgentsInner() {
  const { hasPerm } = useStore();
  const canManage = hasPerm("delivery.manage");
  const [open, setOpen] = React.useState(false);
  const [editing, setEditing] = React.useState<Agent | null>(null);

  const q = useQuery({
    queryKey: ["store", "agents"],
    queryFn: () => api.get<Agent[]>("/store/agents"),
  });
  // Live duty board — the store's own riders' position/on-duty/load, polled. Was
  // absent: the store only had a static roster, no sense of who's actually working.
  const live = useQuery({
    queryKey: ["store", "agents", "live"],
    queryFn: () => api.get<LiveOps>("/store/agents/live"),
    refetchInterval: 20000,
  });

  return (
    <div className="space-y-4">
      <PageHeader
        title="Agents"
        description="Field agents and the phone logins they use in the agent app."
        actions={
          <div className="flex items-center gap-2">
            <Button size="sm" variant="outline" asChild>
              <Link href="/agents/cash">
                <Wallet className="size-4" /> Cash
              </Link>
            </Button>
            {canManage && (
              <Button size="sm" onClick={() => setOpen(true)}>
                <UserPlus className="size-4" /> Add agent
              </Button>
            )}
          </div>
        }
      />

      {live.data && (
        <div className="rounded-lg border bg-card p-4">
          <div className="mb-3 flex items-center justify-between">
            <h2 className="text-sm font-semibold">On duty now</h2>
            <span className="text-xs text-muted-foreground">
              {live.data.summary.agentsOnDuty} on duty · {live.data.summary.agentsOnline} online · {live.data.summary.activeDeliveries} active deliveries
            </span>
          </div>
          {live.data.agents.filter((a) => a.online || a.onDuty).length === 0 ? (
            <p className="text-sm text-muted-foreground">No agents on duty right now.</p>
          ) : (
            <div className="grid grid-cols-1 gap-2 sm:grid-cols-2 lg:grid-cols-3">
              {live.data.agents.filter((a) => a.online || a.onDuty).map((a) => (
                <div key={a.id} className="flex items-center justify-between rounded-md border px-3 py-2">
                  <span className="flex min-w-0 items-center gap-2">
                    <span className={`size-2 shrink-0 rounded-full ${a.online ? "bg-[var(--color-success)]" : "bg-muted-foreground"}`} />
                    <span className="min-w-0">
                      <span className="block truncate text-sm font-medium">{a.name}</span>
                      <span className="block text-xs text-muted-foreground">
                        {a.onDuty ? "On duty" : "Off duty"}{a.lat != null ? " · located" : " · no GPS"}
                      </span>
                    </span>
                  </span>
                  <span className="shrink-0 text-xs tabular-nums text-muted-foreground">{a.activeDeliveries} active</span>
                </div>
              ))}
            </div>
          )}
        </div>
      )}

      {q.isLoading ? (
        <LoadingState label="Loading agents…" />
      ) : q.error ? (
        <ErrorState message="Couldn't load agents." onRetry={() => q.refetch()} />
      ) : (q.data ?? []).length === 0 ? (
        <EmptyState title="No agents yet" description="Add an agent to give them an app login." />
      ) : (
        <div className="overflow-x-auto rounded-lg border">
          <table className="w-full text-sm">
            <thead className="bg-muted/50 text-left text-xs uppercase text-muted-foreground">
              <tr>
                <th className="px-4 py-2.5 font-medium">Name</th>
                <th className="px-4 py-2.5 font-medium">Phone</th>
                <th className="px-4 py-2.5 font-medium">Vehicle</th>
                <th className="px-4 py-2.5 font-medium">Capacity</th>
                <th className="px-4 py-2.5 font-medium">Employment</th>
                <th className="px-4 py-2.5 font-medium">Rating</th>
                <th className="px-4 py-2.5 font-medium">Shift</th>
                <th className="px-4 py-2.5 font-medium">Login</th>
                <th className="px-4 py-2.5 font-medium">Load</th>
                {canManage && <th className="px-4 py-2.5" />}
              </tr>
            </thead>
            <tbody>
              {(q.data ?? []).map((a) => (
                <tr key={a.id} className={`border-t ${a.isActive ? "" : "opacity-55"}`}>
                  <td className="px-4 py-2.5 font-medium">{a.name}</td>
                  <td className="px-4 py-2.5 tabular-nums text-muted-foreground">{a.phone}</td>
                  <td className="px-4 py-2.5 capitalize">{a.vehicle || "—"}</td>
                  <td className="px-4 py-2.5 text-xs tabular-nums text-muted-foreground">
                    {a.bagCapacity} bags · {a.maxStops} stops
                  </td>
                  <td className="px-4 py-2.5">
                    <Badge variant={a.employmentType === "monthly" ? "default" : "secondary"}>
                      {a.employmentType === "monthly" ? "Monthly" : "Gig"}
                    </Badge>
                  </td>
                  <td className="px-4 py-2.5">
                    <span className="inline-flex items-center gap-1 tabular-nums">
                      <Star className="size-3.5 text-[var(--color-gold)]" />
                      {a.rating ? a.rating.toFixed(1) : "—"}
                    </span>
                  </td>
                  <td className="px-4 py-2.5">
                    <Badge variant={a.available ? "success" : "secondary"}>
                      {a.available ? "Available" : "Offline"}
                    </Badge>
                  </td>
                  <td className="px-4 py-2.5">
                    <Badge variant={a.isActive ? "secondary" : "destructive"}>
                      {a.isActive ? "Active" : "Disabled"}
                    </Badge>
                  </td>
                  <td className="px-4 py-2.5 tabular-nums">{a.activeLoad ?? 0}</td>
                  {canManage && (
                    <td className="px-4 py-2.5 text-right">
                      <Button variant="ghost" size="sm" onClick={() => setEditing(a)}>
                        <Pencil className="size-3.5" /> Edit
                      </Button>
                    </td>
                  )}
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      )}

      <AddAgentDialog open={open} onClose={() => setOpen(false)} />
      {editing && (
        <EditAgentDialog
          key={editing.id}
          agent={editing}
          onClose={() => setEditing(null)}
        />
      )}
    </div>
  );
}

/**
 * Edit an agent's vehicle + capacity, their shift availability, and their app
 * login. Capacity is what the dispatch/batching engine plans trips against, so
 * these numbers are operational, not cosmetic.
 */
function EditAgentDialog({ agent, onClose }: { agent: Agent; onClose: () => void }) {
  const [vehicle, setVehicle] = React.useState(agent.vehicle || "bike");
  const [bagCapacity, setBagCapacity] = React.useState(String(agent.bagCapacity ?? ""));
  const [maxStops, setMaxStops] = React.useState(String(agent.maxStops ?? ""));
  const [weightCapacityKg, setWeight] = React.useState(String(agent.weightCapacityKg ?? ""));
  const [cashCapacity, setCash] = React.useState(String(agent.cashCapacity ?? ""));
  const [available, setAvailable] = React.useState(agent.available);
  const [isActive, setIsActive] = React.useState(agent.isActive);
  const [employmentType, setEmploymentType] = React.useState(agent.employmentType || "gig");

  const save = useApiMutation<void, Agent>(
    () => api.patch<Agent>(`/store/agents/${agent.id}`, {
      vehicle,
      bagCapacity: bagCapacity.trim(),
      maxStops: maxStops.trim(),
      weightCapacityKg: weightCapacityKg.trim(),
      cashCapacity: cashCapacity.trim(),
      available,
      isActive,
      employmentType,
    }),
    { invalidate: [["store", "agents"]], successMessage: "Agent updated", onDone: onClose },
  );

  // Guard here too: the backend now 400s on these, but blocking the click is
  // clearer than a round-trip to be told the number was nonsense.
  const num = (v: string) => (v.trim() === "" ? NaN : Number(v));
  const valid = [bagCapacity, maxStops, weightCapacityKg, cashCapacity]
    .every((v) => Number.isFinite(num(v)) && num(v) >= 0);

  return (
    <Dialog open onOpenChange={(o) => !o && onClose()}>
      <DialogContent>
        <DialogHeader>
          <DialogTitle>{agent.name}</DialogTitle>
          <DialogDescription>
            Capacity drives how many stops the dispatch engine plans for this agent.
          </DialogDescription>
        </DialogHeader>
        <div className="space-y-3 py-2">
          <div className="space-y-1.5">
            <Label>Vehicle</Label>
            <Select value={vehicle} onValueChange={setVehicle}>
              <SelectTrigger><SelectValue /></SelectTrigger>
              <SelectContent>
                {VEHICLES.map((v) => <SelectItem key={v.value} value={v.value}>{v.label}</SelectItem>)}
              </SelectContent>
            </Select>
          </div>
          <div className="grid grid-cols-2 gap-3">
            <div className="space-y-1.5">
              <Label>Bag capacity <span className="text-xs font-normal text-muted-foreground">orders/trip</span></Label>
              <Input inputMode="numeric" value={bagCapacity} onChange={(e) => setBagCapacity(e.target.value)} />
            </div>
            <div className="space-y-1.5">
              <Label>Max stops <span className="text-xs font-normal text-muted-foreground">incl. collections</span></Label>
              <Input inputMode="numeric" value={maxStops} onChange={(e) => setMaxStops(e.target.value)} />
            </div>
            <div className="space-y-1.5">
              <Label>Weight capacity (kg)</Label>
              <Input inputMode="numeric" value={weightCapacityKg} onChange={(e) => setWeight(e.target.value)} />
            </div>
            <div className="space-y-1.5">
              <Label>Cash capacity (₹)</Label>
              <Input inputMode="decimal" value={cashCapacity} onChange={(e) => setCash(e.target.value)} />
            </div>
          </div>

          <div className="space-y-1.5">
            <Label>Employment</Label>
            <Select value={employmentType} onValueChange={(v) => setEmploymentType(v as Agent["employmentType"])}>
              <SelectTrigger><SelectValue /></SelectTrigger>
              <SelectContent>
                {EMPLOYMENT_TYPES.map((t) => (
                  <SelectItem key={t.value} value={t.value}>{t.label}</SelectItem>
                ))}
              </SelectContent>
            </Select>
            <p className="text-xs text-muted-foreground">
              {EMPLOYMENT_TYPES.find((t) => t.value === employmentType)?.hint}
            </p>
          </div>

          <label className="flex items-center gap-2 pt-1 text-sm">
            <input type="checkbox" checked={available} onChange={(e) => setAvailable(e.target.checked)} />
            Available for new trips <span className="text-muted-foreground">(on shift)</span>
          </label>
          <label className="flex items-center gap-2 text-sm">
            <input type="checkbox" checked={isActive} onChange={(e) => setIsActive(e.target.checked)} />
            App login enabled
          </label>
          {!isActive && (
            <p className="rounded-md bg-[var(--color-danger)]/10 px-3 py-2 text-xs text-[var(--color-danger)]">
              Disabling the login signs this agent out of the agent app — they can&apos;t
              take deliveries or collections until it&apos;s re-enabled.
            </p>
          )}
        </div>
        <DialogFooter>
          <Button variant="outline" onClick={onClose} disabled={save.isPending}>Cancel</Button>
          <Button onClick={() => save.mutate()} disabled={!valid || save.isPending}>
            {save.isPending && <Loader2 className="size-4 animate-spin" />} Save changes
          </Button>
        </DialogFooter>
      </DialogContent>
    </Dialog>
  );
}

function AddAgentDialog({ open, onClose }: { open: boolean; onClose: () => void }) {
  const [phone, setPhone] = React.useState("");
  const [name, setName] = React.useState("");
  // Capacity at ONBOARDING, not as a later edit. Add-agent used to take only
  // name+phone, so every new rider silently landed on default capacities (and a
  // default vehicle) until someone remembered to reopen Edit — the dispatch
  // engine then planned trips against numbers nobody had entered.
  const [vehicle, setVehicle] = React.useState("bike");
  const [bagCapacity, setBagCapacity] = React.useState("5");
  const [maxStops, setMaxStops] = React.useState("8");
  const [weightCapacityKg, setWeight] = React.useState("20");
  const [cashCapacity, setCash] = React.useState("10000");
  const [employmentType, setEmploymentType] = React.useState<Agent["employmentType"]>("monthly");

  const create = useApiMutation<void, Agent>(
    () =>
      api.post<Agent>("/store/agents", {
        phone: phone.trim(),
        name: name.trim(),
        vehicle,
        bagCapacity: bagCapacity.trim(),
        maxStops: maxStops.trim(),
        weightCapacityKg: weightCapacityKg.trim(),
        cashCapacity: cashCapacity.trim(),
        employmentType,
      }),
    {
      invalidate: [["store", "agents"]],
      successMessage: "Agent added — they can now sign in with their phone",
      onDone: () => {
        setPhone("");
        setName("");
        onClose();
      },
    }
  );

  const numbersValid = [bagCapacity, maxStops, weightCapacityKg, cashCapacity]
    .every((v) => v.trim() !== "" && !Number.isNaN(Number(v)) && Number(v) >= 0);
  const valid =
    /^\d{10}$/.test(phone.trim()) && name.trim().length >= 2 && numbersValid;

  return (
    <Dialog open={open} onOpenChange={(o) => !o && onClose()}>
      <DialogContent>
        <DialogHeader>
          <DialogTitle>Add agent</DialogTitle>
          <DialogDescription>
            Creates a phone login for the agent app. They sign in with this number + an OTP.
          </DialogDescription>
        </DialogHeader>
        <div className="space-y-3 py-2">
          <div className="space-y-1.5">
            <Label htmlFor="agent-name">Name</Label>
            <Input
              id="agent-name"
              value={name}
              onChange={(e) => setName(e.target.value)}
              placeholder="e.g. Ravi Kumar"
            />
          </div>
          <div className="space-y-1.5">
            <Label htmlFor="agent-phone">Mobile number</Label>
            <Input
              id="agent-phone"
              value={phone}
              inputMode="numeric"
              maxLength={10}
              onChange={(e) => setPhone(e.target.value.replace(/\D/g, "").slice(0, 10))}
              placeholder="10-digit mobile number"
            />
          </div>
          <div className="space-y-1.5">
            <Label>Vehicle</Label>
            <Select value={vehicle} onValueChange={setVehicle}>
              <SelectTrigger><SelectValue /></SelectTrigger>
              <SelectContent>
                {VEHICLES.map((v) => (
                  <SelectItem key={v.value} value={v.value}>{v.label}</SelectItem>
                ))}
              </SelectContent>
            </Select>
          </div>
          <div className="grid grid-cols-2 gap-3">
            <div className="space-y-1.5">
              <Label>Bag capacity <span className="text-xs font-normal text-muted-foreground">orders/trip</span></Label>
              <Input inputMode="numeric" value={bagCapacity} onChange={(e) => setBagCapacity(e.target.value)} />
            </div>
            <div className="space-y-1.5">
              <Label>Max stops <span className="text-xs font-normal text-muted-foreground">incl. collections</span></Label>
              <Input inputMode="numeric" value={maxStops} onChange={(e) => setMaxStops(e.target.value)} />
            </div>
            <div className="space-y-1.5">
              <Label>Weight capacity (kg)</Label>
              <Input inputMode="numeric" value={weightCapacityKg} onChange={(e) => setWeight(e.target.value)} />
            </div>
            <div className="space-y-1.5">
              <Label>Cash capacity (₹)</Label>
              <Input inputMode="decimal" value={cashCapacity} onChange={(e) => setCash(e.target.value)} />
            </div>
          </div>
          <div className="space-y-1.5">
            <Label>Employment</Label>
            <Select value={employmentType} onValueChange={(v) => setEmploymentType(v as Agent["employmentType"])}>
              <SelectTrigger><SelectValue /></SelectTrigger>
              <SelectContent>
                {EMPLOYMENT_TYPES.map((t) => (
                  <SelectItem key={t.value} value={t.value}>{t.label}</SelectItem>
                ))}
              </SelectContent>
            </Select>
            <p className="text-xs text-muted-foreground">
              {EMPLOYMENT_TYPES.find((t) => t.value === employmentType)?.hint}
            </p>
          </div>
        </div>
        <DialogFooter>
          <Button variant="outline" onClick={onClose}>Cancel</Button>
          <Button disabled={!valid || create.isPending} onClick={() => create.mutate()}>
            {create.isPending && <Loader2 className="size-4 animate-spin" />} Add agent
          </Button>
        </DialogFooter>
      </DialogContent>
    </Dialog>
  );
}
