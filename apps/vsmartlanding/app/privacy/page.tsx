import type { Metadata } from "next";
import LegalPage from "../components/LegalPage";
import { fetchCmsPage } from "../lib/cms";

export const metadata: Metadata = {
  title: "Privacy Policy",
  description:
    "How VS Mart collects, uses, and protects your personal data across grocery shopping, VS Credit and delivery.",
  alternates: { canonical: "/privacy" },
};

// Always render the latest CMS content (no static caching).
export const dynamic = "force-dynamic";

export default async function PrivacyPage() {
  const page = await fetchCmsPage("privacy");

  if (!page) {
    return (
      <LegalPage
        eyebrow="Legal"
        title="Privacy Policy"
        fallback
      />
    );
  }

  return (
    <LegalPage
      eyebrow="Legal"
      title={page.title || "Privacy Policy"}
      updatedAt={page.updated_at}
      bodyHtml={page.body}
    />
  );
}
