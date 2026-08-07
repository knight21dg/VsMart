import 'package:equatable/equatable.dart';

/// How a delivered order went — VS Mart's ONLY rating surface.
///
/// Products carry no ratings (for groceries they add nothing), so feedback is
/// captured per ORDER: the delivery, not the apple. The backend raises the
/// request automatically when a delivery completes; [available] is false until
/// then.
class OrderFeedback extends Equatable {
  const OrderFeedback({
    required this.available,
    required this.rated,
    this.rating,
    this.feedback = '',
    this.agentName,
  });

  const OrderFeedback.unavailable()
      : available = false,
        rated = false,
        rating = null,
        feedback = '',
        agentName = null;

  /// True once the order is delivered and feedback has been requested.
  final bool available;

  /// True once the customer has answered (they may still change it).
  final bool rated;
  final int? rating;
  final String feedback;
  final String? agentName;

  factory OrderFeedback.fromJson(Map<String, dynamic> j) => OrderFeedback(
        available: j['available'] == true,
        rated: j['rated'] == true,
        rating: (j['rating'] as num?)?.toInt(),
        feedback: (j['feedback'] ?? '').toString(),
        agentName: (j['agentName'] as String?)?.trim().isNotEmpty == true
            ? j['agentName'] as String
            : null,
      );

  @override
  List<Object?> get props => [available, rated, rating, feedback, agentName];
}
