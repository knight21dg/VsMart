"use client";

/**
 * A big, resonant "new order" bell — synthesised with the Web Audio API, no
 * mp3 asset to ship/host or go stale. Modelled as a struck bell rather than a
 * beep: each strike sums several inharmonic partials (real bells don't ring
 * in a clean harmonic series) under one hard-attack, long-decay envelope, so
 * it has weight and ring-out instead of sounding like two quick pings.
 *
 * Browsers block audio until the page has seen a real user gesture (a click,
 * a keypress). `primeAudio()` creates/resumes the shared AudioContext from
 * inside a genuine gesture handler (e.g. the "Enable order alerts" button) so
 * a LATER chime triggered by an incoming WebSocket message — which is not
 * itself a user gesture — is allowed to actually play.
 */
let ctx: AudioContext | null = null;

function getContext(): AudioContext | null {
  if (typeof window === "undefined") return null;
  const Ctor = window.AudioContext || (window as unknown as { webkitAudioContext?: typeof AudioContext }).webkitAudioContext;
  if (!Ctor) return null;
  if (!ctx) ctx = new Ctor();
  return ctx;
}

/** Call from inside a click/keypress handler to unlock audio for the session. */
export function primeAudio() {
  const c = getContext();
  if (c && c.state === "suspended") void c.resume();
}

// Ratios (relative to the strike pitch) and relative amplitudes approximating
// a real bell's inharmonic partials (hum / prime / tierce / quint / nominal).
// Amplitudes are pre-scaled so the partials summed together stay well under
// clipping once run through the strike's own gain envelope.
const BELL_PARTIALS: { ratio: number; amp: number }[] = [
  { ratio: 1.0, amp: 0.6 },
  { ratio: 2.0, amp: 0.32 },
  { ratio: 2.4, amp: 0.2 },
  { ratio: 3.0, amp: 0.14 },
  { ratio: 4.5, amp: 0.08 },
];

/** One bell strike: a hard attack (a "clang", not a fade-in) into a long,
 * slightly-more-than-a-second exponential ring-out. */
function strikeBell(c: AudioContext, pitch: number, start: number) {
  const t0 = c.currentTime + start;
  const decay = 1.7;

  const envelope = c.createGain();
  envelope.gain.setValueAtTime(0, t0);
  envelope.gain.linearRampToValueAtTime(1, t0 + 0.006);
  envelope.gain.exponentialRampToValueAtTime(0.001, t0 + decay);
  envelope.connect(c.destination);

  for (const { ratio, amp } of BELL_PARTIALS) {
    const osc = c.createOscillator();
    osc.type = "sine";
    osc.frequency.value = pitch * ratio;
    const partialGain = c.createGain();
    partialGain.gain.value = amp;
    osc.connect(partialGain);
    partialGain.connect(envelope);
    osc.start(t0);
    osc.stop(t0 + decay + 0.05);
  }
}

/** Plays a big two-strike "ding-DONG" bell — the new-order alert. */
export function playNewOrderChime() {
  const c = getContext();
  if (!c) return;
  if (c.state === "suspended") void c.resume();
  strikeBell(c, 523.25, 0); // C5 — the first, higher strike
  strikeBell(c, 392.0, 0.5); // G4 — the second, lower "dong"
}
