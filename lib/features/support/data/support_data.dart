import 'package:equatable/equatable.dart';

import '../../../app/constants/api_constants.dart';
import '../../../core/network/api_client.dart';

/// A help-centre FAQ entry.
class Faq extends Equatable {
  const Faq({required this.id, required this.category, required this.question, required this.answer});
  final String id;
  final String category;
  final String question;
  final String answer;
  @override
  List<Object?> get props => [id, category, question, answer];
}

/// A single message within a support ticket thread.
class TicketMessage extends Equatable {
  const TicketMessage({required this.senderName, required this.body, required this.at});
  final String senderName;
  final String body;
  final DateTime at;
  @override
  List<Object?> get props => [senderName, body, at];
}

/// A support ticket (with its message thread when fetched in detail).
class SupportTicket extends Equatable {
  const SupportTicket({
    required this.id,
    required this.category,
    required this.subject,
    required this.status,
    this.priority = 'medium',
    this.orderCode,
    required this.createdAt,
    this.messages = const [],
  });
  final String id;
  final String category;
  final String subject;
  final String status;
  final String priority;
  final String? orderCode;
  final DateTime createdAt;
  final List<TicketMessage> messages;
  @override
  List<Object?> get props =>
      [id, category, subject, status, priority, orderCode, createdAt, messages];
}

/// Backend support API: `/support/faqs`, `/support/tickets`.
class SupportRemoteDataSource {
  SupportRemoteDataSource(this._client);
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

  Future<List<Faq>> getFaqs() async {
    final res = await _client.get<dynamic>(ApiConstants.supportFaqs, options: ApiClient.noAuth());
    return _list(res.data)
        .map((j) => Faq(
              id: (j['id'] ?? '').toString(),
              category: (j['category'] ?? 'General').toString(),
              question: (j['question'] ?? '').toString(),
              answer: (j['answer'] ?? '').toString(),
            ))
        .toList();
  }

  Future<List<SupportTicket>> getTickets() async {
    final res = await _client.get<dynamic>(ApiConstants.supportTickets);
    return _list(res.data).map(_toTicket).toList();
  }

  Future<SupportTicket> getTicket(String code) async {
    final res = await _client.get<dynamic>('${ApiConstants.supportTickets}/$code');
    return _toTicket(_obj(res.data));
  }

  Future<SupportTicket> createTicket({
    required String category,
    required String subject,
    String priority = 'medium',
    String? orderCode,
  }) async {
    final res = await _client.post<dynamic>(ApiConstants.supportTickets, data: {
      'category': category,
      'subject': subject,
      'priority': priority,
      if (orderCode != null && orderCode.isNotEmpty) 'order_code': orderCode,
    });
    return _toTicket(_obj(res.data));
  }

  Future<void> sendMessage(String code, String body) =>
      _client.post<dynamic>('${ApiConstants.supportTickets}/$code/messages',
          data: {'body': body});

  SupportTicket _toTicket(Map<String, dynamic> j) => SupportTicket(
        id: (j['id'] ?? '').toString(),
        category: (j['category'] ?? '').toString(),
        subject: (j['subject'] ?? '').toString(),
        status: (j['status'] ?? 'open').toString(),
        priority: (j['priority'] ?? 'medium').toString(),
        orderCode: j['orderCode'] as String?,
        createdAt: _date(j['createdAt']),
        messages: ((j['messages'] as List?) ?? const [])
            .whereType<Map>()
            .map((m) => TicketMessage(
                  senderName: (m['senderName'] ?? 'You').toString(),
                  body: (m['body'] ?? '').toString(),
                  at: _date(m['createdAt']),
                ))
            .toList(),
      );
}
