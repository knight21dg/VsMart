import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/extensions/context_extensions.dart';
import '../../../shared/providers/core_providers.dart';
import '../domain/entities/product.dart';

/// Shares a product's link from ANY surface that renders a product card
/// (home rails, category, sub-category, search, sections, related).
///
/// Kept here so every card shares identically — same link, same blurb, same
/// analytics — instead of each screen re-implementing it.
Future<void> shareProductLink(
  BuildContext context,
  WidgetRef ref,
  Product product,
) async {
  try {
    await ref.read(shareServiceProvider).shareProduct(
          productId: product.id,
          shareToken: product.shareToken,
          name: product.name,
          brand: product.brand,
          price: product.price,
        );
    ref
        .read(analyticsServiceProvider)
        .track('product_shared', {'product': product.id});
  } catch (_) {
    if (!context.mounted) return;
    context.showSnack(context.l10n.catalogShareSheetError, isError: true);
  }
}
