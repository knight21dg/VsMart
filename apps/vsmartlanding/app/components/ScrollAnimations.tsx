"use client";

import { useEffect } from "react";

/**
 * Renders nothing — drives the on-scroll counters, the VS Score ring fill and
 * the credit-dashboard chart bars, mirroring the prototype's setupAnimations().
 * Reads data-attributes off elements rendered by the server components.
 */
export default function ScrollAnimations() {
  useEffect(() => {
    const prefersReduced =
      typeof window !== "undefined" &&
      window.matchMedia &&
      window.matchMedia("(prefers-reduced-motion: reduce)").matches;

    const fmt = (n: number) => n.toLocaleString("en-IN");

    const runCounter = (el: HTMLElement) => {
      const target = parseInt(el.getAttribute("data-target") || "0", 10) || 0;
      const suffix = el.getAttribute("data-suffix") || "";
      if (prefersReduced) {
        el.textContent = fmt(target) + suffix;
        return;
      }
      const dur = 1500;
      const start = performance.now();
      const tick = (now: number) => {
        const p = Math.min((now - start) / dur, 1);
        const eased = 1 - Math.pow(1 - p, 3);
        el.textContent = fmt(Math.round(target * eased)) + suffix;
        if (p < 1) requestAnimationFrame(tick);
      };
      requestAnimationFrame(tick);
    };

    // counters
    const counters = Array.from(document.querySelectorAll<HTMLElement>("[data-count]"));
    const cio = new IntersectionObserver(
      (entries) => {
        entries.forEach((e) => {
          if (!e.isIntersecting) return;
          runCounter(e.target as HTMLElement);
          cio.unobserve(e.target);
        });
      },
      { threshold: 0.5 }
    );
    counters.forEach((el) => {
      el.textContent = "0";
      cio.observe(el);
    });

    // score ring + chart bars
    const aio = new IntersectionObserver(
      (entries) => {
        entries.forEach((e) => {
          if (!e.isIntersecting) return;
          const t = e.target as HTMLElement;
          if (t.id === "vs-score-ring") {
            const pct = (820 - 300) / (900 - 300); // ~0.867
            t.style.strokeDashoffset = String(628 * (1 - pct));
          }
          if (t.hasAttribute("data-bar")) {
            t.style.height = t.getAttribute("data-h") || "0";
          }
          aio.unobserve(t);
        });
      },
      { threshold: 0.4 }
    );
    const ring = document.querySelector("#vs-score-ring");
    if (ring) aio.observe(ring);
    const bars = Array.from(document.querySelectorAll<HTMLElement>("[data-bar]"));
    bars.forEach((el) => aio.observe(el));

    // scroll reveal: fade + rise as elements enter the viewport
    let rio: IntersectionObserver | null = null;
    if (!prefersReduced) {
      rio = new IntersectionObserver(
        (entries) => {
          entries.forEach((e) => {
            if (!e.isIntersecting) return;
            const el = e.target as HTMLElement;
            el.classList.remove("reveal-init");
            el.classList.add("reveal-in");
            rio!.unobserve(el);
          });
        },
        { threshold: 0.12, rootMargin: "0px 0px -8% 0px" }
      );

      const inViewNow = (el: HTMLElement) => {
        const r = el.getBoundingClientRect();
        return r.top < window.innerHeight * 0.92 && r.bottom > 0;
      };
      const prep = (el: HTMLElement, delay: number) => {
        // never hide what's already on screen → no flash for above-the-fold content
        if (inViewNow(el)) return;
        if (delay) el.style.transitionDelay = `${delay}ms`;
        el.classList.add("reveal-init");
        rio!.observe(el);
      };

      document
        .querySelectorAll<HTMLElement>("[data-reveal]")
        .forEach((el) => prep(el, 0));
      document.querySelectorAll<HTMLElement>("[data-reveal-group]").forEach((group) => {
        Array.from(group.children).forEach((child, i) =>
          prep(child as HTMLElement, Math.min(i * 70, 420))
        );
      });
    }

    return () => {
      cio.disconnect();
      aio.disconnect();
      if (rio) rio.disconnect();
    };
  }, []);

  return null;
}
