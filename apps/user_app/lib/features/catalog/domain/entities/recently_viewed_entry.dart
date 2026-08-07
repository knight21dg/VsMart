import 'package:equatable/equatable.dart';

/// A product the customer recently viewed, with the time it was last opened.
class RecentlyViewedEntry extends Equatable {
  const RecentlyViewedEntry({required this.productId, required this.viewedAt});

  final String productId;
  final DateTime viewedAt;

  @override
  List<Object?> get props => [productId, viewedAt];
}
