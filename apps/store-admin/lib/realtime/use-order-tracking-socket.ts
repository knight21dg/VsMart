"use client";

import * as React from "react";
import { API_BASE, ensureFreshToken } from "@/lib/api/client";

export interface TrackingSnapshot {
  orderCode: string;
  status: string;
  deliveryStatus: string | null;
  agentName: string | null;
  agentPhone: string | null;
  agentPhotoUrl: string | null;
  latitude: number | null;
  longitude: number | null;
  eta: string | null;
  destLat: number | null;
  destLng: number | null;
}

async function wsUrl(path: string): Promise<string> {
  const token = (await ensureFreshToken()) ?? "";
  const base = API_BASE.replace(/^http/, "ws").replace(/\/api\/v1\/?$/, "");
  const sep = path.startsWith("/") ? "" : "/";
  return `${base}${sep}${path}?token=${encodeURIComponent(token)}`;
}

/**
 * Subscribes to ws/orders/<code>/tracking for one delivery's live position —
 * the same channel the customer app watches, opened here so a store manager
 * can see exactly where their own agent is without leaving the panel.
 * Auto-reconnects with capped backoff (refreshing the access token first if
 * it's expired, same as useStoreOrdersSocket) while `enabled`.
 */
export function useOrderTrackingSocket(
  orderCode: string | null,
  enabled: boolean,
): { snapshot: TrackingSnapshot | null; connected: boolean } {
  const [snapshot, setSnapshot] = React.useState<TrackingSnapshot | null>(null);
  const [connected, setConnected] = React.useState(false);

  React.useEffect(() => {
    setSnapshot(null);
    if (!enabled || !orderCode) return;

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
      const url = await wsUrl(`/ws/orders/${encodeURIComponent(orderCode)}/tracking`);
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
          if (msg?.type === "tracking" && msg.data) {
            setSnapshot(msg.data as TrackingSnapshot);
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
  }, [orderCode, enabled]);

  return { snapshot, connected };
}
