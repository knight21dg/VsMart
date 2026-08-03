"use client";

import * as React from "react";
import { API_BASE, ensureFreshToken } from "@/lib/api/client";

/** Build the ws(s):// URL for a backend WebSocket path, carrying the JWT as
 * `?token=`. Derives the host from API_BASE (…/api/v1 → ws root). Refreshes
 * the token first if it's expired — a tab left open longer than the 30-min
 * access-token lifetime used to keep reconnecting with a dead token and get
 * rejected forever, silently going stale with no way to recover short of a
 * manual reload. */
async function wsUrl(path: string): Promise<string> {
  const token = (await ensureFreshToken()) ?? "";
  const base = API_BASE.replace(/^http/, "ws").replace(/\/api\/v1\/?$/, "");
  const sep = path.startsWith("/") ? "" : "/";
  return `${base}${sep}${path}?token=${encodeURIComponent(token)}`;
}

export interface NewOrderEvent {
  code: string;
  placedAt: string | null;
  customer: string | null;
  items: number;
  value: number;
  paymentMethod: string;
}

/**
 * Subscribes to ws/store/orders for this store's live "New Order" pushes.
 * Auto-reconnects with capped exponential backoff, same pattern as the admin
 * console's delivery socket. Only connects once `enabled` (i.e. once the
 * signed-in staff member's store membership has resolved).
 */
export function useStoreOrdersSocket(
  onNewOrder: (order: NewOrderEvent) => void,
  enabled: boolean,
): { connected: boolean } {
  const cbRef = React.useRef(onNewOrder);
  const [connected, setConnected] = React.useState(false);

  React.useEffect(() => {
    cbRef.current = onNewOrder;
  }, [onNewOrder]);

  React.useEffect(() => {
    if (!enabled) return;
    let ws: WebSocket | null = null;
    let closed = false;
    let retry = 0;
    let timer: ReturnType<typeof setTimeout> | undefined;

    const schedule = () => {
      retry = Math.min(retry + 1, 6);
      timer = setTimeout(connect, Math.min(1000 * 2 ** retry, 15000));
    };

    const connect = async () => {
      if (closed) return;
      const url = await wsUrl("/ws/store/orders");
      if (closed) return;
      let socket: WebSocket;
      try {
        socket = new WebSocket(url);
      } catch {
        schedule();
        return;
      }
      ws = socket;
      socket.onopen = () => {
        retry = 0;
        setConnected(true);
      };
      socket.onmessage = (e) => {
        try {
          const msg = JSON.parse(e.data);
          if (msg?.type === "new_order" && msg.data) {
            cbRef.current(msg.data as NewOrderEvent);
          }
        } catch {
          /* ignore malformed frames */
        }
      };
      socket.onclose = () => {
        setConnected(false);
        if (!closed) schedule();
      };
      socket.onerror = () => {
        try {
          socket.close();
        } catch {
          /* noop */
        }
      };
    };

    connect();
    return () => {
      closed = true;
      if (timer) clearTimeout(timer);
      try {
        ws?.close();
      } catch {
        /* noop */
      }
    };
  }, [enabled]);

  return { connected };
}
