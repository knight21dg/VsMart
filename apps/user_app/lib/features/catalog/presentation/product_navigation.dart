import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/routes/route_paths.dart';
import '../../cart/presentation/providers/cart_providers.dart';
import '../domain/entities/product.dart';

/// Shared-hero tag pairing a product card with the product DETAIL route.
/// [source] keeps tags unique on screens that show the same product in more than
/// one place (e.g. Home's Popular + Recommended rails), so Hero never sees a
/// duplicate tag on a single route.
String detailHeroTag(String source, String id) => 'hero-$source-$id';

/// Open the product detail route, passing the matching hero tag via `extra` so
/// the tapped card's image morphs into the detail gallery (and back). Pass the
/// SAME [source] you gave the card's `heroTag`.
void openProductDetail(
  BuildContext context, {
  required String productId,
  required String source,
}) {
  context.pushNamed(
    RouteNames.productDetails,
    pathParameters: {'productId': productId},
    extra: detailHeroTag(source, productId),
  );
}

/// The "＋" on a listing card. A product with NO packs adds straight to the cart,
/// as before. A product WITH packs can't be added blind — each pack is priced and
/// stocked separately — so we open the detail sheet for the shopper to pick one,
/// instead of silently adding an unspecified pack that the backend then rejects at
/// checkout (reserving a variant product with no variant is refused).
void addToCartOrChoose(
  BuildContext context,
  WidgetRef ref,
  Product product, {
  String source = 'listing',
}) {
  if (product.variants.isEmpty) {
    ref.read(cartControllerProvider.notifier).addProduct(product);
    return;
  }
  openProductDetail(context, productId: product.id, source: source);
}
