"use client";

import { useEffect, useRef } from "react";

import { mono } from "../components/ui";

/**
 * Six one-digit boxes.
 *
 * The value is an ARRAY of slots, not a joined string: each box owns its own
 * position, so correcting the third digit edits the third digit and nothing
 * else. (A joined string collapses holes, which made a mid-code edit shift
 * every digit after it.)
 *
 * Behaviour people expect from this control, all of it deliberate:
 * - typing advances; the box you're on is replaced, not appended to
 *   (`maxLength=1` plus select-on-focus — without both, typing beside an
 *   existing digit yields a two-character value)
 * - Backspace clears the current box in place, or steps back and clears that
 *   one when the current box is already empty
 * - arrows/Home/End move without editing
 * - pasting (or an SMS autofill that lands in one box) fills from the left
 * - `resetToken` changing re-focuses the first box — used after a rejected
 *   code, so the customer can retype immediately instead of clicking back in
 */
export default function OtpInput({
  value,
  onChange,
  onComplete,
  length = 6,
  invalid = false,
  resetToken = 0,
}: {
  value: string[];
  onChange: (next: string[]) => void;
  onComplete?: (code: string) => void;
  length?: number;
  invalid?: boolean;
  resetToken?: number;
}) {
  const refs = useRef<Array<HTMLInputElement | null>>([]);
  const slots = normalise(value, length);

  // Someone typing a 6-digit code outruns React: several keystrokes land before
  // the first re-render, and each handler would otherwise compose its edit onto
  // the stale render-time array — silently dropping every digit but one. This
  // ref always holds the newest slots, so edits chain correctly, and it
  // re-syncs from props after each commit.
  const latest = useRef<string[]>(slots);
  useEffect(() => {
    latest.current = normalise(value, length);
  }, [value, length]);

  useEffect(() => {
    refs.current[0]?.focus();
  }, [resetToken]);

  function focusAt(index: number) {
    refs.current[Math.max(0, Math.min(index, length - 1))]?.focus();
  }

  /** Commit a new set of slots: publish it, move focus, fire completion. */
  function apply(next: string[], focusIndex: number) {
    latest.current = next;
    onChange(next);
    focusAt(focusIndex);
    if (next.every((d) => d !== "")) onComplete?.(next.join(""));
  }

  /** Overwrite from `start` — used by paste and by autofill that arrives whole. */
  function fillFrom(start: number, digits: string) {
    const next = [...latest.current];
    for (let i = 0; i < digits.length && start + i < length; i++) {
      next[start + i] = digits[i]!;
    }
    apply(next, Math.min(start + digits.length, length - 1));
  }

  function handleChange(index: number, raw: string) {
    const digits = raw.replace(/\D/g, "");
    if (!digits) {
      // The box was emptied (e.g. cut, or an IME clearing it).
      const next = [...latest.current];
      next[index] = "";
      latest.current = next;
      onChange(next);
      return;
    }
    if (digits.length > 1) {
      fillFrom(index, digits);
      return;
    }
    const next = [...latest.current];
    next[index] = digits;
    apply(next, index + 1);
  }

  function handleKeyDown(index: number, e: React.KeyboardEvent<HTMLInputElement>) {
    if (e.key === "Backspace") {
      e.preventDefault();
      const next = [...latest.current];
      if (next[index]) {
        next[index] = ""; // clear where you are
      } else if (index > 0) {
        next[index - 1] = ""; // already empty → step back and clear that one
        focusAt(index - 1);
      }
      latest.current = next;
      onChange(next);
      return;
    }
    if (e.key === "Delete") {
      e.preventDefault();
      const next = [...latest.current];
      next[index] = "";
      latest.current = next;
      onChange(next);
      return;
    }
    if (e.key === "ArrowLeft") {
      e.preventDefault();
      focusAt(index - 1);
      return;
    }
    if (e.key === "ArrowRight") {
      e.preventDefault();
      focusAt(index + 1);
      return;
    }
    if (e.key === "Home") {
      e.preventDefault();
      focusAt(0);
      return;
    }
    if (e.key === "End") {
      e.preventDefault();
      focusAt(length - 1);
    }
  }

  function handlePaste(index: number, e: React.ClipboardEvent<HTMLInputElement>) {
    const digits = e.clipboardData.getData("text").replace(/\D/g, "");
    if (!digits) return;
    e.preventDefault();
    // A full-length paste always starts at the first box, wherever it landed.
    fillFrom(digits.length >= length ? 0 : index, digits.slice(0, length));
  }

  return (
    <div style={{ display: "flex", gap: "clamp(6px,2vw,10px)", justifyContent: "space-between" }}>
      {slots.map((digit, i) => (
        <input
          key={i}
          ref={(el) => {
            refs.current[i] = el;
          }}
          value={digit}
          onChange={(e) => handleChange(i, e.target.value)}
          onKeyDown={(e) => handleKeyDown(i, e)}
          onPaste={(e) => handlePaste(i, e)}
          // Select on focus so the next keystroke replaces the digit instead of
          // sitting beside it.
          onFocus={(e) => e.currentTarget.select()}
          maxLength={1}
          inputMode="numeric"
          autoComplete={i === 0 ? "one-time-code" : "off"}
          aria-label={`Digit ${i + 1} of ${length}`}
          aria-invalid={invalid || undefined}
          className="otp-box"
          style={{
            width: "100%",
            minWidth: 0,
            height: 56,
            textAlign: "center",
            fontFamily: mono,
            fontSize: 22,
            fontWeight: 700,
            color: "#0F172A",
            background: "#fff",
            border: `1.5px solid ${invalid ? "#DC2626" : digit ? "#006D77" : "#E2E8F0"}`,
            borderRadius: 14,
            outline: "none",
            transition: "border-color .15s, box-shadow .15s",
          }}
        />
      ))}
    </div>
  );
}

/** Always exactly `length` slots of at most one digit each. */
function normalise(value: string[], length: number): string[] {
  return Array.from({ length }, (_, i) => (value[i] ?? "").replace(/\D/g, "").slice(0, 1));
}
