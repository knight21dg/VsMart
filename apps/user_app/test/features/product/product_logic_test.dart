import 'package:flutter_test/flutter_test.dart';
import 'package:user_app/features/cart/presentation/providers/cart_providers.dart';
import 'package:user_app/features/catalog/domain/entities/product.dart';

Product _p({bool inStock = true, int? stockCount, num price = 100, num mrp = 120}) =>
    Product(id: '1', name: 'Rice', brand: 'VS', unit: '1kg', price: price, mrp: mrp,
        categoryId: 'c', inStock: inStock, stockCount: stockCount);

void main() {
  group('Product.stockStatus', () {
    test('in stock when count is healthy', () {
      expect(_p(stockCount: 10).stockStatus, StockStatus.inStock);
    });
    test('low stock at the boundary (<= 5)', () {
      expect(_p(stockCount: 5).stockStatus, StockStatus.lowStock);
      expect(_p(stockCount: 1).stockStatus, StockStatus.lowStock);
    });
    test('out of stock at zero count', () {
      expect(_p(stockCount: 0).stockStatus, StockStatus.outOfStock);
    });
    test('out of stock when the inStock flag is false', () {
      expect(_p(inStock: false, stockCount: 99).stockStatus, StockStatus.outOfStock);
    });
    test('in stock when count is unknown but flagged available', () {
      expect(_p(stockCount: null).stockStatus, StockStatus.inStock);
    });
  });

  group('cartItemFrom (add-to-cart mapping)', () {
    test('maps product fields and the chosen quantity', () {
      final item = cartItemFrom(_p(price: 50, mrp: 60), quantity: 3);
      expect(item.productId, '1');
      expect(item.name, 'Rice');
      expect(item.price, 50);
      expect(item.mrp, 60);
      expect(item.quantity, 3);
    });
    test('defaults quantity to 1', () {
      expect(cartItemFrom(_p()).quantity, 1);
    });
  });
}
