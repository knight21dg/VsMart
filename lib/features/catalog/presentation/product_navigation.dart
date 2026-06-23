import 'package:flutter/widgets.dart';
import 'package:go_router/go_router.dart';

import '../../../app/routes/route_paths.dart';

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
