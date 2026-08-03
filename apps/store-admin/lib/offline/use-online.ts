"use client";

import * as React from "react";

/** Tracks browser connectivity. Starts optimistic (true) to avoid an SSR/client
 * flash, then syncs to `navigator.onLine` and listens for online/offline events. */
export function useOnline(): boolean {
  const [online, setOnline] = React.useState(true);

  React.useEffect(() => {
    const update = () => setOnline(navigator.onLine);
    update();
    window.addEventListener("online", update);
    window.addEventListener("offline", update);
    return () => {
      window.removeEventListener("online", update);
      window.removeEventListener("offline", update);
    };
  }, []);

  return online;
}
