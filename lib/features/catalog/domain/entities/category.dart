import 'package:equatable/equatable.dart';

/// A product category / department in the catalog. UI and business logic depend
/// on this entity, never on the data-layer model.
class Category extends Equatable {
  const Category({
    required this.id,
    required this.name,
    required this.productCount,
    this.imageUrl,
    this.iconName,
    this.parentId,
  });

  final String id;
  final String name;
  final int productCount;

  /// Remote image for the category (preferred once the backend is wired).
  final String? imageUrl;

  /// Data-driven icon token used as a fallback when [imageUrl] is null
  /// (mapped to an [IconData] in the presentation layer).
  final String? iconName;

  /// Parent category id for sub-categories; null for top-level departments.
  final String? parentId;

  @override
  List<Object?> get props => [id, name, productCount, imageUrl, iconName, parentId];
}
