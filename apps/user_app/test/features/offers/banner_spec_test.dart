import 'package:flutter_test/flutter_test.dart';
import 'package:user_app/features/offers/domain/entities/banner_spec.dart';
import 'package:user_app/features/offers/domain/entities/offer.dart';

/// These guard the client half of the placement contract in
/// `offers/specs.py::PLACEMENT_SPECS`. If one fails after a backend change, the
/// two halves have drifted and banners are being cropped twice again.
void main() {
  group('BannerSpec ratios mirror the backend', () {
    test('home hero is 16:10, strips are 16:9, spotlight is square', () {
      expect(BannerSpec.top.ratio, closeTo(16 / 10, 1e-9));
      expect(BannerSpec.middle.ratio, closeTo(16 / 9, 1e-9));
      expect(BannerSpec.productList.ratio, closeTo(16 / 9, 1e-9));
      expect(BannerSpec.productDetail.ratio, closeTo(16 / 9, 1e-9));
      expect(BannerSpec.cart.ratio, closeTo(16 / 9, 1e-9));
      expect(BannerSpec.spotlight.ratio, closeTo(1, 1e-9));
    });

    test('every server placement resolves to a spec', () {
      for (final placement in BannerPlacement.values) {
        expect(
          BannerSpec.all.map((s) => s.placement),
          contains(placement.wire),
          reason: '${placement.wire} has no BannerSpec',
        );
      }
    });

    test('an unknown placement degrades to the hero spec, not a crash', () {
      expect(BannerSpec.forPlacement('checkout_v2'), BannerSpec.top);
      expect(BannerSpec.forPlacement(null), BannerSpec.top);
    });
  });

  group('heightFor', () {
    test('height matches the card ratio once the page inset is removed', () {
      const screen = 360.0;
      const inset = 8.0; // AppSpacing.xs on each side
      final h = BannerSpec.top.heightFor(screen, horizontalInset: inset);
      final cardWidth = screen * BannerSpec.top.viewportFraction - inset;
      expect(h, closeTo(cardWidth / BannerSpec.top.ratio, 0.01));
    });

    test('clamps rather than growing without bound on a tablet', () {
      final h = BannerSpec.top.heightFor(1600);
      expect(h, BannerSpec.top.maxHeight);
    });

    test('clamps up on a very narrow screen', () {
      final h = BannerSpec.top.heightFor(200);
      expect(h, BannerSpec.top.minHeight);
    });

    test('fraction override lets a lone banner span the full width', () {
      const screen = 360.0;
      final carousel = BannerSpec.productDetail.heightFor(screen);
      final full = BannerSpec.productDetail.heightFor(screen, fraction: 1.0);
      expect(full, greaterThanOrEqualTo(carousel));
    });

    test('never returns a non-positive height for a degenerate width', () {
      expect(BannerSpec.top.heightFor(0), greaterThan(0));
      expect(BannerSpec.top.heightFor(10, horizontalInset: 999), greaterThan(0));
    });

    test('rendered heights match the published table in docs/BANNER_SPEC.md', () {
      // If this fails, either a spec changed or the docs table is now a lie —
      // update both. Insets mirror the real call sites.
      const screenPad = 32.0; // AppSpacing.screenHorizontal, both sides
      const pageInset = 8.0; // AppSpacing.xs per side
      void check(String label, double actual, double documented) =>
          expect(actual, closeTo(documented, 0.5), reason: label);

      check('top@360', BannerSpec.top.heightFor(360, horizontalInset: pageInset), 202);
      check('top@412', BannerSpec.top.heightFor(412, horizontalInset: pageInset), 232);
      check('middle@360',
          BannerSpec.middle.heightFor(360, horizontalInset: pageInset), 170);
      check(
          'productList@360',
          BannerSpec.productList
              .heightFor(360, horizontalInset: pageInset + screenPad),
          164);
      check('productDetail@360',
          BannerSpec.productDetail.heightFor(360, fraction: 1.0), 203);
      check(
          'cart@360',
          BannerSpec.cart.heightFor(360, horizontalInset: pageInset + screenPad),
          180);
    });
  });

  group('Offer overlay parsing', () {
    test('accentColor parses #RRGGBB to opaque ARGB', () {
      const offer = Offer(
        id: '1',
        title: 't',
        type: OfferType.banner,
        accentColor: '#16A34A',
      );
      expect(offer.accentArgb, 0xFF16A34A);
    });

    test('a malformed accent colour falls back to null, not a crash', () {
      for (final bad in ['green', '#FFF', '', '#GGGGGG']) {
        final offer = Offer(
          id: '1',
          title: 't',
          type: OfferType.banner,
          accentColor: bad,
        );
        expect(offer.accentArgb, isNull, reason: 'accepted "$bad"');
      }
    });

    test('localized CTA falls back to English when a translation is missing', () {
      const offer = Offer(
        id: '1',
        title: 't',
        type: OfferType.banner,
        ctaText: 'Shop now',
        ctaTextTe: 'ఇప్పుడే కొనండి',
      );
      expect(offer.localizedCta('te'), 'ఇప్పుడే కొనండి');
      expect(offer.localizedCta('hi'), 'Shop now');
      expect(offer.localizedCta('en'), 'Shop now');
    });

    test('placement/theme/position parse from the wire format', () {
      expect(BannerPlacement.parse('product_list'), BannerPlacement.productList);
      expect(BannerPlacement.parse('nonsense'), BannerPlacement.top);
      expect(BannerTextTheme.parse('none'), BannerTextTheme.none);
      expect(BannerTextTheme.parse(null), BannerTextTheme.light);
      expect(BannerTextPosition.parse('bottom_center'),
          BannerTextPosition.bottomCenter);
      expect(BannerTextPosition.parse('sideways'),
          BannerTextPosition.bottomLeft);
    });
  });
}
