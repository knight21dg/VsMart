"use client";

/**
 * Counter feedback sounds for the POS.
 *
 * Synthesised with the Web Audio API rather than shipped as audio files: no
 * network fetch to fail mid-sale, nothing to cache, works offline (the POS runs
 * offline), and a few bytes instead of a few KB.
 *
 * Why it matters at a till: a cashier scanning a basket is looking at the ITEMS,
 * not the screen. The beep is the confirmation — a scan that only shows a toast
 * makes them look up on every item. A distinct error tone means a bad scan is
 * caught at the shelf instead of at Charge.
 */

type Tone = { freq: number; ms: number; gap?: number; type?: OscillatorType };

// Distinct, short, and pitched apart so they're told apart by ear alone.
const PATTERNS: Record<string, Tone[]> = {
  // Crisp single blip — the "got it" of a supermarket scanner.
  scan: [{ freq: 2000, ms: 55 }],
  // Low double buzz — unmistakably "that didn't work".
  error: [
    { freq: 320, ms: 110, type: "square" },
    { freq: 220, ms: 150, gap: 40, type: "square" },
  ],
  // Rising two-note chime — sale complete.
  success: [
    { freq: 880, ms: 90 },
    { freq: 1320, ms: 140, gap: 10 },
  ],
  // Soft tick for +/- and removals.
  tick: [{ freq: 1200, ms: 25 }],
};

let ctx: AudioContext | null = null;
let muted = false;
let loaded = false;

const STORAGE_KEY = "vsmart.pos.muted";
const listeners = new Set<() => void>();

function load() {
  if (loaded || typeof window === "undefined") return;
  loaded = true;
  muted = window.localStorage.getItem(STORAGE_KEY) === "1";
}

/** Subscribe/snapshot pair for `useSyncExternalStore`.
 *
 * The preference lives in localStorage — an external store — so React reads it
 * through this rather than a setState-in-an-effect (which this project lints as
 * an error, and which would flash the wrong icon for a frame). `getServerSnapshot`
 * returns the default so SSR and first hydration agree.
 */
export function subscribeMuted(cb: () => void) {
  listeners.add(cb);
  return () => listeners.delete(cb);
}

export function isMuted() {
  load();
  return muted;
}

/** SSR/hydration snapshot — always the default, never touches localStorage. */
export function isMutedServer() {
  return false;
}

export function setMuted(next: boolean) {
  loaded = true;
  muted = next;
  try {
    window.localStorage.setItem(STORAGE_KEY, next ? "1" : "0");
  } catch {
    /* private mode — the preference just won't persist */
  }
  listeners.forEach((l) => l());
}

function audio(): AudioContext | null {
  if (typeof window === "undefined") return null;
  try {
    // Lazily created: browsers refuse an AudioContext before a user gesture, so
    // building it on first play (which always follows a scan/click) avoids the
    // console warning and a suspended context.
    ctx ||= new (window.AudioContext || (window as unknown as { webkitAudioContext: typeof AudioContext }).webkitAudioContext)();
    if (ctx.state === "suspended") void ctx.resume();
    return ctx;
  } catch {
    return null; // no Web Audio (very old browser) — silence, never a crash
  }
}

/** Play a named feedback sound. Never throws; silent when muted. */
export function play(name: keyof typeof PATTERNS) {
  load();
  if (muted) return;
  const ac = audio();
  if (!ac) return;
  const tones = PATTERNS[name];
  if (!tones) return;

  let at = ac.currentTime;
  for (const t of tones) {
    at += (t.gap ?? 0) / 1000;
    const osc = ac.createOscillator();
    const gain = ac.createGain();
    osc.type = t.type ?? "sine";
    osc.frequency.value = t.freq;
    // Short attack + exponential release: a clean blip with no click at the edges.
    gain.gain.setValueAtTime(0.0001, at);
    gain.gain.exponentialRampToValueAtTime(0.18, at + 0.008);
    gain.gain.exponentialRampToValueAtTime(0.0001, at + t.ms / 1000);
    osc.connect(gain).connect(ac.destination);
    osc.start(at);
    osc.stop(at + t.ms / 1000 + 0.02);
    at += t.ms / 1000;
  }
}

export const beepScan = () => play("scan");
export const beepError = () => play("error");
export const beepSuccess = () => play("success");
export const beepTick = () => play("tick");
