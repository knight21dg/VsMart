// Helpers for fetching CMS pages from the VS Mart backend so super-admin
// can edit Privacy / Terms content without a redeploy.

export const API_BASE_URL =
  process.env.NEXT_PUBLIC_API_BASE_URL || "https://api.thevsmart.com/api/v1";

export type CmsPage = {
  id: number | string;
  slug: string;
  title: string;
  body: string;
  type?: string;
  updated_at?: string | null;
};

/**
 * Fetch a CMS page by slug. Returns `null` on any failure (network error,
 * non-200, missing page, malformed envelope) so callers can render a clean
 * fallback instead of crashing the route.
 */
export async function fetchCmsPage(slug: string): Promise<CmsPage | null> {
  try {
    const res = await fetch(`${API_BASE_URL}/content/pages/${slug}`, {
      cache: "no-store",
    });
    if (!res.ok) return null;

    const json = (await res.json()) as
      | { success?: boolean; data?: Partial<CmsPage> }
      | null;

    const data = json?.data;
    if (!json?.success || !data || typeof data.body !== "string") return null;

    return {
      id: data.id ?? slug,
      slug: data.slug ?? slug,
      title: data.title ?? "",
      body: data.body,
      type: data.type,
      updated_at: data.updated_at ?? null,
    };
  } catch {
    return null;
  }
}
