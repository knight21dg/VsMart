"use client";

import * as React from "react";
import { useQuery } from "@tanstack/react-query";
import { Camera, Clock, KeyRound, LogOut, Menu, Store } from "lucide-react";
import { toast } from "sonner";
import { useAuth } from "@/lib/auth/auth-context";
import { useStore } from "@/lib/store/store-context";
import { api, useApiMutation } from "@/lib/api/hooks";
import { ApiError } from "@/lib/types";
import { Button } from "@/components/ui/button";
import { Badge } from "@/components/ui/badge";
import { OrderAlertsToggle } from "@/components/notifications/order-alerts-toggle";
import { ChangePasswordDialog } from "@/components/change-password-dialog";
import {
  DropdownMenu,
  DropdownMenuContent,
  DropdownMenuItem,
  DropdownMenuLabel,
  DropdownMenuSeparator,
  DropdownMenuTrigger,
} from "@/components/ui/dropdown-menu";

/** Small avatar bubble: the uploaded photo when present, else initials —
 *  the same identification purpose as the agent app's face capture. */
function Avatar({ url, name, size = 32 }: { url?: string | null; name?: string | null; size?: number }) {
  const initials = (name || "?")
    .split(" ")
    .map((s) => s[0])
    .slice(0, 2)
    .join("")
    .toUpperCase();
  if (url) {
    // eslint-disable-next-line @next/next/no-img-element
    return (
      <img
        src={api.assetUrl(url)}
        alt=""
        style={{ width: size, height: size }}
        className="shrink-0 rounded-full object-cover shadow-sm"
      />
    );
  }
  return (
    <span
      style={{ width: size, height: size }}
      className="flex shrink-0 items-center justify-center rounded-full bg-primary text-xs font-semibold text-primary-foreground"
    >
      {initials}
    </span>
  );
}

interface AttendanceState {
  date: string;
  checkInAt: string | null;
  checkOutAt: string | null;
  /** Server-derived: checked in today and not yet checked out. */
  clockedIn: boolean;
}

export function Topbar({ onMenu }: { onMenu: () => void }) {
  const { user, logout, refreshUser } = useAuth();
  const { me } = useStore();
  const inputRef = React.useRef<HTMLInputElement>(null);
  const [uploading, setUploading] = React.useState(false);
  const [changingPassword, setChangingPassword] = React.useState(false);

  // Attendance comes from the server, not from a local boolean. The old code
  // held `useState(false)` and flipped it on each click, so the button showed
  // "Clock in" to someone who had been on shift since 08:00, and any navigation
  // that remounted the topbar silently reset it back to "out".
  const attendance = useQuery({
    queryKey: ["store", "attendance", "me"],
    queryFn: () => api.get<AttendanceState>("/store/staff/attendance/me"),
    staleTime: 60_000,
  });
  const clockedIn = attendance.data?.clockedIn ?? false;

  const clock = useApiMutation(
    (action: "check-in" | "check-out") =>
      api.post<AttendanceState>(`/store/staff/attendance/${action}`, {}),
    {
      // The write returns the authoritative state; invalidating keeps the
      // roster page (which reads the same attendance) in step too.
      invalidate: [["store", "attendance"]],
      successMessage: "Attendance updated",
    }
  );

  async function pickPhoto(file: File | null) {
    if (!file) return;
    setUploading(true);
    try {
      const fd = new FormData();
      fd.append("file", file);
      await api.upload<{ avatar_url: string }>("/users/me/avatar", fd);
      await refreshUser();
      toast.success("Profile photo updated");
    } catch (e) {
      toast.error(e instanceof ApiError ? e.message : "Photo upload failed.");
    } finally {
      setUploading(false);
      if (inputRef.current) inputRef.current.value = "";
    }
  }

  return (
    <header className="sticky top-0 z-30 flex h-14 items-center gap-3 border-b bg-card/80 px-4 backdrop-blur">
      <Button variant="ghost" size="icon" className="lg:hidden" onClick={onMenu}>
        <Menu />
      </Button>

      <div className="flex items-center gap-2 text-sm">
        <Store className="size-4 text-primary" />
        <span className="font-medium">{me?.store.name || "Store"}</span>
        {me && (
          <Badge variant="secondary" className="hidden sm:inline-flex">
            {me.staffRoleLabel}
          </Badge>
        )}
      </div>

      <div className="ml-auto flex items-center gap-2">
        <OrderAlertsToggle />

        <Button
          variant={clockedIn ? "secondary" : "outline"}
          size="sm"
          onClick={() => clock.mutate(clockedIn ? "check-out" : "check-in")}
          // Disabled until the real state has loaded, so the first click can't
          // fire the wrong action against an assumed-false default.
          disabled={clock.isPending || attendance.isPending}
          title={clockedIn ? "You are on shift" : "You are not clocked in"}
        >
          <Clock className="size-4" />
          <span className="hidden sm:inline">
            {attendance.isPending ? "…" : clockedIn ? "Clock out" : "Clock in"}
          </span>
        </Button>

        {/* capture="user" hints the front/selfie camera on a phone browser; a
            desktop browser just opens the normal file picker. */}
        <input
          ref={inputRef}
          type="file"
          accept="image/png,image/jpeg,image/webp"
          capture="user"
          className="hidden"
          onChange={(e) => pickPhoto(e.target.files?.[0] ?? null)}
        />
        <DropdownMenu>
          <DropdownMenuTrigger asChild>
            <button className="flex items-center gap-2 rounded-full py-1 pl-1 pr-2 transition-colors hover:bg-accent">
              <Avatar url={user?.avatar_url} name={user?.name || user?.phone} />
              <span className="hidden text-left sm:block">
                <span className="block text-sm font-medium leading-tight">{user?.name || "Staff"}</span>
                <span className="block text-[11px] leading-tight text-muted-foreground">{user?.phone}</span>
              </span>
            </button>
          </DropdownMenuTrigger>
          <DropdownMenuContent align="end" className="w-56">
            <DropdownMenuLabel className="flex items-center gap-2">
              <Avatar url={user?.avatar_url} name={user?.name || user?.phone} size={36} />
              <span className="flex flex-col gap-1">
                <span>{me?.title || user?.name || "Staff"}</span>
                <Badge variant="secondary" className="w-fit">{me?.staffRoleLabel || "Store staff"}</Badge>
              </span>
            </DropdownMenuLabel>
            <DropdownMenuSeparator />
            <DropdownMenuItem disabled={uploading} onSelect={() => inputRef.current?.click()}>
              <Camera /> {uploading ? "Uploading…" : user?.avatar_url ? "Change photo" : "Add photo"}
            </DropdownMenuItem>
            <DropdownMenuItem onSelect={() => setChangingPassword(true)}>
              <KeyRound /> Change password
            </DropdownMenuItem>
            <DropdownMenuSeparator />
            <DropdownMenuItem destructive onSelect={() => logout()}>
              <LogOut /> Sign out
            </DropdownMenuItem>
          </DropdownMenuContent>
        </DropdownMenu>
      </div>

      <ChangePasswordDialog
        open={changingPassword}
        onOpenChange={setChangingPassword}
      />
    </header>
  );
}
