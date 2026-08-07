import { permanentRedirect } from "next/navigation";

/** Singular `/product/<id>` alias → the canonical plural `/products/<id>` the app
 * shares, so both URLs resolve to one page (and search engines see one canonical). */
export default async function ProductAlias({
  params,
}: {
  params: Promise<{ id: string }>;
}) {
  const { id } = await params;
  permanentRedirect(`/products/${encodeURIComponent(id)}`);
}
