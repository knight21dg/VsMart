import 'package:flutter/material.dart';

import '../../app/theme/app_theme.dart';
import '../extensions/context_extensions.dart';
import 'vs_status_chip.dart';

/// Selectable saved-address card used in checkout and the address book.
class VSAddressCard extends StatelessWidget {
  const VSAddressCard({
    super.key,
    required this.label,
    required this.fullAddress,
    this.recipientName,
    this.phone,
    this.isDefault = false,
    this.isSelected = false,
    this.icon = Icons.home_rounded,
    this.onTap,
    this.onEdit,
    this.onDelete,
  });

  final String label;
  final String fullAddress;
  final String? recipientName;
  final String? phone;
  final bool isDefault;
  final bool isSelected;
  final IconData icon;
  final VoidCallback? onTap;
  final VoidCallback? onEdit;
  final VoidCallback? onDelete;

  @override
  Widget build(BuildContext context) {
    final vs = context.vsColors;
    return InkWell(
      onTap: onTap,
      borderRadius: AppRadius.brLg,
      child: Container(
        padding: const EdgeInsets.all(AppSpacing.lg),
        decoration: BoxDecoration(
          color: context.colors.surface,
          borderRadius: AppRadius.brLg,
          border: Border.all(
            color: isSelected ? vs.brand : vs.border,
            width: isSelected ? 1.5 : 1,
          ),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: vs.brand, size: 22),
            AppSpacing.hGapMd,
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(label, style: AppTypography.titleMedium),
                      if (isDefault) ...[
                        AppSpacing.hGapSm,
                        const VSStatusChip(
                          label: 'Default',
                          tone: VSStatusTone.brand,
                          dense: true,
                        ),
                      ],
                    ],
                  ),
                  if (recipientName != null) ...[
                    const SizedBox(height: 2),
                    Text(recipientName!,
                        style: AppTypography.bodySmall
                            .copyWith(color: vs.textSecondary)),
                  ],
                  AppSpacing.vGapXs,
                  Text(fullAddress,
                      style: AppTypography.bodySmall
                          .copyWith(color: vs.textSecondary)),
                  if (phone != null) ...[
                    AppSpacing.vGapXs,
                    Text('Phone: $phone',
                        style: AppTypography.bodySmall
                            .copyWith(color: vs.textSecondary)),
                  ],
                ],
              ),
            ),
            if (onEdit != null || onDelete != null)
              PopupMenuButton<String>(
                icon: Icon(Icons.more_vert_rounded, color: vs.textSecondary),
                onSelected: (v) {
                  if (v == 'edit') onEdit?.call();
                  if (v == 'delete') onDelete?.call();
                },
                itemBuilder: (_) => [
                  if (onEdit != null)
                    const PopupMenuItem(value: 'edit', child: Text('Edit')),
                  if (onDelete != null)
                    const PopupMenuItem(value: 'delete', child: Text('Delete')),
                ],
              ),
          ],
        ),
      ),
    );
  }
}
