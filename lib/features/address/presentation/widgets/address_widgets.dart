import 'package:flutter/material.dart';

import '../../../../app/theme/app_theme.dart';
import '../../../../core/widgets/widgets.dart';
import '../../domain/entities/address.dart';

/// Selectable list of saved addresses (reuses the core [VSAddressCard]).
class VSAddressSelector extends StatelessWidget {
  const VSAddressSelector({
    super.key,
    required this.addresses,
    required this.selectedId,
    required this.onSelect,
    this.onEdit,
    this.onDelete,
  });

  final List<Address> addresses;
  final String? selectedId;
  final ValueChanged<Address> onSelect;
  final ValueChanged<Address>? onEdit;
  final ValueChanged<Address>? onDelete;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        for (final a in addresses) ...[
          VSAddressCard(
            label: a.isDefault ? 'Home' : 'Address',
            fullAddress: a.formatted,
            recipientName: a.name,
            phone: a.phone.isEmpty ? null : a.phone,
            isDefault: a.isDefault,
            isSelected: a.id == selectedId,
            onTap: () => onSelect(a),
            onEdit: onEdit == null ? null : () => onEdit!(a),
            onDelete: onDelete == null ? null : () => onDelete!(a),
          ),
          AppSpacing.vGapMd,
        ],
      ],
    );
  }
}

/// Empty state when the customer has no saved addresses.
class VSNoAddressState extends StatelessWidget {
  const VSNoAddressState({super.key, required this.onAdd});

  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    return VSEmptyState(
      title: 'No addresses yet',
      message: 'Add a delivery address to place your order.',
      icon: Icons.location_off_rounded,
      actionLabel: 'Add Address',
      onAction: onAdd,
    );
  }
}
