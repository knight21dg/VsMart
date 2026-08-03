"use client";

import * as React from "react";
import { useRouter } from "next/navigation";
import { toast } from "sonner";
import { useStore } from "@/lib/store/store-context";
import { useStoreOrdersSocket, type NewOrderEvent } from "@/lib/realtime/use-store-orders-socket";
import { playNewOrderChime } from "@/lib/notifications/sound";
import { inr } from "@/lib/utils";

/**
 * Case 1 of the "New Order" alert: while this tab is open — even
 * backgrounded — a live order fires a chime, a toast, and (with permission)
 * a browser Notification. Mounted once in the console layout.
 *
 * Case 2 (tab fully closed) is a separate concern: FCM web push, handled by
 * public/sw.js's `push` listener and enabled via the bell button in Topbar.
 */
export function NewOrderAlerts() {
  const router = useRouter();
  const { me } = useStore();

  const onNewOrder = React.useCallback(
    (order: NewOrderEvent) => {
      playNewOrderChime();
      toast(`New order — ${order.code}`, {
        description: `${order.customer ?? "Customer"} · ${order.items} item${order.items === 1 ? "" : "s"} · ${inr(order.value)}`,
        duration: 10_000,
        action: {
          label: "View",
          onClick: () => router.push(`/orders/${order.code}`),
        },
      });
      if (typeof window !== "undefined" && "Notification" in window && Notification.permission === "granted") {
        const n = new Notification("New Order", {
          body: `${order.code} · ${inr(order.value)}`,
          icon: "/icon-192.png",
          tag: order.code,
        });
        n.onclick = () => {
          window.focus();
          router.push(`/orders/${order.code}`);
          n.close();
        };
      }
    },
    [router],
  );

  useStoreOrdersSocket(onNewOrder, Boolean(me));

  return null;
}
