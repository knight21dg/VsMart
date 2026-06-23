import 'package:equatable/equatable.dart';

/// Category of an in-app notification, controlling its icon/accent and the
/// filter tab it belongs to.
enum NotificationType { order, delivery, credit, payment, offer, account }

/// A single notification shown in the in-app inbox.
class AppNotification extends Equatable {
  const AppNotification({
    required this.id,
    required this.title,
    required this.body,
    required this.type,
    required this.time,
    this.read = false,
    this.important = false,
    this.actionLabel,
    this.route,
  });

  final String id;
  final String title;
  final String body;
  final NotificationType type;
  final DateTime time;
  final bool read;
  final bool important;

  /// Optional inline CTA (e.g. "Track Order", "Pay Now", "Claim Offer").
  final String? actionLabel;

  /// Optional named route opened by the CTA / tapping the card.
  final String? route;

  AppNotification copyWith({bool? read}) => AppNotification(
        id: id,
        title: title,
        body: body,
        type: type,
        time: time,
        read: read ?? this.read,
        important: important,
        actionLabel: actionLabel,
        route: route,
      );

  @override
  List<Object?> get props =>
      [id, title, body, type, time, read, important, actionLabel, route];
}
