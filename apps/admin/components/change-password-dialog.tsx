"use client";

import * as React from "react";
import { api } from "@/lib/api/client";
import { useApiMutation } from "@/lib/api/hooks";
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
 * Change your own console password.
 *
 * There was no way to do this anywhere in the product: the only route to a new
 * password was the signed-*out* forgot-password flow, which texts an OTP to the
 * account's registered phone. Useless for a routine rotation, and impossible
 * for an account whose phone has changed hands.
 *
 * The server re-checks everything this form checks (match, minimum strength,
 * not-the-same-as-current) — the client-side copies exist to answer instantly,
 * not to be the gate.
 */
export function ChangePasswordDialog({
  open,
  onOpenChange,
}: {
  open: boolean;
  onOpenChange: (open: boolean) => void;
}) {
  const [current, setCurrent] = React.useState("");
  const [next, setNext] = React.useState("");
  const [confirm, setConfirm] = React.useState("");

  function reset() {
    setCurrent("");
    setNext("");
    setConfirm("");
  }

  const change = useApiMutation(
    () =>
      api.post("/auth/password/change", {
        current_password: current,
        new_password: next,
        confirm_password: confirm,
      }),
    {
      successMessage: "Password changed.",
      onDone: () => {
        reset();
        onOpenChange(false);
      },
    },
  );

  // Mirrors the server's rules so the button explains itself before a round trip.
  const mismatch = confirm.length > 0 && confirm !== next;
  const tooShort = next.length > 0 && next.length < 8;
  const sameAsCurrent = next.length > 0 && next === current;
  const ready =
    current.length > 0 &&
    next.length >= 8 &&
    confirm === next &&
    !sameAsCurrent;

  return (
    <Dialog
      open={open}
      onOpenChange={(o) => {
        // Never leave a typed password sitting in state behind a closed dialog.
        if (!o) reset();
        onOpenChange(o);
      }}
    >
      <DialogContent>
        <DialogHeader>
          <DialogTitle>Change password</DialogTitle>
          <DialogDescription>
            You&apos;ll stay signed in on this device. Use the new password next time
            you sign in.
          </DialogDescription>
        </DialogHeader>

        <div className="space-y-3">
          <div className="space-y-1.5">
            <Label htmlFor="current-password">Current password</Label>
            <Input
              id="current-password"
              type="password"
              autoComplete="current-password"
              value={current}
              onChange={(e) => setCurrent(e.target.value)}
            />
          </div>
          <div className="space-y-1.5">
            <Label htmlFor="new-password">New password</Label>
            <Input
              id="new-password"
              type="password"
              autoComplete="new-password"
              value={next}
              onChange={(e) => setNext(e.target.value)}
            />
            {tooShort && (
              <p className="text-xs text-destructive">
                Use at least 8 characters.
              </p>
            )}
            {sameAsCurrent && (
              <p className="text-xs text-destructive">
                Choose a password different from your current one.
              </p>
            )}
          </div>
          <div className="space-y-1.5">
            <Label htmlFor="confirm-password">Confirm new password</Label>
            <Input
              id="confirm-password"
              type="password"
              autoComplete="new-password"
              value={confirm}
              onChange={(e) => setConfirm(e.target.value)}
            />
            {mismatch && (
              <p className="text-xs text-destructive">
                The two passwords don&apos;t match.
              </p>
            )}
          </div>
        </div>

        <DialogFooter>
          <Button variant="outline" onClick={() => onOpenChange(false)}>
            Cancel
          </Button>
          <Button
            disabled={!ready || change.isPending}
            onClick={() => change.mutate(undefined)}
          >
            {change.isPending ? "Changing…" : "Change password"}
          </Button>
        </DialogFooter>
      </DialogContent>
    </Dialog>
  );
}
