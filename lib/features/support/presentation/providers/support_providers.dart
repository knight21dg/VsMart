import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../shared/providers/core_providers.dart';
import '../../data/support_data.dart';

final supportDataSourceProvider = Provider<SupportRemoteDataSource>(
  (ref) => SupportRemoteDataSource(ref.watch(apiClientProvider)),
);

/// Help-centre FAQs (public).
final faqsProvider = FutureProvider<List<Faq>>(
  (ref) => ref.watch(supportDataSourceProvider).getFaqs(),
);

/// The customer's support tickets, most recent first.
final ticketsProvider = FutureProvider<List<SupportTicket>>(
  (ref) => ref.watch(supportDataSourceProvider).getTickets(),
);

/// A single ticket with its message thread.
final ticketProvider = FutureProvider.family<SupportTicket, String>(
  (ref, code) => ref.watch(supportDataSourceProvider).getTicket(code),
);
