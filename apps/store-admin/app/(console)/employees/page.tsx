"use client";

import * as React from "react";
import { useQuery } from "@tanstack/react-query";
import type { ColumnDef } from "@tanstack/react-table";
import { Loader2, Plus, ShieldCheck, UserCog } from "lucide-react";
import { api, useApiMutation } from "@/lib/api/hooks";
import { useStore } from "@/lib/store/store-context";
import { PageHeader } from "@/components/page-header";
import { DataTable } from "@/components/data-table";
import { RequirePerm } from "@/components/permission-gate";
import { ConfirmDialog } from "@/components/confirm-dialog";
import { StatusBadge, BoolBadge } from "@/components/status-badge";
import {
  Dialog,
  DialogContent,
  DialogDescription,
  DialogFooter,
  DialogHeader,
  DialogTitle,
} from "@/components/ui/dialog";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import { Badge } from "@/components/ui/badge";
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from "@/components/ui/select";
import { fmtDate, titleize } from "@/lib/utils";

interface StaffRow {
  id: string;
  userId: string;
  name: string;
  phone: string;
  staffRole: string;
  staffRoleLabel: string;
  title: string;
  employeeCode: string;
  isManager: boolean;
  isActive: boolean;
  joinedOn: string | null;
  permissions: string[];
  permissionCount: number;
  presentToday: boolean;
}

interface Catalog {
  groups: { module: string; permissions: { key: string; label: string }[] }[];
  roleDefaults: Record<string, string[]>;
  roles: { value: string; label: string }[];
}

export default function EmployeesPage() {
  return (
    <RequirePerm perm="employees.view">
      <EmployeesInner />
    </RequirePerm>
  );
}

function EmployeesInner() {
  const { hasPerm } = useStore();
  const canManage = hasPerm("employees.manage");
  const [editing, setEditing] = React.useState<StaffRow | null>(null);
  const [creating, setCreating] = React.useState(false);

  const staffQ = useQuery({ queryKey: ["store", "staff"], queryFn: () => api.get<StaffRow[]>("/store/staff") });
  const catalogQ = useQuery({ queryKey: ["store", "permissions"], queryFn: () => api.get<Catalog>("/store/permissions") });

  const columns: ColumnDef<StaffRow, unknown>[] = [
    {
      header: "Staff",
      cell: ({ row }) => (
        <div>
          <div className="font-medium">{row.original.name}</div>
          <div className="text-xs text-muted-foreground">{row.original.phone}</div>
        </div>
      ),
    },
    {
      header: "Role",
      cell: ({ row }) => (
        <div className="flex flex-col gap-0.5">
          <Badge variant={row.original.isManager ? "default" : "secondary"} className="w-fit">
            {row.original.staffRoleLabel}
          </Badge>
          {row.original.title && <span className="text-xs text-muted-foreground">{row.original.title}</span>}
        </div>
      ),
    },
    {
      header: "Permissions",
      cell: ({ row }) =>
        row.original.isManager ? (
          <span className="flex items-center gap-1 text-sm text-primary"><ShieldCheck className="size-3.5" /> All access</span>
        ) : (
          <span className="text-sm">{row.original.permissionCount} granted</span>
        ),
    },
    { header: "Present", cell: ({ row }) => <BoolBadge value={row.original.presentToday} trueLabel="In" falseLabel="—" /> },
    { header: "Status", cell: ({ row }) => <StatusBadge status={row.original.isActive ? "active" : "suspended"} /> },
    {
      header: "",
      id: "actions",
      cell: ({ row }) =>
        canManage ? (
          <Button variant="outline" size="sm" onClick={() => setEditing(row.original)}>Manage</Button>
        ) : null,
    },
  ];

  return (
    <div className="space-y-5">
      <PageHeader
        title="Employees"
        description="Your store's staff, their roles and exactly what they can do."
        actions={
          canManage ? (
            <Button onClick={() => setCreating(true)}><Plus className="size-4" /> Add staff</Button>
          ) : undefined
        }
      />

      <DataTable
        columns={columns}
        data={staffQ.data ?? []}
        loading={staffQ.isLoading}
        error={staffQ.error ? "Couldn't load staff." : null}
        onRetry={() => staffQ.refetch()}
        emptyMessage="No staff yet. Add your first team member."
      />

      {(creating || editing) && catalogQ.data && (
        <StaffDialog
          catalog={catalogQ.data}
          staff={editing}
          onClose={() => {
            setCreating(false);
            setEditing(null);
          }}
        />
      )}
    </div>
  );
}

