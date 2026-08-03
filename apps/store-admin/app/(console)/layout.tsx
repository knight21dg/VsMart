"use client";

import * as React from "react";
import { useRouter } from "next/navigation";
import { Loader2, RefreshCw, WifiOff } from "lucide-react";
import { useAuth } from "@/lib/auth/auth-context";
import { clearCachedMe, useStore } from "@/lib/store/store-context";
import { getAccessToken, clearSession } from "@/lib/auth/session";
import { Sidebar } from "@/components/layout/sidebar";
import { Topbar } from "@/components/layout/topbar";
import { NewOrderAlerts } from "@/components/notifications/new-order-alerts";
import { cn } from "@/lib/utils";

export default function ConsoleLayout({ children }: { children: React.ReactNode }) {
  const router = useRouter();
  const { loading: authLoading } = useAuth();
  const { me, loading: meLoading, authRejected, refetch } = useStore();
  const [mobileOpen, setMobileOpen] = React.useState(false);

  const loading = authLoading || meLoading;

  React.useEffect(() => {
    if (loading) return;
    const hasToken = !!getAccessToken();
    if (!hasToken) {
      router.replace("/login");
      return;
    }
    // ONLY a genuine rejection ends the session — a 401/403 from /store/me means
    // the token is dead or this user isn't a member of the store.
    //
    // It used to be `if (error || !me)`, which treated "the server is
    // unreachable" identically: reload the tab with no network — routine at a
    // till running the offline POS — and the cashier was signed out mid-queue,
    // unable to sign back in until the network returned. A network failure now
    // falls through to the cached identity (see store-context).
    if (authRejected) {
      clearSession();
      clearCachedMe();
      router.replace("/login?denied=1");
    }
  }, [loading, authRejected, router]);

  if (loading) {
    return (
      <div className="flex min-h-screen items-center justify-center">
        <Loader2 className="size-6 animate-spin text-muted-foreground" />
      </div>
    );
  }

  // Unreachable server AND nothing cached to fall back on (this device has never
  // loaded the panel). Not a reason to sign anyone out — offer a retry instead.
  if (!me) {
    return (
      <div className="flex min-h-screen flex-col items-center justify-center gap-3 p-6 text-center">
        {authRejected ? (
          <Loader2 className="size-6 animate-spin text-muted-foreground" />
        ) : (
          <>
            <WifiOff className="size-7 text-muted-foreground" />
            <p className="text-sm text-muted-foreground">
              Can&apos;t reach the server. You&apos;re still signed in — reconnect and try again.
            </p>
            <button
              onClick={() => refetch()}
              className="inline-flex items-center gap-2 rounded-md border px-3 py-1.5 text-sm hover:bg-accent"
            >
              <RefreshCw className="size-4" /> Retry
            </button>
          </>
        )}
      </div>
    );
  }

  return (
    <div className="flex h-screen overflow-hidden">
      <NewOrderAlerts />
      <div className="hidden lg:block">
        <Sidebar />
      </div>

      {mobileOpen && (
        <div className="fixed inset-0 z-50 lg:hidden">
          <div className="absolute inset-0 bg-black/50" onClick={() => setMobileOpen(false)} />
          <div className="absolute left-0 top-0 h-full">
            <Sidebar onNavigate={() => setMobileOpen(false)} />
          </div>
        </div>
      )}

      <div className={cn("flex min-w-0 flex-1 flex-col")}>
        <Topbar onMenu={() => setMobileOpen(true)} />
        <main className="flex-1 overflow-y-auto p-4 sm:p-6">
          <div className="mx-auto max-w-7xl space-y-6">{children}</div>
        </main>
      </div>
    </div>
  );
}
