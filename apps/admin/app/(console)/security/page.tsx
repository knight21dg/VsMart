"use client";

import * as React from "react";
import { useQuery } from "@tanstack/react-query";
import { Check, Loader2, Minus, Plus, ShieldCheck } from "lucide-react";
import { api } from "@/lib/api/client";
import { useApiMutation } from "@/lib/api/hooks";
import { useAuth } from "@/lib/auth/auth-context";
import { PageHeader } from "@/components/page-header";
import { ConfirmDialog } from "@/components/confirm-dialog";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from "@/components/ui/table";
import { Badge } from "@/components/ui/badge";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from "@/components/ui/select";
import { Dialog, DialogContent, DialogFooter, DialogHeader, DialogTitle } from "@/components/ui/dialog";
import { NotWiredYet, LoadingState, ErrorState } from "@/components/states";
import { titleize } from "@/lib/utils";

interface Staff { id: string; phone: string; name: string; role: string; isActive: boolean }

const ROLES = ["Super Admin", "Admin", "Agent", "Customer"] as const;
// RBAC matrix derived from core/permissions.py (IsAdmin = admin+superadmin,
// IsSuperAdmin = superadmin-only writes, IsAgent, IsCustomer).
const MATRIX: { cap: string; access: [boolean, boolean, boolean, boolean] }[] = [
  { cap: "View admin console", access: [true, true, false, false] },
  { cap: "Manage stores & zones (write)", access: [true, false, false, false] },
  { cap: "Create/edit staff", access: [true, false, false, false] },
  { cap: "System settings & credit rules (write)", access: [true, false, false, false] },
  { cap: "Product Master & inventory", access: [true, true, false, false] },
  { cap: "Credit decisions & limits", access: [true, true, false, false] },
  { cap: "KYC / verification decisions", access: [true, true, false, false] },
  { cap: "Orders, delivery & collections ops", access: [true, true, false, false] },
  { cap: "Field delivery & collection tasks", access: [false, false, true, false] },
  { cap: "Place orders & use credit", access: [false, false, false, true] },
];

// What POST /admin/staff accepts, and what a role Select may offer. `customer`
// and `store_staff` are deliberately absent: a store staff login is created from
// the store panel (it needs a store membership), and demoting an admin to
// customer is not a governance action anyone wants one click away.
const ASSIGNABLE_ROLES = ["superadmin", "admin", "agent"] as const;
const CREATABLE_ROLES = ["admin", "agent"] as const;

