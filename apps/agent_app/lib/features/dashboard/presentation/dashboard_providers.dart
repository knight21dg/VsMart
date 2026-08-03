import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/providers.dart';
import '../data/dashboard_data.dart';

final dashboardRepoProvider = Provider<DashboardRepo>(
  (ref) => DashboardRepo(ref.watch(apiProvider)),
);

final agentProfileProvider = FutureProvider.autoDispose<AgentProfile>(
  (ref) => ref.watch(dashboardRepoProvider).me(),
);

final agentPerformanceProvider = FutureProvider.autoDispose<AgentPerformance>(
  (ref) => ref.watch(dashboardRepoProvider).performance(),
);

final agentEarningsProvider = FutureProvider.autoDispose<AgentEarnings>(
  (ref) => ref.watch(dashboardRepoProvider).earnings(),
);

final agentAttendanceProvider = FutureProvider.autoDispose<AgentAttendance>(
  (ref) => ref.watch(dashboardRepoProvider).attendance(),
);

final agentIncentivesProvider =
    FutureProvider.autoDispose<List<AgentIncentive>>(
  (ref) => ref.watch(dashboardRepoProvider).incentives(),
);

/// Keyed by "YYYY-MM" (empty string = current month) so switching months in
/// the attendance calendar is just a different family key, not manual state.
final attendanceHistoryProvider =
    FutureProvider.autoDispose.family<AttendanceHistory, String>(
  (ref, month) => ref
      .watch(dashboardRepoProvider)
      .attendanceHistory(month: month.isEmpty ? null : month),
);
