"use client";

import * as React from "react";

/**
 * Global key bindings for the till.
 *
 * A cashier works two-handed — scanner in one hand, keyboard in the other — and
 * every mouse trip costs seconds per customer. These are the standard retail
 * F-keys so the whole sale can run without leaving the keyboard.
 *
 * Deliberate behaviours:
 *  - F-keys fire even while the scan box is focused (it always is — the scanner
 *    types into it), which is why we do NOT blanket-ignore typing targets.
 *  - Plain printable keys are ignored while typing, so "F" in a product search
 *    never triggers an action.
 *  - NOTHING fires while a modal is open. The listener is on `window`, so before
 *    this guard F9 completed a sale and F8 saved-and-cleared the cart from behind
 *    an open dialog, and Escape — which Radix handles on `document` to dismiss a
 *    dialog — ALSO reached the till and wiped the sale.
 *  - Handlers are held in a ref, so the listener binds once and never goes stale.
 */
export type HotkeyMap = Record<string, (e: KeyboardEvent) => void>;

const isTyping = (el: EventTarget | null) => {
  const n = el as HTMLElement | null;
  if (!n) return false;
  const tag = n.tagName;
  return tag === "INPUT" || tag === "TEXTAREA" || tag === "SELECT" || n.isContentEditable;
};

/** F-keys and Escape are safe to fire while typing; letters are not. */
const alwaysSafe = (key: string) => /^F\d{1,2}$/.test(key) || key === "Escape";

/**
 * Any open modal surface.
 *
 * Asked live from the DOM rather than tracked in page state on purpose: the POS
 * page's dialogs are owned by five independent components (product detail, add
 * customer, close-till, the shortcut legend's uncontrolled DialogTrigger, and
 * the clear-cart confirm), and Radix also opens dialogs we never render
 * ourselves. Lifting all of that into the page would be both invasive and
 * fragile — the next dialog someone adds would silently reintroduce the bug.
 * Radix stamps `role="dialog"|"alertdialog"` + `data-state="open"` on every
 * dialog content node, so one query at keypress time is authoritative and
 * self-maintaining. `role="listbox"` catches an open Select dropdown — also a
 * surface that owns the keyboard — and `dialog[open]` a native <dialog>.
 */
const MODAL_SELECTOR = [
  '[role="dialog"][data-state="open"]',
  '[role="alertdialog"][data-state="open"]',
  '[role="listbox"][data-state="open"]',
  "dialog[open]",
].join(",");

export function isModalOpen(): boolean {
  if (typeof document === "undefined") return false;
  return document.querySelector(MODAL_SELECTOR) !== null;
}

export function useHotkeys(map: HotkeyMap, enabled = true) {
  const ref = React.useRef(map);

  // Writing a ref during render is a react-compiler violation; keep it in sync
  // from an effect instead. The listener still reads the LATEST map on every
  // keypress, so handlers never go stale — and it binds once, not per render.
  React.useEffect(() => {
    ref.current = map;
  });

  React.useEffect(() => {
    if (!enabled) return;
    function onKey(e: KeyboardEvent) {
      const handler = ref.current[e.key];
      if (!handler) return;
      // A dialog owns the keyboard while it's up — including Escape, which must
      // dismiss the dialog and nothing else.
      if (isModalOpen()) return;
      if (!alwaysSafe(e.key) && isTyping(e.target)) return;
      // Stop the browser stealing F-keys (F1 help, F3 find, F5 reload…).
      e.preventDefault();
      handler(e);
    }
    window.addEventListener("keydown", onKey);
    return () => window.removeEventListener("keydown", onKey);
  }, [enabled]);
}

/**
 * Put the caret back in the scan box once every dialog has closed.
 *
 * Radix restores focus to whatever opened the dialog — for the product popup
 * that's the product card, a <button>. The scanner then types its digits into a
 * button and its trailing Enter re-opens the very dialog the cashier just
 * closed, so the next scan is lost and the till looks stuck. Watching the DOM
 * (same reasoning as `isModalOpen`) catches the close of ANY dialog, including
 * ones this page doesn't own.
 */
export function useFocusOnModalClose(
  ref: React.RefObject<HTMLElement | null>,
  enabled = true,
) {
  React.useEffect(() => {
    if (!enabled || typeof document === "undefined") return;
    let wasOpen = isModalOpen();
    let timer: ReturnType<typeof setTimeout> | undefined;

    const check = () => {
      const open = isModalOpen();
      if (wasOpen && !open) {
        clearTimeout(timer);
        // Radix restores trigger focus asynchronously on close; land after it.
        timer = setTimeout(() => {
          const active = document.activeElement as HTMLElement | null;
          // Never steal focus the cashier has already given to another field.
          if (active && isTyping(active)) return;
          ref.current?.focus();
        }, 80);
      }
      wasOpen = open;
    };

    const mo = new MutationObserver(check);
    mo.observe(document.body, {
      childList: true,
      subtree: true,
      attributes: true,
      attributeFilter: ["data-state", "open"],
    });
    return () => {
      mo.disconnect();
      clearTimeout(timer);
    };
  }, [ref, enabled]);
}