export default function SecurityPage() {
  const [creating, setCreating] = React.useState(false);
  const [toDisable, setToDisable] = React.useState<Staff | null>(null);
  const staff = useQuery({ queryKey: ["security", "staff"], queryFn: () => api.get<Staff[]>("/admin/staff") });
  const me = useAuth().user;

  const update = useApiMutation(
    (v: { id: string; body: Record<string, unknown> }) =>
      api.patch(`/admin/staff/${v.id}`, v.body),
    { invalidate: [["security", "staff"]], successMessage: "Staff account updated" },
  );

  return (
    <>
      <PageHeader title="Security Center" description="Role-based access control and account governance." />

      <Card>
        <CardHeader><CardTitle className="flex items-center gap-2"><ShieldCheck className="size-4" /> Role Permission Matrix</CardTitle></CardHeader>
        <CardContent className="p-0">
          <Table>
            <TableHeader>
              <TableRow className="hover:bg-transparent">
                <TableHead>Capability</TableHead>
                {ROLES.map((r) => <TableHead key={r} className="text-center">{r}</TableHead>)}
              </TableRow>
            </TableHeader>
            <TableBody>
              {MATRIX.map((row) => (
                <TableRow key={row.cap}>
                  <TableCell className="font-medium">{row.cap}</TableCell>
                  {row.access.map((ok, i) => (
                    <TableCell key={i} className="text-center">
                      {ok ? <Check className="mx-auto size-4 text-[var(--color-success)]" /> : <Minus className="mx-auto size-4 text-muted-foreground/40" />}
                    </TableCell>
                  ))}
                </TableRow>
              ))}
            </TableBody>
          </Table>
        </CardContent>
      </Card>

      <Card>
        <CardHeader className="flex flex-row items-center justify-between gap-3">
          <CardTitle>Staff Accounts &amp; Roles</CardTitle>
          <Button size="sm" onClick={() => setCreating(true)}>
            <Plus className="size-4" /> New staff account
          </Button>
        </CardHeader>
        <CardContent className="p-0">
          {staff.isLoading ? (
            <LoadingState />
          ) : staff.isError ? (
            <div className="p-4">
              <ErrorState message="Couldn't load staff accounts." onRetry={() => staff.refetch()} />
            </div>
          ) : (
            <Table>
              <TableHeader>
                <TableRow className="hover:bg-transparent">
                  <TableHead>Name</TableHead><TableHead>Phone</TableHead><TableHead>Role</TableHead>
                  <TableHead>Status</TableHead><TableHead className="text-right">Manage</TableHead>
                </TableRow>
              </TableHeader>
              <TableBody>
                {(staff.data ?? []).map((u) => {
                  const isSelf = me?.id === u.id;
                  return (
                    <TableRow key={u.id}>
                      <TableCell className="font-medium">
                        {u.name || "—"}
                        {isSelf && <span className="ml-2 text-xs text-muted-foreground">(you)</span>}
                      </TableCell>
                      <TableCell className="font-mono text-xs">{u.phone}</TableCell>
                      <TableCell>
                        {/* Changing your own role is refused server-side too —
                            it's how a super-admin locks themselves out. */}
                        <Select
                          value={u.role}
                          disabled={isSelf || update.isPending}
                          onValueChange={(role) => update.mutate({ id: u.id, body: { role } })}
                        >
                          <SelectTrigger className="h-8 w-[150px] text-xs"><SelectValue /></SelectTrigger>
                          <SelectContent>
                            {ASSIGNABLE_ROLES.map((r) => (
                              <SelectItem key={r} value={r}>{titleize(r)}</SelectItem>
                            ))}
                          </SelectContent>
                        </Select>
                      </TableCell>
                      <TableCell>
                        <Badge variant={u.isActive ? "success" : "destructive"}>
                          {u.isActive ? "Active" : "Disabled"}
                        </Badge>
                      </TableCell>
                      <TableCell className="text-right">
                        {u.isActive ? (
                          <Button
                            variant="ghost" size="sm"
                            disabled={isSelf || update.isPending}
                            onClick={() => setToDisable(u)}
                          >
                            Disable
                          </Button>
                        ) : (
                          <Button
                            variant="ghost" size="sm"
                            disabled={update.isPending}
                            onClick={() => update.mutate({ id: u.id, body: { isActive: true } })}
                          >
                            Re-enable
                          </Button>
                        )}
                      </TableCell>
                    </TableRow>
                  );
                })}
                {(staff.data ?? []).length === 0 && (
                  <TableRow><TableCell colSpan={5} className="py-8 text-center text-sm text-muted-foreground">No staff accounts.</TableCell></TableRow>
                )}
              </TableBody>
            </Table>
          )}
        </CardContent>
      </Card>

      {creating && <StaffDialog onClose={() => setCreating(false)} />}

      <ConfirmDialog
        open={!!toDisable}
        onOpenChange={(o) => !o && setToDisable(null)}
        title={`Disable ${toDisable?.name || toDisable?.phone}?`}
        description={
          `They will be signed out and can no longer reach the admin console. ` +
          `Their audit history and everything they actioned stays intact, and you ` +
          `can re-enable them at any time.`
        }
        confirmLabel="Disable account"
        destructive
        loading={update.isPending}
        onConfirm={() => {
          if (toDisable) update.mutate({ id: toDisable.id, body: { isActive: false } });
          setToDisable(null);
        }}
      />

      <div className="grid gap-4 lg:grid-cols-3">
        <Card><CardHeader><CardTitle className="text-base">Two-Factor Auth</CardTitle></CardHeader><CardContent><NotWiredYet note="VS Mart is OTP-only today; a second factor after login isn't implemented yet." /></CardContent></Card>
        <Card><CardHeader><CardTitle className="text-base">IP Restrictions</CardTitle></CardHeader><CardContent><NotWiredYet note="IP allow-listing for admin access isn't configured in the backend yet." /></CardContent></Card>
        <Card><CardHeader><CardTitle className="text-base">Session Management</CardTitle></CardHeader><CardContent><NotWiredYet note="JWT logout blacklists tokens; a live session roster/force-logout endpoint isn't built yet." /></CardContent></Card>
      </div>
    </>
  );
}

