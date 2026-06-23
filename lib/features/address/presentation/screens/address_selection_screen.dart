import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../app/routes/route_paths.dart';
import '../../../../app/theme/app_theme.dart';
import '../../../../core/extensions/context_extensions.dart';
import '../../../../core/widgets/widgets.dart';
import '../../../../shared/providers/core_providers.dart';
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
    final selectedId = ref.watch(addressSelectionProvider).selectedId;
    final connectivity = ref.watch(commerceConnectivityProvider);

    return Scaffold(
      appBar: const VSAppBar(title: 'Select Address'),
      body: Column(
        children: [
          VSOfflineBanner(
            offline: connectivity == CommerceConnectivity.offline,
            syncing: connectivity == CommerceConnectivity.syncing,
          ),
          Expanded(
            child: addresses.isEmpty
                ? VSNoAddressState(
                    onAdd: () => context.pushNamed(RouteNames.addAddress),
                  )
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
                          onDelete: (a) => ref
                              .read(addressesProvider.notifier)
                              .remove(a.id),
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
                          label: const Text('Add New Address'),
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
}
