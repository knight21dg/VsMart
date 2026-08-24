"use client";

import * as React from "react";
import { Camera, KeyRound, LogOut, Menu, UserCog } from "lucide-react";
import { toast } from "sonner";
import { useAuth } from "@/lib/auth/auth-context";
import { api } from "@/lib/api/client";
import { ApiError } from "@/lib/types";
import { Button } from "@/components/ui/button";
import { Badge } from "@/components/ui/badge";
import {
  DropdownMenu,
  DropdownMenuContent,
  DropdownMenuItem,
  DropdownMenuLabel,
  DropdownMenuSeparator,
  DropdownMenuTrigger,
} from "@/components/ui/dropdown-menu";
import { ChangePasswordDialog } from "@/components/change-password-dialog";
import { EditProfileDialog } from "@/components/edit-profile-dialog";
import { GlobalSearch } from "./global-search";
import { titleize } from "@/lib/utils";

/** Small avatar bubble: the uploaded photo when present, else initials. Same
 *  identification purpose as the agent app's face capture — a face on the
 *  account instead of just a name in a list. */
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
      className="flex shrink-0 items-center justify-center rounded-full bg-gradient-to-br from-primary to-[#0b4f57] text-xs font-semibold text-primary-foreground shadow-sm"
    >
      {initials}
    </span>
  );
}

export function Topbar({ onMenu }: { onMenu: () => void }) {
  const { user, logout, refreshUser } = useAuth();
  const [changingPassword, setChangingPassword] = React.useState(false);
  const [editingProfile, setEditingProfile] = React.useState(false);
  const inputRef = React.useRef<HTMLInputElement>(null);
  const [uploading, setUploading] = React.useState(false);

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
    <header className="sticky top-0 z-30 flex h-16 items-center gap-3 border-b bg-card/85 px-5 backdrop-blur-md">
      <Button variant="ghost" size="icon" className="lg:hidden" onClick={onMenu}>
        <Menu />
      </Button>
      <GlobalSearch />
      <div className="ml-auto flex items-center gap-3">
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
            <button className="flex items-center gap-2 rounded-full py-1 pl-1 pr-2.5 transition-colors hover:bg-accent">
              <Avatar url={user?.avatar_url} name={user?.name || user?.phone} />
              <span className="hidden text-left sm:block">
                <span className="block text-sm font-medium leading-tight">{user?.name || "Admin"}</span>
                <span className="block text-[11px] leading-tight text-muted-foreground">{user?.phone}</span>
              </span>
            </button>
          </DropdownMenuTrigger>
          <DropdownMenuContent align="end" className="w-56">
            <DropdownMenuLabel className="flex items-center gap-2">
              <Avatar url={user?.avatar_url} name={user?.name || user?.phone} size={36} />
              <span className="flex flex-col gap-1">
                <span>{user?.name || "Admin"}</span>
                <Badge variant="secondary" className="w-fit">{titleize(user?.role)}</Badge>
              </span>
            </DropdownMenuLabel>
            <DropdownMenuSeparator />
            <DropdownMenuItem disabled={uploading} onSelect={() => inputRef.current?.click()}>
              <Camera /> {uploading ? "Uploading…" : user?.avatar_url ? "Change photo" : "Add photo"}
            </DropdownMenuItem>
            <DropdownMenuItem onSelect={() => setEditingProfile(true)}>
              <UserCog /> Edit profile
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

      <EditProfileDialog
        open={editingProfile}
        onOpenChange={setEditingProfile}
      />
      <ChangePasswordDialog
        open={changingPassword}
        onOpenChange={setChangingPassword}
      />
    </header>
  );
}
