"use client";

import * as React from "react";
import { API_BASE } from "@/lib/api/client";
import { getAccessToken } from "@/lib/auth/session";

/** Build the ws(s):// URL for a backend WebSocket path, carrying the JWT as
 * `?token=`. Derives the host from API_BASE (…/api/v1 → ws root). */
function wsUrl(path: string): string {
  const token = getAccessToken() ?? "";
  const base = API_BASE.replace(/^http/, "ws").replace(/\/api\/v1\/?$/, "");
  const sep = path.startsWith("/") ? "" : "/";
  return `${base}${sep}${path}?token=${encodeURIComponent(token)}`;
}

/**
 * Subscribe to a delivery WebSocket. Calls `onMessage` with each parsed JSON
 * payload, and auto-reconnects with capped exponential backoff. Returns whether
 * the socket is currently connected (for a "live" indicator). Polling stays as
 * the source of truth; this just streams deltas in between.
 */
export function useDeliverySocket(
  path: string,
  onMessage: (data: unknown) => void,
): { connected: boolean } {
  const cbRef = React.useRef(onMessage);
  cbRef.current = onMessage;
  const [connected, setConnected] = React.useState(false);

  React.useEffect(() => {
    let ws: WebSocket | null = null;
    let closed = false;
    let retry = 0;
    let timer: ReturnType<typeof setTimeout> | undefined;

    const schedule = () => {
      retry = Math.min(retry + 1, 6);
      timer = setTimeout(connect, Math.min(1000 * 2 ** retry, 15000));
    };

    const connect = () => {
      if (closed) return;
      let socket: WebSocket;
      try {
        socket = new WebSocket(wsUrl(path));
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
          cbRef.current(JSON.parse(e.data));
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
  }, [path]);

  return { connected };
}
