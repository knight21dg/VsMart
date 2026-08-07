import type { Metadata, Viewport } from "next";
import { Bricolage_Grotesque, Plus_Jakarta_Sans, JetBrains_Mono } from "next/font/google";
import "./globals.css";

export const viewport: Viewport = {
  width: "device-width",
  initialScale: 1,
  viewportFit: "cover",
  themeColor: "#006d77",
};

const display = Bricolage_Grotesque({
  subsets: ["latin"],
  weight: ["600", "700", "800"],
  variable: "--font-display",
  display: "swap",
});

const body = Plus_Jakarta_Sans({
  subsets: ["latin"],
  weight: ["400", "500", "600", "700", "800"],
  variable: "--font-body",
  display: "swap",
});

const mono = JetBrains_Mono({
  subsets: ["latin"],
  weight: ["500", "600", "700"],
  variable: "--font-mono",
  display: "swap",
});

const SITE_URL = "https://thevsmart.com";
const OG_IMAGE = "/assets/vsmart-appicon.png";

export const metadata: Metadata = {
  metadataBase: new URL(SITE_URL),
  title: {
    default: "VS Mart — India's Smart Grocery & Credit Platform",
    template: "%s · VS Mart",
  },
  description:
    "VS Mart combines grocery shopping, credit purchases, doorstep delivery and easy repayments in one app. Buy today, pay weekly or monthly.",
  applicationName: "VS Mart",
  keywords: [
    "grocery on credit",
    "buy groceries on credit",
    "monthly grocery credit",
    "grocery delivery app",
    "online grocery delivery",
    "pay later groceries",
    "VS Mart",
    "VS Credit",
    "VS Score",
  ],
  authors: [{ name: "VS Mart" }],
  creator: "VS Mart",
  publisher: "VS Mart",
  alternates: {
    canonical: "/",
  },
  openGraph: {
    type: "website",
    url: SITE_URL,
    siteName: "VS Mart",
    title: "VS Mart — Groceries Delivered Fast. Credit Made Easy.",
    description:
      "Shop groceries, buy on credit and pay with ease. India's smart grocery & credit platform — buy today, pay weekly or monthly.",
    images: [
      {
        url: OG_IMAGE,
        width: 1200,
        height: 1200,
        alt: "VS Mart — smart grocery & credit platform",
      },
    ],
    locale: "en_IN",
  },
  twitter: {
    card: "summary_large_image",
    title: "VS Mart — Groceries Delivered Fast. Credit Made Easy.",
    description:
      "Shop groceries, buy on credit and pay with ease. India's smart grocery & credit platform.",
    images: [OG_IMAGE],
  },
  robots: {
    index: true,
    follow: true,
    googleBot: {
      index: true,
      follow: true,
      "max-image-preview": "large",
      "max-snippet": -1,
      "max-video-preview": -1,
    },
  },
  manifest: "/manifest.webmanifest",
  icons: {
    icon: [{ url: "/icon.png", type: "image/png" }],
    shortcut: ["/icon.png"],
    apple: [{ url: "/apple-icon.png", type: "image/png" }],
  },
};

const jsonLd = {
  "@context": "https://schema.org",
  "@graph": [
    {
      "@type": "Organization",
      "@id": `${SITE_URL}/#organization`,
      name: "VS Mart",
      url: SITE_URL,
      logo: {
        "@type": "ImageObject",
        url: `${SITE_URL}/assets/vsmart-appicon.png`,
      },
      description:
        "VS Mart combines grocery shopping, credit purchases, doorstep delivery and easy repayments in one app.",
    },
    {
      "@type": "WebSite",
      "@id": `${SITE_URL}/#website`,
      url: SITE_URL,
      name: "VS Mart",
      description: "India's smart grocery & credit platform.",
      publisher: { "@id": `${SITE_URL}/#organization` },
      potentialAction: {
        "@type": "SearchAction",
        target: {
          "@type": "EntryPoint",
          urlTemplate: `${SITE_URL}/?q={search_term_string}`,
        },
        "query-input": "required name=search_term_string",
      },
    },
  ],
};

export default function RootLayout({ children }: { children: React.ReactNode }) {
  return (
    <html lang="en" className={`${display.variable} ${body.variable} ${mono.variable}`}>
      <body>
        <script
          type="application/ld+json"
          // eslint-disable-next-line react/no-danger
          dangerouslySetInnerHTML={{ __html: JSON.stringify(jsonLd) }}
        />
        {children}
      </body>
    </html>
  );
}
