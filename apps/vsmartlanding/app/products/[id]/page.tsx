import type { Metadata } from "next";
import { notFound } from "next/navigation";

const API_BASE_URL =
  process.env.NEXT_PUBLIC_API_BASE_URL || "https://api.thevsmart.com/api/v1";
const MEDIA_ORIGIN = API_BASE_URL.replace(/\/api\/v1\/?$/, "");

/** Resolve a media path to an absolute URL on the API origin. The API returns
 * host-root-relative media (e.g. `/api/v1/media/public/<id>/<variant>`); left
 * relative, the browser would load it from thevsmart.com (where media isn't
 * served) instead of api.thevsmart.com. Absolute URLs pass through unchanged. */
function mediaUrl(rel?: string | null): string | null {
  if (!rel) return null;
  return /^https?:\/\//.test(rel) ? rel : `${MEDIA_ORIGIN}${rel}`;
}

const SITE_URL = "https://thevsmart.com";
const PLAY_STORE_URL =
  "https://play.google.com/store/apps/details?id=com.vsmart.user_app";

interface Variant {
  id: string;
  label: string;
  price?: number | null;
  mrp?: number | null;
  priceDelta?: number | null;
  imageUrl?: string | null;
  available?: number | null;
  inStock?: boolean | null;
}
interface Product {
  id: string;
  shareToken?: string | null;
  name: string;
  brand?: string | null;
  unit?: string | null;
  price?: number | null;
  mrp?: number | null;
  discountPercent?: number | null;
  imageUrl?: string | null;
  images?: string[] | null;
  inStock?: boolean | null;
  description?: string | null;
  variants?: Variant[] | null;
  specifications?: Record<string, string> | null;
}
interface Offer {
  id: string;
  type: string;
  title?: string | null;
  subtitle?: string | null;
  code?: string | null;
  badge?: string | null;
  discountPercent?: number | null;
  imageUrl?: string | null;
  image?: { medium?: string; large?: string; small?: string; legacy_url?: string } | null;
}

/** Fetch a product from the public catalog API. Returns null on 404/any failure. */
async function getProduct(id: string): Promise<Product | null> {
  try {
    const res = await fetch(`${API_BASE_URL}/products/${encodeURIComponent(id)}`, {
      next: { revalidate: 300 },
    });
    if (!res.ok) return null;
    const body = await res.json();
    const data = body?.data ?? body;
    return data && data.id ? (data as Product) : null;
  } catch {
    return null;
  }
}

/** Active public offers of a type (coupon / banner). Never throws — marketing
 * extras must not break a shared product link. */
async function getOffers(type: string): Promise<Offer[]> {
  try {
    const res = await fetch(`${API_BASE_URL}/offers?type=${type}`, {
      next: { revalidate: 300 },
    });
    if (!res.ok) return [];
    const body = await res.json();
    const data = body?.data ?? body;
    return Array.isArray(data) ? (data as Offer[]) : [];
  } catch {
    return [];
  }
}

const inr = (v?: number | null) =>
  typeof v === "number" ? `₹${v.toLocaleString("en-IN")}` : "";

/** Resolve an offer image to an absolute URL (WebP variant or legacy pasted URL). */
function offerImage(o: Offer): string | null {
  const img = o.image;
  const rel = img?.medium || img?.large || img?.small || img?.legacy_url;
  return mediaUrl(rel) ?? mediaUrl(o.imageUrl);
}

export async function generateMetadata({
  params,
}: {
  params: Promise<{ id: string }>;
}): Promise<Metadata> {
  const { id } = await params;
  const p = await getProduct(id);
  if (!p) {
    // The layout template appends " · VS Mart" — don't double it here.
    return { title: "Product not found", robots: { index: false } };
  }
  const title = p.brand ? `${p.name} by ${p.brand}` : p.name;
  const price = inr(p.price);
  const description =
    p.description?.trim() ||
    `${p.name}${price ? ` — ${price}` : ""}${p.unit ? ` (${p.unit})` : ""}. Order on VS Mart for fast doorstep delivery.`;
  const image = mediaUrl(p.imageUrl || p.images?.[0]);

  return {
    title,
    description,
    alternates: { canonical: `/products/${p.shareToken || p.id}` },
    openGraph: {
      type: "website",
      url: `${SITE_URL}/products/${p.shareToken || p.id}`,
      siteName: "VS Mart",
      title,
      description,
      images: image ? [{ url: image, alt: p.name }] : undefined,
      locale: "en_IN",
    },
    twitter: {
      card: "summary_large_image",
      title,
      description,
      images: image ? [image] : undefined,
    },
  };
}

