"use client";

import * as React from "react";
import { api } from "@/lib/api/client";
import { useApiMutation } from "@/lib/api/hooks";
import { useAuth } from "@/lib/auth/auth-context";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import {
  Dialog,
  DialogContent,
  DialogDescription,
  DialogFooter,
  DialogHeader,
  DialogTitle,
} from "@/components/ui/dialog";

/**
 * Edit your own name/email — the backend (`PATCH /users/me`, `UserSerializer`)
 * has always accepted this, but no console screen ever exposed a form for it.
 * Phone and role stay read-only here on purpose: phone is the login identity
 * (changing it belongs with a verification step, not a plain text field) and
 * role is assigned by whoever manages accounts, not self-service.
 */
export function EditProfileDialog({
  open,
  onOpenChange,
}: {
  open: boolean;
  onOpenChange: (open: boolean) => void;
}) {
  const { user, refreshUser } = useAuth();
  const [name, setName] = React.useState("");
  const [email, setEmail] = React.useState("");
  const [hydrated, setHydrated] = React.useState(false);

  // Seed from the current user each time the dialog opens, not on every render.
  if (open && !hydrated) {
    setName(user?.name ?? "");
    setEmail(user?.email ?? "");
    setHydrated(true);
  }
  if (!open && hydrated) {
    setHydrated(false);
  }

  const save = useApiMutation(
    () => api.patch("/users/me", { name: name.trim(), email: email.trim() }),
    {
      successMessage: "Profile updated.",
      onDone: async () => {
        await refreshUser();
        onOpenChange(false);
      },
    },
  );

  const ready = name.trim().length > 0;

  return (
    <Dialog open={open} onOpenChange={onOpenChange}>
      <DialogContent>
        <DialogHeader>
          <DialogTitle>Edit profile</DialogTitle>
          <DialogDescription>
            Your name and email, as shown across the console.
          </DialogDescription>
        </DialogHeader>

        <div className="space-y-3">
          <div className="space-y-1.5">
            <Label htmlFor="profile-name">Name</Label>
            <Input
              id="profile-name"
              value={name}
              onChange={(e) => setName(e.target.value)}
            />
          </div>
          <div className="space-y-1.5">
            <Label htmlFor="profile-email">Email</Label>
            <Input
              id="profile-email"
              type="email"
              value={email}
              onChange={(e) => setEmail(e.target.value)}
            />
          </div>
          <div className="space-y-1.5">
            <Label>Phone</Label>
            <Input value={user?.phone ?? ""} disabled />
            <p className="text-xs text-muted-foreground">
              Phone is your sign-in identity — contact a super-admin to change it.
            </p>
          </div>
        </div>

        <DialogFooter>
          <Button variant="outline" onClick={() => onOpenChange(false)}>
            Cancel
          </Button>
          <Button disabled={!ready || save.isPending} onClick={() => save.mutate(undefined)}>
            {save.isPending ? "Saving…" : "Save changes"}
          </Button>
        </DialogFooter>
      </DialogContent>
    </Dialog>
  );
}
