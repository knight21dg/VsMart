import 'package:flutter_test/flutter_test.dart';
import 'package:user_app/app/routes/pending_deep_link.dart';
import 'package:user_app/core/services/deep_link.dart';
import 'package:user_app/core/services/deep_link_controller.dart';

void main() {
  group('resolveDeepLink — links we publish', () {
    test('opens a shared product link by share token', () {
      expect(
        resolveDeepLink(Uri.parse('https://thevsmart.com/products/tjNlmy5HLjMX')),
        '/products/tjNlmy5HLjMX',
      );
    });

    test('accepts the www host', () {
      expect(
        resolveDeepLink(Uri.parse('https://www.thevsmart.com/products/abc123')),
        '/products/abc123',
      );
    });

    test('accepts the singular /product alias the web site redirects from', () {
      // Older shared links used the singular form; they must still open in the
      // app rather than bouncing out to the browser.
      expect(
        resolveDeepLink(Uri.parse('https://thevsmart.com/product/abc123')),
        '/products/abc123',
      );
    });

    test('ignores query and fragment', () {
      expect(
        resolveDeepLink(
          Uri.parse('https://thevsmart.com/products/abc123?utm_source=wa#top'),
        ),
        '/products/abc123',
      );
    });

    test('accepts the custom scheme', () {
      expect(
        resolveDeepLink(Uri.parse('vsmart://products/abc123')),
        '/products/abc123',
      );
    });
  });

  group('resolveDeepLink — untrusted input is rejected', () {
    test('rejects a lookalike host', () {
      // The whole point of the host allowlist: registering thevsmart.com.evil.co
      // must not let a stranger drive someone else's app.
      for (final url in [
        'https://thevsmart.com.evil.co/products/abc',
        'https://evil.co/products/abc',
        'https://notthevsmart.com/products/abc',
        'https://thevsmart.com.co/products/abc',
      ]) {
        expect(resolveDeepLink(Uri.parse(url)), isNull, reason: url);
      }
    });

    test('rejects a non-https scheme on an allowlisted host', () {
      expect(
        resolveDeepLink(Uri.parse('http://thevsmart.com/products/abc')),
        isNull,
      );
    });

    test('rejects sections we do not publish links for', () {
      for (final url in [
        'https://thevsmart.com/orders/VS12345',
        'https://thevsmart.com/checkout',
        'https://thevsmart.com/credit/invoices/9',
        'https://thevsmart.com/privacy',
        'https://thevsmart.com/',
      ]) {
        expect(resolveDeepLink(Uri.parse(url)), isNull, reason: url);
      }
    });

    test('rejects a bare section with no identifier', () {
      expect(resolveDeepLink(Uri.parse('https://thevsmart.com/products')), isNull);
      expect(resolveDeepLink(Uri.parse('https://thevsmart.com/products/')), isNull);
    });

    test('rejects extra path segments', () {
      expect(
        resolveDeepLink(Uri.parse('https://thevsmart.com/products/abc/edit')),
        isNull,
      );
    });

    test('does not let an encoded separator smuggle a second segment', () {
      // %2F decodes to "/" — without the guard this would build
      // "/products/abc/../checkout" and land somewhere we never published.
      expect(
        resolveDeepLink(Uri.parse('https://thevsmart.com/products/abc%2F..%2Fcheckout')),
        isNull,
      );
    });

    test('escapes an identifier so it stays a single path segment', () {
      final path = resolveDeepLink(
        Uri.parse('https://thevsmart.com/products/a%20b'),
      );
      expect(path, '/products/a%20b');
    });
  });

  group('DeepLinkController', () {
    late PendingDeepLink pending;
    late int ticks;
    late DeepLinkController controller;

    setUp(() {
      pending = PendingDeepLink();
      ticks = 0;
      controller = DeepLinkController(
        pending: pending,
        onLink: () => ticks++,
        links: null,
      );
    });

    test('parks a recognised link and nudges the router', () {
      controller.handle(Uri.parse('https://thevsmart.com/products/abc123'));
      expect(pending.isPending, isTrue);
      expect(pending.take(), '/products/abc123');
      expect(ticks, 1);
    });

    test('ignores a link that is not ours', () {
      controller.handle(Uri.parse('https://evil.co/products/abc123'));
      expect(pending.isPending, isFalse);
      expect(ticks, 0);
    });

    test('does not act on the same link twice', () {
      // The launch link can arrive from BOTH getInitialLink() and the platform
      // stream; opening the product twice would push a duplicate route.
      final uri = Uri.parse('https://thevsmart.com/products/abc123');
      controller.handle(uri);
      controller.handle(uri);
      expect(ticks, 1);
    });

    test('a later, different link replaces an unconsumed one', () {
      controller.handle(Uri.parse('https://thevsmart.com/products/first'));
      controller.handle(Uri.parse('https://thevsmart.com/products/second'));
      expect(pending.take(), '/products/second');
    });
  });

  group('PendingDeepLink', () {
    test('take clears, so a bounced link cannot loop forever', () {
      final pending = PendingDeepLink()..park('/products/abc');
      expect(pending.take(), '/products/abc');
      expect(pending.take(), isNull);
      expect(pending.isPending, isFalse);
    });
  });
}
