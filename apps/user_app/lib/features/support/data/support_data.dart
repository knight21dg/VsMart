import 'package:dio/dio.dart';
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

/// The platform-wide fallback support contact ([PlatformConfig] on the
/// backend) — used when no zone/store is resolved for the caller.
class SupportContact extends Equatable {
  const SupportContact({this.phone, this.email});
  final String? phone;
  final String? email;
  @override
  List<Object?> get props => [phone, email];
}

/// Backend support API: `/support/faqs`, `/support/tickets`, `/support/contact`.
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

  /// The platform-wide fallback support number/email (public, no auth).
  Future<SupportContact> getContact() async {
    final res = await _client.get<dynamic>(ApiConstants.supportContact, options: ApiClient.noAuth());
    final j = _obj(res.data);
    return SupportContact(
      phone: (j['supportPhone'] as String?)?.trim().isNotEmpty == true ? j['supportPhone'] as String : null,
      email: (j['supportEmail'] as String?)?.trim().isNotEmpty == true ? j['supportEmail'] as String : null,
    );
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

  Future<void> sendMessage(
    String code,
    String body, {
    List<Map<String, dynamic>>? attachments,
  }) =>
      _client.post<dynamic>('${ApiConstants.supportTickets}/$code/messages',
          data: {
            'body': body,
            if (attachments != null && attachments.isNotEmpty)
              'attachments': attachments,
          });

  /// Closes the caller's own ticket (idempotent). Returns the refreshed ticket.
  Future<SupportTicket> closeTicket(String code) async {
    final res = await _client
        .post<dynamic>('${ApiConstants.supportTickets}/$code/close');
    return _toTicket(_obj(res.data));
  }

  /// Uploads one attachment image to the authenticated media endpoint and
  /// returns an `{name, url}` map ready to attach to a ticket message. The URL
  /// is a private asset owned by the customer; support staff can view it.
  Future<Map<String, dynamic>> uploadAttachment(String filePath) async {
    final fileName = filePath.split(RegExp(r'[\\/]')).last;
    final res = await _client.post<dynamic>(
      ApiConstants.mediaUpload,
      data: FormData.fromMap({
        'category': 'support',
        'file': await MultipartFile.fromFile(filePath, filename: fileName),
      }),
    );
    final data = _obj(res.data);
    final variants = data['variants'];
    final url = (variants is Map
                ? (variants['medium'] ?? variants['original'])
                : null)
            ?.toString() ??
        '';
    return {'name': fileName, 'url': url};
  }

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
