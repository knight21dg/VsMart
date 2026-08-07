// Shared style tokens used across the VS Mart landing components.
// `display` / `mono` map to the CSS variables defined in layout.tsx.

import type { CSSProperties } from "react";

export const display = "var(--font-display), sans-serif";
export const mono = "var(--font-mono), monospace";

export const colors = {
  teal: "#006D77",
  green: "#8BC34A",
  gold: "#F4C430",
  bg: "#F8FAFC",
  dark: "#0F172A",
} as const;

/** Mono eyebrow label used on every numbered section header (e.g. "01 — The App"). */
export function eyebrow(color: string): CSSProperties {
  return {
    fontFamily: mono,
    fontSize: 12,
    fontWeight: 600,
    letterSpacing: ".14em",
    color,
    textTransform: "uppercase",
    marginBottom: 16,
  };
}
