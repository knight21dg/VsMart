import type { Metadata } from "next";
import LegalPage from "../components/LegalPage";
import { fetchCmsPage } from "../lib/cms";

export const metadata: Metadata = {
  title: "Terms & Conditions",
  description:
    "The terms governing your use of the VS Mart app, VS Credit, deliveries and repayments.",
  alternates: { canonical: "/terms" },
};

// Always render the latest CMS content (no static caching).
export const dynamic = "force-dynamic";

export default async function TermsPage() {
  const page = await fetchCmsPage("terms");

  if (!page) {
    return (
      <LegalPage
        eyebrow="Legal"
        title="Terms & Conditions"
        fallback
      />
    );
  }

  return (
    <LegalPage
      eyebrow="Legal"
      title={page.title || "Terms & Conditions"}
      updatedAt={page.updated_at}
      bodyHtml={page.body}
    />
  );
}
