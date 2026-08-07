import 'package:equatable/equatable.dart';

import 'category.dart';
import 'product.dart';

/// As-you-type autocomplete payload for the search screen: a few matching
/// products (with thumbnails), completion terms, and matching categories.
///
/// Returned by the lightweight `/products/suggest` endpoint — distinct from the
/// full [Product] result set that a submitted search returns.
class SearchSuggestions extends Equatable {
  const SearchSuggestions({
    this.products = const [],
    this.terms = const [],
    this.categories = const [],
  });

  /// Top matching products, richest suggestion (image + price + brand).
  final List<Product> products;

  /// Query-completion terms (product names / brands) for one-tap refinement.
  final List<String> terms;

  /// Categories whose name matches the query — a shortcut into the department.
  final List<Category> categories;

  static const empty = SearchSuggestions();

  bool get isEmpty =>
      products.isEmpty && terms.isEmpty && categories.isEmpty;

  bool get isNotEmpty => !isEmpty;

  @override
  List<Object?> get props => [products, terms, categories];
}
