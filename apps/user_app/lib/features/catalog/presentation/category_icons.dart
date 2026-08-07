import 'package:flutter/material.dart';

/// Maps a [Category.iconName] token to a Material icon for the fixture phase
/// (until categories carry a remote `imageUrl`). Presentation-only, so the
/// catalog domain stays free of Flutter types.
IconData categoryIcon(String? iconName) {
  switch (iconName) {
    case 'vegetables':
      return Icons.eco_rounded;
    case 'fruits':
      return Icons.apple_rounded;
    case 'dairy':
      return Icons.egg_alt_rounded;
    case 'drinks':
      return Icons.local_cafe_rounded;
    case 'snacks':
      return Icons.cookie_rounded;
    case 'staples':
      return Icons.rice_bowl_rounded;
    case 'household':
      return Icons.cleaning_services_rounded;
    case 'personal':
      return Icons.spa_rounded;
    case 'bakery':
      return Icons.bakery_dining_rounded;
    case 'leafy':
      return Icons.grass_rounded;
    case 'root':
      return Icons.spa_rounded;
    case 'organic':
      return Icons.energy_savings_leaf_rounded;
    case 'exotic':
      return Icons.park_rounded;
    case 'cut':
      return Icons.set_meal_rounded;
    case 'herbs':
      return Icons.local_florist_rounded;
    case 'mushrooms':
      return Icons.bubble_chart_rounded;
    // ---- DummyJSON category slugs ----
    case 'beauty':
      return Icons.brush_rounded;
    case 'fragrances':
      return Icons.local_florist_rounded;
    case 'furniture':
      return Icons.chair_rounded;
    case 'groceries':
      return Icons.local_grocery_store_rounded;
    case 'home-decoration':
      return Icons.home_rounded;
    case 'kitchen-accessories':
      return Icons.kitchen_rounded;
    case 'laptops':
      return Icons.laptop_mac_rounded;
    case 'mens-shirts':
    case 'tops':
    case 'womens-dresses':
      return Icons.checkroom_rounded;
    case 'mens-shoes':
    case 'womens-shoes':
      return Icons.directions_walk_rounded;
    case 'mens-watches':
    case 'womens-watches':
      return Icons.watch_rounded;
    case 'mobile-accessories':
      return Icons.cable_rounded;
    case 'motorcycle':
      return Icons.two_wheeler_rounded;
    case 'skin-care':
      return Icons.face_retouching_natural_rounded;
    case 'smartphones':
      return Icons.smartphone_rounded;
    case 'sports-accessories':
      return Icons.sports_basketball_rounded;
    case 'sunglasses':
      return Icons.remove_red_eye_rounded;
    case 'tablets':
      return Icons.tablet_mac_rounded;
    case 'vehicle':
      return Icons.directions_car_rounded;
    case 'womens-bags':
      return Icons.shopping_bag_rounded;
    case 'womens-jewellery':
      return Icons.diamond_rounded;
    default:
      return Icons.category_rounded;
  }
}
