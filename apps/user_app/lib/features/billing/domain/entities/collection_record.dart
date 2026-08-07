import 'package:equatable/equatable.dart';

import 'billing_enums.dart';

/// A field-collection request/record. Shared shape with the future Agent App
/// (agent assignment) and Admin Panel (collection oversight).
class CollectionRecord extends Equatable {
  const CollectionRecord({
    required this.id,
    required this.amount,
    required this.status,
    required this.createdAt,
    this.agentId,
    this.agentName,
    this.collectedAt,
    this.method = RepaymentMethod.cashCollection,
    this.address,
  });

  final String id;
  final num amount;
  final CollectionStatus status;
  final DateTime createdAt;
  final String? agentId;
  final String? agentName;
  final DateTime? collectedAt;
  final RepaymentMethod method;
  final String? address;

  bool get isAssigned => agentId != null;

  @override
  List<Object?> get props => [
        id,
        amount,
        status,
        createdAt,
        agentId,
        agentName,
        collectedAt,
        method,
        address,
      ];
}
