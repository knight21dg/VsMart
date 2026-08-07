"use client";

import { useEffect, useRef } from "react";
import { display } from "./ui";

const WORD = "VS Mart";

type P = { x: number; y: number; vx: number; vy: number };

/**
 * The giant footer brand wordmark, made physically interactive.
 * On a fine pointer you can grab the word and toss it — each letter is a
 * spring in a chain, so the word stretches, whips and settles back home with
 * momentum. Falls back to a static wordmark on touch / reduced-motion.
 */
export default function FooterWordmark() {
  const containerRef = useRef<HTMLDivElement>(null);
  const letterRefs = useRef<(HTMLSpanElement | null)[]>([]);

  useEffect(() => {
    const fine = window.matchMedia("(pointer: fine)").matches;
    const reduced = window.matchMedia("(prefers-reduced-motion: reduce)").matches;
    const container = containerRef.current;
    const letters = letterRefs.current.filter((el): el is HTMLSpanElement => !!el);
    const N = letters.length;
    if (!container || N === 0 || !fine || reduced) return;

    const pos: P[] = letters.map(() => ({ x: 0, y: 0, vx: 0, vy: 0 }));
    const target = { x: 0, y: 0 };
    const grab = { x: 0, y: 0 };
    const last = { x: 0, y: 0, t: 0 };
    const vel = { x: 0, y: 0 };
    let dragging = false;
    let raf = 0;

    container.style.cursor = "grab";

    const clamp = (v: number, m: number) => Math.max(-m, Math.min(m, v));

    const onDown = (e: PointerEvent) => {
      dragging = true;
      grab.x = e.clientX;
      grab.y = e.clientY;
      last.x = e.clientX;
      last.y = e.clientY;
      last.t = e.timeStamp;
      vel.x = 0;
      vel.y = 0;
      container.style.cursor = "grabbing";
      try {
        container.setPointerCapture(e.pointerId);
      } catch {}
    };
    const onMove = (e: PointerEvent) => {
      if (!dragging) return;
      target.x = e.clientX - grab.x;
      target.y = e.clientY - grab.y;
      const dt = Math.max(1, e.timeStamp - last.t);
      vel.x = clamp(((e.clientX - last.x) / dt) * 16, 60);
      vel.y = clamp(((e.clientY - last.y) / dt) * 16, 60);
      last.x = e.clientX;
      last.y = e.clientY;
      last.t = e.timeStamp;
    };
    const onUp = () => {
      if (!dragging) return;
      dragging = false;
      container.style.cursor = "grab";
      // hand the toss momentum to the head letter; the chain whips along
      pos[0].vx += vel.x;
      pos[0].vy += vel.y;
      target.x = 0;
      target.y = 0;
    };

    container.addEventListener("pointerdown", onDown);
    window.addEventListener("pointermove", onMove);
    window.addEventListener("pointerup", onUp);
    window.addEventListener("pointercancel", onUp);

    const HEAD_K = 0.16; // stiffness pulling the head letter to the target
    const CHAIN_K = 0.3; // stiffness binding each letter to the one before it
    const DAMP = 0.8;

    const tick = () => {
      const tx = dragging ? target.x : 0;
      const ty = dragging ? target.y : 0;
      for (let i = 0; i < N; i++) {
        const p = pos[i];
        const targetX = i === 0 ? tx : pos[i - 1].x;
        const targetY = i === 0 ? ty : pos[i - 1].y;
        const k = i === 0 ? HEAD_K : CHAIN_K;
        p.vx += (targetX - p.x) * k;
        p.vy += (targetY - p.y) * k;
        p.vx *= DAMP;
        p.vy *= DAMP;
        p.x += p.vx;
        p.y += p.vy;
        const rot = clamp(p.vx * 0.05, 12);
        letters[i].style.transform = `translate(${p.x.toFixed(2)}px,${p.y.toFixed(2)}px) rotate(${rot.toFixed(2)}deg)`;
      }
      raf = requestAnimationFrame(tick);
    };
    raf = requestAnimationFrame(tick);

    return () => {
      cancelAnimationFrame(raf);
      container.removeEventListener("pointerdown", onDown);
      window.removeEventListener("pointermove", onMove);
      window.removeEventListener("pointerup", onUp);
      window.removeEventListener("pointercancel", onUp);
    };
  }, []);

  return (
    <div
      ref={containerRef}
      aria-hidden
      style={{
        fontFamily: display,
        fontWeight: 800,
        fontSize: "clamp(72px,21vw,248px)",
        lineHeight: 0.9,
        letterSpacing: "-.05em",
        textAlign: "center",
        whiteSpace: "nowrap",
        color: "#EFE9CC",
        margin: "0 0 clamp(36px,6vw,64px)",
        userSelect: "none",
        WebkitUserSelect: "none",
        touchAction: "pan-y",
      }}
    >
      {WORD.split("").map((ch, i) => (
        <span
          key={i}
          ref={(el) => {
            letterRefs.current[i] = el;
          }}
          style={{ display: "inline-block", willChange: "transform", whiteSpace: "pre" }}
        >
          {ch === " " ? " " : ch}
        </span>
      ))}
    </div>
  );
}