export default async function ProductPage({
  params,
}: {
  params: Promise<{ id: string }>;
}) {
  const { id } = await params;
  const [p, coupons, banners] = await Promise.all([
    getProduct(id),
    getOffers("coupon"),
    getOffers("banner"),
  ]);
  if (!p) notFound();

  const gallery = (p.images && p.images.length ? p.images : [p.imageUrl])
    .map((x) => mediaUrl(x))
    .filter((x): x is string => !!x);
  const hero = gallery[0];
  const hasDiscount =
    typeof p.mrp === "number" && typeof p.price === "number" && p.mrp > p.price;
  const variants = (p.variants ?? []).filter((v) => v.label);
  const specs = Object.entries(p.specifications ?? {}).filter(([, v]) => v);
  const bannerCards = banners.map((b) => ({ ...b, img: offerImage(b) }));

  return (
    <>
      {/* Lightweight header so a shared link feels like part of the site. */}
      <header className="pdp-nav">
        <a href="/" className="pdp-nav-brand">
          {/* eslint-disable-next-line @next/next/no-img-element */}
          <img src="/assets/vsmart-logo.png" alt="VS Mart" className="pdp-nav-logo" />
        </a>
        <a className="pdp-nav-cta" href={PLAY_STORE_URL}>
          Get the app
        </a>
      </header>

      <main className="pdp">
        <div className="pdp-shell">
          <div className="pdp-card">
            <div className="pdp-media">
              {hero ? (
                <>
                  {/* eslint-disable-next-line @next/next/no-img-element */}
                  <img src={hero} alt={p.name} className="pdp-img" />
                  {gallery.length > 1 ? (
                    <div className="pdp-thumbs">
                      {gallery.slice(0, 5).map((g, i) => (
                        // eslint-disable-next-line @next/next/no-img-element
                        <img
                          key={i}
                          src={g}
                          alt=""
                          className={`pdp-thumb${i === 0 ? " is-active" : ""}`}
                        />
                      ))}
                    </div>
                  ) : null}
                </>
              ) : (
                <div className="pdp-img pdp-img-empty" aria-hidden="true" />
              )}
            </div>

            <div className="pdp-info">
              {p.brand ? <p className="pdp-brand">{p.brand}</p> : null}
              <h1 className="pdp-title">{p.name}</h1>
              {p.unit ? <p className="pdp-unit">{p.unit}</p> : null}

              <div className="pdp-price-row">
                <span className="pdp-price">{inr(p.price)}</span>
                {hasDiscount ? (
                  <>
                    <span className="pdp-mrp">{inr(p.mrp)}</span>
                    {p.discountPercent ? (
                      <span className="pdp-off">{p.discountPercent}% off</span>
                    ) : null}
                  </>
                ) : null}
              </div>

              <p className={p.inStock === false ? "pdp-oos" : "pdp-instock"}>
                {p.inStock === false ? "Currently out of stock" : "In stock"}
              </p>

              {variants.length ? (
                <div className="pdp-variants">
                  <p className="pdp-variants-label">Available packs</p>
                  <div className="pdp-variant-row">
                    {variants.map((v) => (
                      <span
                        key={v.id}
                        className={`pdp-variant${v.inStock === false ? " is-oos" : ""}`}
                      >
                        <b>{v.label}</b>
                        {typeof v.price === "number" ? (
                          <span>{inr(v.price)}</span>
                        ) : null}
                      </span>
                    ))}
                  </div>
                </div>
              ) : null}

              {p.description ? <p className="pdp-desc">{p.description}</p> : null}

              <a className="pdp-cta" href={PLAY_STORE_URL}>
                Get it on the VS Mart app
              </a>
              <p className="pdp-note">
                Groceries delivered fast — buy today, pay weekly or monthly with VS
                Credit.
              </p>
              <a className="pdp-back" href="/">
                ← Explore VS Mart
              </a>
            </div>
          </div>

          {/* Coupons — live offers a shopper can use in the app. */}
          {coupons.length ? (
            <section className="pdp-section">
              <h2 className="pdp-section-title">Offers you can use</h2>
              <div className="pdp-coupons">
                {coupons.slice(0, 6).map((c) => (
                  <div key={c.id} className="pdp-coupon">
                    <div className="pdp-coupon-body">
                      <p className="pdp-coupon-title">{c.title}</p>
                      {c.subtitle ? (
                        <p className="pdp-coupon-sub">{c.subtitle}</p>
                      ) : null}
                    </div>
                    {c.code ? <span className="pdp-coupon-code">{c.code}</span> : null}
                  </div>
                ))}
              </div>
            </section>
          ) : null}

          {/* Promotional banners (marketing strip). */}
          {bannerCards.length ? (
            <section className="pdp-section">
              <h2 className="pdp-section-title">What&rsquo;s on at VS Mart</h2>
              <div className="pdp-banners">
                {bannerCards.slice(0, 6).map((b) => (
                  <a key={b.id} href={PLAY_STORE_URL} className="pdp-banner">
                    {b.img ? (
                      // eslint-disable-next-line @next/next/no-img-element
                      <img src={b.img} alt={b.title ?? ""} className="pdp-banner-img" />
                    ) : (
                      <div className="pdp-banner-img pdp-banner-fallback" />
                    )}
                    <div className="pdp-banner-text">
                      {b.badge ? <span className="pdp-banner-badge">{b.badge}</span> : null}
                      <p className="pdp-banner-title">{b.title}</p>
                      {b.subtitle ? (
                        <p className="pdp-banner-sub">{b.subtitle}</p>
                      ) : null}
                    </div>
                  </a>
                ))}
              </div>
            </section>
          ) : null}

          {/* Specifications, when the product has any. */}
          {specs.length ? (
            <section className="pdp-section">
              <h2 className="pdp-section-title">Product details</h2>
              <dl className="pdp-specs">
                {specs.map(([k, v]) => (
                  <div key={k} className="pdp-spec">
                    <dt>{k}</dt>
                    <dd>{v}</dd>
                  </div>
                ))}
              </dl>
            </section>
          ) : null}
        </div>
      </main>

      <footer className="pdp-foot">
        <p>© {new Date().getFullYear()} VS Mart · Groceries + VS Credit</p>
        <a href={PLAY_STORE_URL}>Download the app</a>
      </footer>
    </>
  );
}
