import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../app/routes/route_paths.dart';
import '../../../../app/theme/app_theme.dart';
import '../../../../core/errors/app_error_presenter.dart';
import '../../../../core/errors/error_handler.dart';
import '../../../../core/extensions/context_extensions.dart';
import '../../../../core/widgets/widgets.dart';
import '../../../../shared/providers/core_providers.dart';
import '../../domain/entities/address.dart';
import '../providers/address_providers.dart';
import '../providers/address_selection_provider.dart';
import '../widgets/address_widgets.dart';

/// Reusable address selection module (Cart → Checkout → Address → Payment).
/// Kept separate from checkout so it can be reused from Profile and Orders.
class AddressSelectionScreen extends ConsumerWidget {
  const AddressSelectionScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final vs = context.vsColors;
    final addresses = ref.watch(addressesProvider);
    final hydrating = ref.watch(addressesHydratingProvider);
    final selectedId = ref.watch(addressSelectionProvider).selectedId;
    final connectivity = ref.watch(commerceConnectivityProvider);

    return Scaffold(
      appBar: VSAppBar(title: context.l10n.checkoutSelectAddress),
      body: Column(
        children: [
          VSOfflineBanner(
            offline: connectivity == CommerceConnectivity.offline,
            syncing: connectivity == CommerceConnectivity.syncing,
          ),
          Expanded(
            child: addresses.isEmpty
                ? (hydrating
                    ? const VSLoadingView()
                    : VSNoAddressState(
                        onAdd: () => context.pushNamed(RouteNames.addAddress),
                      ))
                : RefreshIndicator(
                    onRefresh: () async => ref.invalidate(addressesProvider),
                    child: ListView(
                      padding: AppSpacing.screen,
                      children: [
                        VSAddressSelector(
                          addresses: addresses,
                          selectedId: selectedId,
                          onSelect: (a) {
                            ref
                                .read(addressSelectionProvider.notifier)
                                .select(a.id);
                            ref.read(analyticsServiceProvider).track(
                                'address_selected', {'address': a.id});
                          },
                          onEdit: (a) => context.pushNamed(
                            RouteNames.addAddress,
                            extra: a,
                          ),
                          onDelete: (a) => _confirmDelete(context, ref, a),
                        ),
                        OutlinedButton.icon(
                          onPressed: () =>
                              context.pushNamed(RouteNames.addAddress),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: vs.brand,
                            side: BorderSide(color: vs.brand),
                            minimumSize: const Size(double.infinity, 48),
                            shape: const RoundedRectangleBorder(
                                borderRadius: AppRadius.brMd),
                          ),
                          icon: const Icon(Icons.add_rounded),
                          label: Text(context.l10n.checkoutAddNewAddress),
                        ),
                      ],
                    ),
                  ),
          ),
          if (addresses.isNotEmpty)
            Container(
              decoration: BoxDecoration(
                color: context.colors.surface,
                border: Border(top: BorderSide(color: vs.border)),
              ),
              child: SafeArea(
                minimum: AppSpacing.screen,
                child: VSButton(
                  label: 'Deliver to this Address',
                  onPressed: selectedId == null ? null : () => context.pop(),
                ),
              ),
            ),
        ],
      ),
    );
  }

  /// Confirms before removing an address (a destructive, single-tap action) and
  /// surfaces an actionable error if the backend delete fails.
  Future<void> _confirmDelete(
    BuildContext context,
    WidgetRef ref,
    Address address,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete address?'),
        content: Text(
          address.name.trim().isNotEmpty
              ? 'Remove "${address.name}" from your saved addresses? '
                  'This cannot be undone.'
              : 'Remove this address from your saved addresses? '
                  'This cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(ctx.l10n.commonCancel),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(
              foregroundColor: ctx.vsColors.danger,
            ),
            child: Text(ctx.l10n.commonDelete),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    if (!context.mounted) return;
    try {
      await ref.read(addressesProvider.notifier).remove(address.id);
    } catch (e) {
      if (!context.mounted) return;
      presentFailure(context, ref, ErrorHandler.handle(e));
    }
  }
}
