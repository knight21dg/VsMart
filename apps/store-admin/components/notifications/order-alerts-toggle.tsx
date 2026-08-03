"use client";

import * as React from "react";
import { Bell, BellRing } from "lucide-react";
import { toast } from "sonner";
import { api } from "@/lib/api/hooks";
import { Button } from "@/components/ui/button";
import { primeAudio, playNewOrderChime } from "@/lib/notifications/sound";
import { isPushConfigured, requestFcmToken } from "@/lib/notifications/firebase";

const STORAGE_KEY = "vsmart-store-order-alerts-enabled";

/**
 * The bell in Topbar. One click, from a real user gesture, does three things
 * at once (each is a hard requirement Chrome enforces from a gesture, so
 * they can't be split across separate gated buttons):
 *   1. Unlocks the Web Audio chime for the rest of the session.
 *   2. Requests Notification permission (for the tab-open banner).
 *   3. Registers this browser for FCM web push (Case 2 — closed tab).
 *
 * The sound/toast alert itself (Case 1, tab open) works without any of this
 * — see NewOrderAlerts — this button is only about the closed-tab case and
 * about permission for the OS-level Notification popup.
 */
export function OrderAlertsToggle() {
  const [enabled, setEnabled] = React.useState(false);
  const [busy, setBusy] = React.useState(false);

  React.useEffect(() => {
    // Browser-only state (localStorage + Notification permission) — can't be
    // known during SSR/the initial render, so this has to run post-mount.
    // eslint-disable-next-line react-hooks/set-state-in-effect
    setEnabled(
      typeof window !== "undefined" &&
        window.localStorage.getItem(STORAGE_KEY) === "1" &&
        typeof Notification !== "undefined" &&
        Notification.permission === "granted",
    );
  }, []);

  async function enable() {
    primeAudio();
    playNewOrderChime(); // confirms sound works right away
    setBusy(true);
    try {
      if (typeof Notification === "undefined") {
        toast.error("This browser doesn't support notifications.");
        return;
      }
      const permission = await Notification.requestPermission();
      if (permission !== "granted") {
        toast.error("Notifications blocked", {
          description: "Allow notifications for this site in your browser settings to enable alerts.",
        });
        return;
      }
      window.localStorage.setItem(STORAGE_KEY, "1");
      setEnabled(true);
      toast.success("Order alerts enabled", {
        description: "You'll hear a chime for new orders while this tab is open.",
      });

      if (isPushConfigured()) {
        const token = await requestFcmToken();
        if (token) {
          await api.post("/notifications/device-token", { token, platform: "web" });
        }
      }
    } finally {
      setBusy(false);
    }
  }

  return (
    <Button variant={enabled ? "secondary" : "outline"} size="sm" onClick={enable} disabled={busy}>
      {enabled ? <BellRing className="size-4" /> : <Bell className="size-4" />}
      <span className="hidden sm:inline">{enabled ? "Alerts on" : "Enable order alerts"}</span>
    </Button>
  );
}