/**
 * Create an admin or field-agent login.
 *
 * The console had no way to create staff at all — `POST /admin/staff` existed
 * and was audited, and nothing called it. A new account signs in with their
 * phone via OTP, so no password is collected here; the optional one only
 * enables the email/password route, which needs an email the endpoint doesn't
 * accept yet.
 */
function StaffDialog({ onClose }: { onClose: () => void }) {
  const [role, setRole] = React.useState<string>("admin");
  const [name, setName] = React.useState("");
  const [phone, setPhone] = React.useState("");
  const [pincodes, setPincodes] = React.useState("");

  const create = useApiMutation<void>(
    () => api.post("/admin/staff", {
      role,
      name: name.trim(),
      phone: phone.trim(),
      ...(role === "agent"
        ? { assignedPincodes: pincodes.split(",").map((p) => p.trim()).filter(Boolean) }
        : {}),
    }),
    {
      invalidate: [["security", "staff"]],
      successMessage: "Staff account created",
      onDone: onClose,
    },
  );

  // E.164 is what the backend normalises to; 10 digits is the minimum that can
  // possibly be a valid Indian mobile.
  const digits = phone.replace(/\D/g, "");
  const valid = digits.length >= 10 && !!name.trim();

  return (
    <Dialog open onOpenChange={(o) => !o && onClose()}>
      <DialogContent className="max-w-md">
        <DialogHeader><DialogTitle>New staff account</DialogTitle></DialogHeader>
        <div className="space-y-3 py-1">
          <div className="space-y-1.5">
            <Label>Role</Label>
            <Select value={role} onValueChange={setRole}>
              <SelectTrigger><SelectValue /></SelectTrigger>
              <SelectContent>
                {CREATABLE_ROLES.map((r) => (
                  <SelectItem key={r} value={r}>{titleize(r)}</SelectItem>
                ))}
              </SelectContent>
            </Select>
          </div>
          <div className="space-y-1.5">
            <Label>Name</Label>
            <Input value={name} onChange={(e) => setName(e.target.value)} placeholder="Full name" />
          </div>
          <div className="space-y-1.5">
            <Label>Phone</Label>
            <Input
              value={phone}
              onChange={(e) => setPhone(e.target.value)}
              placeholder="9876543210"
            />
            <p className="text-xs text-muted-foreground">
              They sign in with this number and a one-time code — share it with them directly.
            </p>
          </div>
          {role === "agent" && (
            <div className="space-y-1.5">
              <Label>Assigned pincodes</Label>
              <Input
                value={pincodes}
                onChange={(e) => setPincodes(e.target.value)}
                placeholder="560001, 560002"
              />
              <p className="text-xs text-muted-foreground">Comma separated. Optional.</p>
            </div>
          )}
        </div>
        <DialogFooter>
          <Button variant="outline" onClick={onClose} disabled={create.isPending}>Cancel</Button>
          <Button onClick={() => create.mutate()} disabled={!valid || create.isPending}>
            {create.isPending && <Loader2 className="size-4 animate-spin" />} Create account
          </Button>
        </DialogFooter>
      </DialogContent>
    </Dialog>
  );
}
