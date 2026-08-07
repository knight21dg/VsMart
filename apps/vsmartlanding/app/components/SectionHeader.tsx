import type { ReactNode } from "react";
import { display, mono } from "./ui";

/**
 * The light, editorial numbered header used by App, Features, Ecosystem,
 * Delivery and Partner sections: a mono eyebrow + display headline on the
 * left, supporting copy on the right, above a hairline rule.
 */
export default function SectionHeader({
  eyebrow,
  title,
  lead,
  leftMax = 640,
  rightMax = 330,
  marginBottom = 52,
}: {
  eyebrow: string;
  title: ReactNode;
  lead: ReactNode;
  leftMax?: number;
  rightMax?: number;
  marginBottom?: number;
}) {
  return (
    <div
      data-reveal
      style={{
        display: "flex",
        justifyContent: "space-between",
        alignItems: "flex-end",
        gap: 40,
        flexWrap: "wrap",
        borderTop: "1px solid rgba(15,23,42,.1)",
        paddingTop: 26,
        marginBottom,
      }}
    >
      <div style={{ maxWidth: leftMax }}>
        <div
          style={{
            fontFamily: mono,
            fontSize: 12,
            fontWeight: 600,
            letterSpacing: ".14em",
            color: "#006D77",
            textTransform: "uppercase",
            marginBottom: 16,
          }}
        >
          {eyebrow}
        </div>
        <h2
          style={{
            fontFamily: display,
            fontWeight: 800,
            fontSize: "clamp(28px,5vw,48px)",
            lineHeight: 1.02,
            letterSpacing: "-.035em",
            margin: 0,
          }}
        >
          {title}
        </h2>
      </div>
      <p
        style={{
          fontSize: 16,
          color: "#64748B",
          fontWeight: 500,
          margin: 0,
          maxWidth: rightMax,
          lineHeight: 1.6,
        }}
      >
        {lead}
      </p>
    </div>
  );
}
