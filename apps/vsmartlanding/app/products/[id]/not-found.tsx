const PLAY_STORE_URL =
  "https://play.google.com/store/apps/details?id=com.vsmart.user_app";

/** Shown when a shared product link points to something that no longer exists
 * (deactivated, wrong id). Returns HTTP 404 via Next's not-found convention. */
export default function ProductNotFound() {
  return (
    <>
      <header className="pdp-nav">
        <a href="/" className="pdp-nav-brand">
          {/* eslint-disable-next-line @next/next/no-img-element */}
          <img src="/assets/vsmart-logo.png" alt="VS Mart" className="pdp-nav-logo" />
        </a>
        <a className="pdp-nav-cta" href={PLAY_STORE_URL}>
          Get the app
        </a>
      </header>

      <main className="pdp-404">
        <div className="pdp-404-emoji" aria-hidden="true">
          🛒
        </div>
        <h1>Product not found</h1>
        <p>
          This item may have sold out or been removed. Browse thousands more on the
          VS Mart app — fresh groceries delivered fast, buy now and pay with VS
          Credit.
        </p>
        <div className="pdp-404-actions">
          <a className="pdp-cta" href={PLAY_STORE_URL}>
            Get the VS Mart app
          </a>
          <a className="pdp-back" href="/">
            ← Back to VS Mart
          </a>
        </div>
      </main>
    </>
  );
}
