import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/extensions/context_extensions.dart';
import '../../../../core/utils/launch_helpers.dart';
import '../../../../core/widgets/widgets.dart';
import '../../../serviceability/presentation/providers/serviceability_providers.dart';
import '../providers/support_providers.dart';

/// The one Call Support action across the (simplified) Help & Support flow.
///
/// Resolves the number to dial in order: the customer's own serving store
/// (so the call reaches the store handling their orders) → the platform-wide
/// fallback number from admin settings → a hardcoded last resort. All of that
/// is invisible to the customer — they just see one "Call Support" button.
class SupportCallButton extends ConsumerWidget {
  const SupportCallButton({super.key, this.outlined = false});

  final bool outlined;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final storePhone = ref.watch(currentServiceabilityProvider).storePhone;
    final fallbackPhone = ref.watch(supportContactProvider).valueOrNull?.phone;
    final phone = (storePhone != null && storePhone.trim().isNotEmpty)
        ? storePhone
        : fallbackPhone;

    void onCall() => callSupport(context, phone: phone);

    return outlined
        ? VSOutlinedButton(
            label: context.l10n.supportCallSupport,
            icon: Icons.call_rounded,
            onPressed: onCall,
          )
        : VSButton(
            label: context.l10n.supportCallSupport,
            icon: Icons.call_rounded,
            onPressed: onCall,
          );
  }
}
