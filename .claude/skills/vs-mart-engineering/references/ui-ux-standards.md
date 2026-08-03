# UI/UX Standards

Every VS Mart screen should feel production-ready, which means handling the states users actually hit — not just the one where everything works.

## Screen-state matrix

For each screen, confirm it handles:

- **Loading** — a real loading indicator, not a frozen blank
- **Empty** — a meaningful empty state, not a bare list
- **Error** — clear message + a way to retry
- **Success** — the normal populated state
- **Offline** — degrades gracefully, communicates the offline condition

## Cross-cutting

- **Accessibility** — labels, contrast, tap target sizes
- **Responsiveness** — works across phone sizes
- **Tablet support** — usable layout on larger screens
- **Dark mode** — readable and correct in both themes
- **Localization** — strings externalized, layout survives longer translations
- **Performance** — smooth scroll, no jank on the screen's main interaction

A screen isn't done when the happy path renders. It's done when all five states above are handled and the cross-cutting checks pass.
