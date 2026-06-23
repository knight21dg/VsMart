# VS Mart — Commerce Architecture Report (Phase 2 Sign-off)

Handoff document for Phase 3 (Cart → Checkout → Orders). The commerce platform
layer below is built, integrated, and `flutter analyze lib` clean.

---

## 1. Entities

| Entity | Location | Notes |
|---|---|---|
| `Category` | `catalog/domain/entities/category.dart` | Department **and** sub-category (via `parentId`); `productCount`, `iconName`, `imageUrl` |
| `Product` | `catalog/domain/entities/product.dart` | `price`, `mrp`, `creditPrice`, `images`, `inStock`, `stockCount`, `variants`, `specifications`; getters `pricing`, `gallery`, `stockStatus`, `discountPercent`, `savings` |
| `ProductPrice` | `…/product_price.dart` | selling/MRP/credit + `discountPercent`, `savings`, `effectiveCreditPrice` |
| `ProductVariant` | `…/product_variant.dart` | `label`, `priceDelta`, `inStock` |
| `ProductFilter` | `…/product_filter.dart` | price/stock/brands/categories/subCategories/discount; `matches()`, `activeChips()` |
| `ProductSort` (enum) | `…/product_filter.dart` | popularity / newest / price↑ / price↓ / discount |
| `StockStatus` (enum) | `…/product.dart` | inStock / lowStock / outOfStock |
| `RecentlyViewedEntry` | `…/recently_viewed_entry.dart` | `{productId, viewedAt}` |
| `Offer` | `offers/domain/entities/offer.dart` | type banner/deal/coupon; `code`, `discountPercent`, `dealPrice`, `originalPrice`, `productId` |

Cross-phase entities consumed by commerce: `Cart`, `CartItem`, `CreditAccount`, `Address`.

## 2. Repositories

- **`CatalogRepository`** — `getDepartments`, `getCategories({parentId})`, `getProducts({categoryId})`, `getProductById`, `getRecommended`, `getFeatured`, `search`.
- **`OfferRepository`** — `getBanners`, `getDeals`, `getCoupons`.
- **`RecentlyViewedRepository`** — `getRecent`, `addViewed`, `removeViewed`, `clear`.
- Cross-phase: `CartRepository`, `AddressRepository`, `CreditRepository`.

Data sources: `CatalogFixtureDataSource` → **`CachingCatalogDataSource`** (SWR); `OfferFixtureDataSource` → **`CachingOfferDataSource`** (SWR); `RecentlyViewedRepositoryImpl` (Hive). The fixture is the single backend seam — swap for a Dio remote source with **zero** changes above the data layer.

## 3. Providers

**Wiring:** `catalogRemoteDataSourceProvider` → `catalogDataSourceProvider` (caching) → `catalogRepositoryProvider`; same shape for offers.

**Reads:** `departmentsProvider`, `categoriesProvider.family(parentId)`, `subCategoriesProvider`, `productsProvider.family(categoryId)`, `productByIdProvider.family(id)`, `recommendedProductsProvider`, `featuredProductsProvider`, `popularProductsProvider`, `searchProductsProvider.family(query)`, `bannersProvider`, `dealsProvider`, `couponsProvider`.

**Controllers:** `listingControllerProvider.family(ListingArgs{categoryId,query})` (fetch→filter→sort→paginate, grid pref persisted); `productDetailControllerProvider.family(productId)` (variant/quantity/stock/recently-viewed); `recentlyViewedProvider` + `recentlyViewedProductsProvider`; `cartControllerProvider`.

**Infra:** `commerceCacheManagerProvider`, `commerceConnectivityProvider` (online/offline/syncing), `analyticsServiceProvider`.

## 4. Hive Boxes

Commerce: `categoryBox`, `subCategoryBox`, `productBox`, `offerBox`, `recentlyViewedBox`. Cross-phase: `cartBox`, `addressBox`, `settingsBox` (`listing_grid` view pref), `cacheBox`, `verificationBox`.

## 5. Reusable Widgets

- **Core:** `VSProductCard`, `VSCategoryCard`, `VSCreditSummaryCard`, `VSOfflineBanner`, `VSEmptyState`, `VSErrorView`, `VSLoadingView`, `VSShimmer/Box`, `VSStatusChip`, `VSSearchField`, `VSButton/OutlinedButton`.
- **Catalog:** `VSPriceWidget`, `VSSubCategoryCard`, `VSProductGrid` (sliver), `VSProductListTile`, `VSFilterChip`, `showVSSortBottomSheet`, `showVSFilterSheet`, `VSPaginationLoader`, `VSProductGallery`, `VSVariantSelector`, `VSQuantitySelector`, `VSStockStatus`, `VSSpecificationSection`, `VSHomeShimmer`.
- **Offers:** `VSOfferBanner`.

## 6. Analytics Events

`home_viewed`, `offer_clicked`, `category_opened`, `subcategory_opened`, `listing_viewed`, `sort_changed`, `filter_applied`, `product_opened`, `variant_selected`, `quantity_changed`, `add_to_cart`, `buy_now`, `product_shared`, `recently_viewed_added`, `wishlist_added`, `wishlist_removed`.

Deferred until the Search screen exists: `search_started`, `search_completed`.

All via `AnalyticsService` (Firebase Analytics with `AppLogger` fallback, fire-and-forget).

## 7. Offline Strategy (Stale-While-Revalidate)

`CommerceCacheManager` stores JSON lists per Hive box with a `cachedAt` timestamp. The caching data sources:

1. **Fresh cache (< 5 min TTL)** → return instantly (fast cold start).
2. **Stale/missing** → fetch remote, **write through** to cache.
3. **Remote fails (offline)** → fall back to stale cache.

`commerceConnectivityProvider` (online/offline/syncing) drives `VSOfflineBanner` on Home + Listing. Cart, addresses, and recently-viewed persist to Hive independently.

## 8. Screen Inventory

| Screen | State |
|---|---|
| Home | **Hardened** — offline banner, pull-to-refresh, shimmer, offer carousel, credit card, quick actions, deals, categories, popular, recommended, continue-shopping |
| Categories (tab) | Department rail + sub-category grid |
| SubCategory | **New** — breadcrumb, banner, grid, states |
| Product Listing | **Engine** — sort/filter/active-chips/grid-list/pagination/states; search-compatible |
| Product Detail | **Engine** — gallery, variants, quantity, stock, specs, recommended, sticky CTA |
| Search / Offers / Wishlist / Today's Deals / Coupons | Stubs — listing engine ready for Search reuse |

---

## Phase 3 readiness

Cart and Checkout can consume `Product`, `ProductPrice`, `ProductVariant`, the cart controller, `AddressRepository`, and `CreditAccount` without rewrites. The listing engine + caching + analytics are reusable by Search, Offers, and Wishlist. **Next:** Cart → Address Selection → Checkout → Payment → Credit Purchase → Order Success → Orders → Tracking → Order Details. (Wishlist deferred — lower value than the order pipeline.)