function StaffDialog({ catalog, staff, onClose }: { catalog: Catalog; staff: StaffRow | null; onClose: () => void }) {
  const isEdit = !!staff;
  const [name, setName] = React.useState(staff?.name ?? "");
  const [phone, setPhone] = React.useState(staff?.phone ?? "");
  const [title, setTitle] = React.useState(staff?.title ?? "");
  const [role, setRole] = React.useState(staff?.staffRole ?? "cashier");
  const [perms, setPerms] = React.useState<Set<string>>(new Set(staff?.permissions ?? catalog.roleDefaults["cashier"] ?? []));
  const [active, setActive] = React.useState(staff?.isActive ?? true);
  // Sign-in credentials. The panel authenticates with email + password, so a
  // staff member created without these could never actually get in.
  const [email, setEmail] = React.useState("");
  const [password, setPassword] = React.useState("");
  const [confirmDeactivate, setConfirmDeactivate] = React.useState(false);

  const isManager = role === "manager";

  // When picking a (non-manager) role, seed its default permission bundle.
  function pickRole(r: string) {
    setRole(r);
    if (r !== "manager") setPerms(new Set(catalog.roleDefaults[r] ?? []));
  }

  function toggle(key: string) {
    setPerms((prev) => {
      const next = new Set(prev);
      if (next.has(key)) next.delete(key);
      else next.add(key);
      return next;
    });
  }

  const create = useApiMutation(
    (body: unknown) => api.post("/store/staff", body),
    { invalidate: [["store", "staff"]], successMessage: "Staff member added", onDone: onClose }
  );
  const update = useApiMutation(
    (body: unknown) => api.patch(`/store/staff/${staff!.id}`, body),
    { invalidate: [["store", "staff"]], successMessage: "Staff updated", onDone: onClose }
  );
  const pending = create.isPending || update.isPending;

  function submit() {
    const permissions = isManager ? [] : Array.from(perms);
    if (isEdit) {
      // Deactivating is the only removal path — make it deliberate.
      if (staff!.isActive && !active) {
        setConfirmDeactivate(true);
        return;
      }
      update.mutate({ staffRole: role, permissions, title, isActive: active, name });
    } else {
      create.mutate({ phone, name, email, password, staffRole: role, permissions, title });
    }
  }

  return (
    <Dialog open onOpenChange={(o) => !o && onClose()}>
      <DialogContent className="max-h-[90vh] max-w-2xl overflow-y-auto">
        <DialogHeader>
          <DialogTitle className="flex items-center gap-2">
            <UserCog className="size-5" /> {isEdit ? `Manage ${staff!.name}` : "Add staff member"}
          </DialogTitle>
          <DialogDescription>
            Pick a role for sensible defaults, then fine-tune exactly what they can access.
          </DialogDescription>
        </DialogHeader>

        <div className="space-y-4">
          <div className="grid gap-3 sm:grid-cols-2">
            <div className="space-y-1.5">
              <Label>Name</Label>
              <Input value={name} onChange={(e) => setName(e.target.value)} placeholder="Full name" />
            </div>
            <div className="space-y-1.5">
              <Label>Phone {isEdit && <span className="text-muted-foreground">(login)</span>}</Label>
              <Input value={phone} onChange={(e) => setPhone(e.target.value)} placeholder="9876543210" disabled={isEdit} />
            </div>
            <div className="space-y-1.5">
              <Label>Role</Label>
              <Select value={role} onValueChange={pickRole}>
                <SelectTrigger><SelectValue /></SelectTrigger>
                <SelectContent>
                  {catalog.roles.map((r) => (
                    <SelectItem key={r.value} value={r.value}>{r.label}</SelectItem>
                  ))}
                </SelectContent>
              </Select>
            </div>
            <div className="space-y-1.5">
              <Label>Title</Label>
              <Input value={title} onChange={(e) => setTitle(e.target.value)} placeholder="e.g. Floor Assistant" />
            </div>
          </div>

          {!isEdit && (
            <div className="space-y-3 rounded-lg border bg-muted/30 p-3">
              <div>
                <p className="text-sm font-medium">Sign-in details</p>
                <p className="text-xs text-muted-foreground">
                  Staff sign in to this panel with an email and password. Share these
                  with them directly — they can change the password from the login
                  page&apos;s &ldquo;Forgot password&rdquo; link.
                </p>
              </div>
              <div className="grid gap-3 sm:grid-cols-2">
                <div className="space-y-1.5">
                  <Label>Email</Label>
                  <Input
                    type="email"
                    autoComplete="off"
                    value={email}
                    onChange={(e) => setEmail(e.target.value)}
                    placeholder="name@yourstore.com"
                  />
                </div>
                <div className="space-y-1.5">
                  <Label>Temporary password</Label>
                  <Input
                    type="password"
                    autoComplete="new-password"
                    value={password}
                    onChange={(e) => setPassword(e.target.value)}
                    placeholder="At least 8 characters"
                  />
                </div>
              </div>
            </div>
          )}

          {isManager ? (
            <div className="flex items-center gap-2 rounded-lg border bg-primary/5 px-4 py-3 text-sm">
              <ShieldCheck className="size-4 text-primary" />
              Managers have full access to every part of the store panel.
            </div>
          ) : (
            <div className="space-y-3">
              <div className="flex items-center justify-between">
                <Label>Permissions</Label>
                <span className="text-xs text-muted-foreground">{perms.size} selected</span>
              </div>
              <div className="space-y-3 rounded-lg border p-3">
                {catalog.groups.map((g) => (
                  <div key={g.module}>
                    <p className="mb-1.5 text-xs font-semibold uppercase tracking-wide text-muted-foreground">{g.module}</p>
                    <div className="grid gap-1.5 sm:grid-cols-2">
                      {g.permissions.map((p) => (
                        <label key={p.key} className="flex cursor-pointer items-center gap-2 rounded-md px-2 py-1.5 text-sm hover:bg-accent">
                          <input
                            type="checkbox"
                            className="size-4 accent-[var(--color-primary)]"
                            checked={perms.has(p.key)}
                            onChange={() => toggle(p.key)}
                          />
                          {p.label}
                        </label>
                      ))}
                    </div>
                  </div>
                ))}
              </div>
            </div>
          )}

          {isEdit && (
            <label className="flex cursor-pointer items-center gap-2 text-sm">
              <input type="checkbox" className="size-4 accent-[var(--color-primary)]" checked={active} onChange={(e) => setActive(e.target.checked)} />
              Active (can sign in)
            </label>
          )}
        </div>

        <DialogFooter>
          <Button variant="outline" onClick={onClose} disabled={pending}>Cancel</Button>
          <Button
            onClick={submit}
            disabled={
              pending ||
              (!isEdit && (!phone || phone.length < 10 || !email.trim() || password.length < 8))
            }
          >
            {pending && <Loader2 className="size-4 animate-spin" />}
            {isEdit ? "Save changes" : "Add staff"}
          </Button>
        </DialogFooter>

        <ConfirmDialog
          open={confirmDeactivate}
          onOpenChange={setConfirmDeactivate}
          title={`Deactivate ${staff?.name || "this staff member"}?`}
          description={
            "They will be signed out and won't be able to access the store panel — " +
            "no POS, no orders, no stock. Their past sales and audit history stay intact, " +
            "and you can reactivate them at any time."
          }
          confirmLabel="Deactivate"
          destructive
          loading={pending}
          onConfirm={() => {
            setConfirmDeactivate(false);
            update.mutate({
              staffRole: role,
              permissions: isManager ? [] : Array.from(perms),
              title,
              isActive: false,
              name,
            });
          }}
        />
      </DialogContent>
    </Dialog>
  );
}
