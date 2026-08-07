import 'package:equatable/equatable.dart';

import '../../../app/constants/api_constants.dart';
import '../../../core/network/api_client.dart';

/// A single product rating & review left by a customer.
class Review extends Equatable {
  const Review({
    required this.id,
    required this.rating,
    required this.title,
    required this.body,
    required this.createdAt,
    required this.authorName,
  });

  final String id;
  final int rating;
  final String title;
  final String body;
  final DateTime createdAt;
  final String authorName;

  @override
  List<Object?> get props => [id, rating, title, body, createdAt, authorName];
}

/// Aggregated rating stats for a product: average, total count, and the
/// per-star (1..5) distribution.
class ReviewSummary extends Equatable {
  const ReviewSummary({
    required this.average,
    required this.count,
    required this.distribution,
  });

  final double average;
  final int count;

  /// Map of star value (1..5) -> number of reviews at that rating.
  final Map<int, int> distribution;

  /// How many reviews carry [star] stars (0 when absent).
  int countFor(int star) => distribution[star] ?? 0;

  static const ReviewSummary empty =
      ReviewSummary(average: 0, count: 0, distribution: {});

  @override
  List<Object?> get props => [average, count, distribution];
}

/// The full reviews payload for a product: the list plus its summary.
class ProductReviews extends Equatable {
  const ProductReviews({required this.reviews, required this.summary});

  final List<Review> reviews;
  final ReviewSummary summary;

  static const ProductReviews empty =
      ProductReviews(reviews: [], summary: ReviewSummary.empty);

  @override
  List<Object?> get props => [reviews, summary];
}

/// Backend reviews API: `/products/{id}/reviews` (public GET, auth POST) and
/// `/reviews/mine` (auth GET).
class ReviewsRemoteDataSource {
  ReviewsRemoteDataSource(this._client);
  final ApiClient _client;

  List<Map<String, dynamic>> _list(dynamic raw) {
    final data = raw is Map ? raw['data'] : raw;
    final list = data is List ? data : const [];
    return list.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList();
  }

  Map<String, dynamic> _obj(dynamic raw) {
    final data = raw is Map && raw['data'] is Map ? raw['data'] : raw;
    return data is Map ? Map<String, dynamic>.from(data) : <String, dynamic>{};
  }

  DateTime _date(dynamic v) =>
      DateTime.tryParse(v?.toString() ?? '')?.toLocal() ?? DateTime.now();

  int _int(dynamic v) {
    if (v is int) return v;
    if (v is num) return v.round();
    return int.tryParse(v?.toString() ?? '') ?? 0;
  }

  double _double(dynamic v) {
    if (v is num) return v.toDouble();
    return double.tryParse(v?.toString() ?? '') ?? 0;
  }

  Review _toReview(Map<String, dynamic> j) => Review(
        id: (j['id'] ?? '').toString(),
        rating: _int(j['rating']).clamp(0, 5),
        title: (j['title'] ?? '').toString(),
        body: (j['body'] ?? '').toString(),
        createdAt: _date(j['createdAt']),
        authorName: (j['authorName'] ?? 'Anonymous').toString(),
      );

  ReviewSummary _toSummary(Map<String, dynamic> j) {
    final raw = j['distribution'];
    final dist = <int, int>{};
    if (raw is Map) {
      raw.forEach((key, value) {
        final star = int.tryParse(key.toString());
        if (star != null && star >= 1 && star <= 5) {
          dist[star] = _int(value);
        }
      });
    }
    return ReviewSummary(
      average: _double(j['average']),
      count: _int(j['count']),
      distribution: dist,
    );
  }

  /// Public: fetch a product's reviews and summary.
  Future<ProductReviews> getForProduct(String productId) async {
    final res = await _client.get<dynamic>(
      ApiConstants.productReviews(productId),
      options: ApiClient.noAuth(),
    );
    final data = _obj(res.data);
    return ProductReviews(
      reviews: ((data['reviews'] as List?) ?? const [])
          .whereType<Map>()
          .map((m) => _toReview(Map<String, dynamic>.from(m)))
          .toList(),
      summary: _toSummary(_obj(data['summary'])),
    );
  }

  /// Auth: submit a review for a product; returns the saved review.
  Future<Review> postReview({
    required String productId,
    required int rating,
    String title = '',
    String body = '',
  }) async {
    final res = await _client.post<dynamic>(
      ApiConstants.productReviews(productId),
      data: {
        'rating': rating,
        if (title.isNotEmpty) 'title': title,
        if (body.isNotEmpty) 'body': body,
      },
    );
    return _toReview(_obj(res.data));
  }

  /// Auth: the signed-in user's own reviews.
  Future<List<Review>> myReviews() async {
    final res = await _client.get<dynamic>(ApiConstants.myReviews);
    return _list(res.data).map(_toReview).toList();
  }
}
