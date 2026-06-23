import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../auth/presentation/providers/current_user_provider.dart';
import '../../domain/credit_access.dart';

/// Reactive [CreditAccess] for the signed-in customer. Watch this anywhere a
/// credit surface might render so non-applied customers only ever see the
/// "Apply for VS Credit" prompt — never a balance, statement or dashboard.
final creditAccessProvider = Provider<CreditAccess>(
  (ref) => creditAccessForUser(ref.watch(currentUserProvider)),
);
