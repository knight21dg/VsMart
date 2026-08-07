import 'package:share_plus/share_plus.dart';

/// Builds canonical VS Mart links and hands them to the OS share sheet.
///
/// The product link mirrors the in-app route (`/products/<id>`), so once Android
/// App Links / iOS Universal Links are configured for `thevsmart.com` the same
/// URL opens the product straight in the app; until then it stays a valid,
/// shareable web link.
class ShareService {
  const ShareService();

  /// Public site origin that backs our shareable links.
  static const String siteOrigin = 'https://thevsmart.com';

  /// The canonical, shareable URL for a product. Prefers the unguessable
  /// [shareToken] so a store-private product can be shared without leaking its
  /// numeric id; falls back to the id for older payloads without a token.
  static String productLink(String productId, {String? shareToken}) {
    final slug = (shareToken != null && shareToken.isNotEmpty)
        ? shareToken
        : productId;
    return '$siteOrigin/products/$slug';
  }

  /// Opens the native share sheet with a friendly blurb + the product link.
  /// Returns false when the user dismissed the sheet without sharing.
  Future<bool> shareProduct({
    required String productId,
    String? shareToken,
    required String name,
    String? brand,
    num? price,
    String? currencySymbol,
  }) async {
    final link = productLink(productId, shareToken: shareToken);
    final symbol = currencySymbol ?? '₹';
    final buf = StringBuffer();
    buf.writeln(brand == null || brand.isEmpty ? name : '$name by $brand');
    if (price != null) buf.writeln('$symbol$price');
    buf
      ..writeln()
      ..writeln('Order it on VS Mart:')
      ..write(link);

    final result = await SharePlus.instance.share(
      ShareParams(text: buf.toString(), subject: name, title: name),
    );
    return result.status == ShareResultStatus.success;
  }
}
