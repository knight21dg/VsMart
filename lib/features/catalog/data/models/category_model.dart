import '../../domain/entities/category.dart';

/// JSON serialization for [Category] (cache + future remote API).
abstract final class CategoryModel {
  CategoryModel._();

  static Map<String, dynamic> toJson(Category c) => {
        'id': c.id,
        'name': c.name,
        'productCount': c.productCount,
        'imageUrl': c.imageUrl,
        'iconName': c.iconName,
        'parentId': c.parentId,
      };

  static Category fromJson(Map<String, dynamic> j) => Category(
        id: j['id'] as String? ?? '',
        name: j['name'] as String? ?? '',
        productCount: (j['productCount'] as num?)?.toInt() ?? 0,
        imageUrl: j['imageUrl'] as String?,
        iconName: j['iconName'] as String?,
        parentId: j['parentId'] as String?,
      );
}
