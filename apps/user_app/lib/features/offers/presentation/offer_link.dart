import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../app/routes/route_paths.dart';
import '../../../shared/providers/core_providers.dart';
import '../domain/entities/offer.dart';
import 'providers/banner_event_sink.dart';

/// Handle a banner tap: record analytics (local + backend click event) and
/// navigate by the offer's [OfferAction] enum + payload. The app never parses
/// URLs — it branches on the enum.
void handleOfferTap(
  BuildContext context,
  WidgetRef ref,
  Offer offer, {
  String? placement,
}) {
  ref.read(analyticsServiceProvider).track('banner_clicked', {
    'offer': offer.id,
    if (placement != null) 'placement': placement,
  });
  ref.read(bannerEventSinkProvider).click(offer.id);
  _navigate(context, offer);
}

void _navigate(BuildContext context, Offer offer) {
  String? p(String key) => offer.payload[key]?.toString();

  switch (offer.action) {
    case OfferAction.product:
      final id = p('productId') ?? offer.productId;
      if (id != null && id.isNotEmpty) {
        context.pushNamed(RouteNames.productDetails,
            pathParameters: {'productId': id});
        return;
      }
      _fallback(context, offer);
    case OfferAction.category:
      final id = p('categoryId');
      if (id != null && id.isNotEmpty) {
        context.pushNamed(RouteNames.products,
            queryParameters: {'categoryId': id, 'title': offer.title});
        return;
      }
      _fallback(context, offer);
    case OfferAction.search:
      context.pushNamed(RouteNames.search);
    case OfferAction.credit:
      context.goNamed(RouteNames.creditDashboard);
    case OfferAction.offers:
      context.pushNamed(RouteNames.offers);
    case OfferAction.cart:
      context.goNamed(RouteNames.cart);
    case OfferAction.profile:
      context.pushNamed(RouteNames.profile);
    case OfferAction.order:
      final id = p('orderId');
      if (id != null && id.isNotEmpty) {
        context.pushNamed(RouteNames.orderDetails,
            pathParameters: {'orderId': id});
        return;
      }
      context.pushNamed(RouteNames.orders);
    case OfferAction.home:
      context.goNamed(RouteNames.home);
    case OfferAction.external:
      _openExternal(context, offer);
    // No dedicated brand/store screens yet — fall back to the product or hub.
    case OfferAction.brand:
    case OfferAction.store:
    case OfferAction.none:
      _fallback(context, offer);
  }
}

/// Open an `external` banner's link in the system browser.
///
/// The server only accepts absolute `https://` URLs for this action (see
/// `offers/validators.py`), but re-check the scheme here: a stale cached banner
/// could predate that validation, and launching an arbitrary scheme from a
/// server-controlled string is exactly the kind of thing that shouldn't be
/// trusted twice.
Future<void> _openExternal(BuildContext context, Offer offer) async {
  final raw = offer.payload['url']?.toString();
  final uri = raw == null ? null : Uri.tryParse(raw);
  if (uri == null || uri.scheme != 'https' || uri.host.isEmpty) {
    if (context.mounted) _fallback(context, offer);
    return;
  }
  final launched = await launchUrl(uri, mode: LaunchMode.externalApplication);
  if (!launched && context.mounted) _fallback(context, offer);
}

/// Legacy behaviour: open the linked product if any, else the offers hub.
void _fallback(BuildContext context, Offer offer) {
  final id = offer.productId;
  if (id != null && id.isNotEmpty) {
    context.pushNamed(RouteNames.productDetails,
        pathParameters: {'productId': id});
  } else {
    context.pushNamed(RouteNames.offers);
  }
}
