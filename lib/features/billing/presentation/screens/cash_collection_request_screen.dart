import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../../app/theme/app_theme.dart';
import '../../../../core/extensions/context_extensions.dart';
import '../../../../core/widgets/widgets.dart';
import '../../../address/presentation/providers/address_providers.dart';
import '../../../credit/presentation/providers/credit_providers.dart';

/// A preferred collection time slot shown in the request form.
enum _TimeSlot {
  morning('Morning', '9 AM - 12 PM', Icons.wb_sunny_outlined),
  afternoon('Afternoon', '12 PM - 4 PM', Icons.wb_cloudy_outlined),
  evening('Evening', '4 PM - 8 PM', Icons.nightlight_outlined);

  const _TimeSlot(this.label, this.window, this.icon);

  final String label;
  final String window;
  final IconData icon;
}

/// Cash Collection Request (Phase 4I) — lets the customer schedule a cash
/// pickup: amount, pickup address, a preferred date and time slot, and optional
/// notes. Submitting confirms and returns to the collections list. The agent is
/// assigned automatically by the back office, mirrored from the Agent App.
class CashCollectionRequestScreen extends ConsumerStatefulWidget {
  const CashCollectionRequestScreen({super.key});

  @override
  ConsumerState<CashCollectionRequestScreen> createState() =>
      _CashCollectionRequestScreenState();
}

class _CashCollectionRequestScreenState
    extends ConsumerState<CashCollectionRequestScreen> {
  final _formKey = GlobalKey<FormState>();
  final _amountController = TextEditingController();
  final _notesController = TextEditingController();

  /// Five selectable dates starting today.
  late final List<DateTime> _dates = List.generate(5, (i) {
    final now = DateTime.now();
    return DateTime(now.year, now.month, now.day).add(Duration(days: i));
  });

  int _selectedDateIndex = 0;
  _TimeSlot _selectedSlot = _TimeSlot.morning;
  bool _prefilled = false;

  @override
  void dispose() {
    _amountController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  void _submit() {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    context.hideKeyboard();
    context.showSnack('Collection request submitted');
    context.pop();
  }

  @override
  Widget build(BuildContext context) {
    final vs = context.vsColors;

    // Optional prefill from the customer's outstanding credit balance.
    final outstanding =
        ref.watch(creditAccountProvider).valueOrNull?.outstanding;
    if (!_prefilled && outstanding != null && outstanding > 0) {
      _amountController.text = outstanding.toStringAsFixed(0);
      _prefilled = true;
    }

    final address = ref.watch(defaultAddressProvider);

    return Scaffold(
      appBar: const VSAppBar(title: 'Request Collection'),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: AppSpacing.screen,
          children: [
            _AmountCard(controller: _amountController),
            AppSpacing.vGapXl,
            const _SectionHeader('Collection Address'),
            AppSpacing.vGapMd,
            _AddressCard(
              name: address?.name ?? 'Home Address',
              line: address?.formatted ?? 'No saved address',
              onChange: () => context.showSnack('Change address'),
            ),
            AppSpacing.vGapXl,
            const _SectionHeader('Preferred Collection Date'),
            AppSpacing.vGapMd,
            _DateSelector(
              dates: _dates,
              selectedIndex: _selectedDateIndex,
              onSelect: (i) => setState(() => _selectedDateIndex = i),
            ),
            AppSpacing.vGapXl,
            const _SectionHeader('Preferred Time'),
            AppSpacing.vGapMd,
            for (final slot in _TimeSlot.values) ...[
              _TimeSlotTile(
                slot: slot,
                selected: _selectedSlot == slot,
                onSelect: () => setState(() => _selectedSlot = slot),
              ),
              if (slot != _TimeSlot.values.last) AppSpacing.vGapMd,
            ],
            AppSpacing.vGapXl,
            const _SectionHeader('Agent Information'),
            AppSpacing.vGapMd,
            const _AgentCard(),
            AppSpacing.vGapMd,
            VSTextField(
              controller: _notesController,
              label: 'Notes (optional)',
              hint: 'Any instructions for the collection agent',
              maxLines: 3,
              textInputAction: TextInputAction.newline,
            ),
            AppSpacing.vGapLg,
            _InfoBanner(
              color: vs.trust,
              tint: vs.trustTint,
              icon: Icons.shield_outlined,
              message:
                  'A VS Mart collection agent will visit your location and '
                  'collect payment securely.',
            ),
          ],
        ),
      ),
      bottomNavigationBar: _SubmitBar(onPressed: _submit),
    );
  }
}

/// Centered outstanding-amount card with an inline editable amount field.
class _AmountCard extends StatelessWidget {
  const _AmountCard({required this.controller});

  final TextEditingController controller;

  @override
  Widget build(BuildContext context) {
    final vs = context.vsColors;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.lg,
        vertical: AppSpacing.xl,
      ),
      decoration: BoxDecoration(
        color: context.colors.surface,
        borderRadius: AppRadius.brLg,
        border: Border.all(color: vs.border),
      ),
      child: Column(
        children: [
          Text(
            'Outstanding Amount',
            style: AppTypography.bodyMedium.copyWith(color: vs.textSecondary),
          ),
          AppSpacing.vGapMd,
          TextFormField(
            controller: controller,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            textAlign: TextAlign.center,
            inputFormatters: [
              FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
            ],
            style: AppTypography.displayMedium.copyWith(color: vs.brand),
            decoration: InputDecoration(
              filled: false,
              isDense: true,
              border: InputBorder.none,
              enabledBorder: InputBorder.none,
              focusedBorder: InputBorder.none,
              errorBorder: InputBorder.none,
              focusedErrorBorder: InputBorder.none,
              contentPadding: EdgeInsets.zero,
              prefixText: '₹ ',
              prefixStyle: AppTypography.displayMedium.copyWith(color: vs.brand),
              hintText: '0',
            ),
            validator: (v) {
              final amount = num.tryParse((v ?? '').trim());
              if (amount == null || amount <= 0) {
                return 'Enter a valid amount';
              }
              return null;
            },
          ),
        ],
      ),
    );
  }
}

/// Section title used between form blocks.
class _SectionHeader extends StatelessWidget {
  const _SectionHeader(this.title);

  final String title;

  @override
  Widget build(BuildContext context) {
    return Text(title, style: AppTypography.titleLarge);
  }
}

/// Pickup address card with a "Change" affordance.
class _AddressCard extends StatelessWidget {
  const _AddressCard({
    required this.name,
    required this.line,
    required this.onChange,
  });

  final String name;
  final String line;
  final VoidCallback onChange;

  @override
  Widget build(BuildContext context) {
    final vs = context.vsColors;
    return Container(
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        color: context.colors.surface,
        borderRadius: AppRadius.brLg,
        border: Border.all(color: vs.border),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.location_on_outlined, color: vs.brand, size: 22),
          AppSpacing.hGapMd,
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(name, style: AppTypography.titleMedium),
                AppSpacing.vGapXs,
                Text(
                  line,
                  style: AppTypography.bodyMedium
                      .copyWith(color: vs.textSecondary),
                ),
              ],
            ),
          ),
          AppSpacing.hGapMd,
          GestureDetector(
            onTap: onChange,
            child: Text(
              'Change',
              style: AppTypography.labelMedium.copyWith(
                color: vs.trust,
                decoration: TextDecoration.underline,
                decorationColor: vs.trust,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Horizontally scrollable row of selectable date chips.
class _DateSelector extends StatelessWidget {
  const _DateSelector({
    required this.dates,
    required this.selectedIndex,
    required this.onSelect,
  });

  final List<DateTime> dates;
  final int selectedIndex;
  final ValueChanged<int> onSelect;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 76,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: dates.length,
        separatorBuilder: (_, __) => AppSpacing.hGapMd,
        itemBuilder: (_, i) => _DateChip(
          date: dates[i],
          selected: i == selectedIndex,
          onTap: () => onSelect(i),
        ),
      ),
    );
  }
}

class _DateChip extends StatelessWidget {
  const _DateChip({
    required this.date,
    required this.selected,
    required this.onTap,
  });

  final DateTime date;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final vs = context.vsColors;
    final month = DateFormat('MMM').format(date);
    final day = DateFormat('d').format(date);
    return InkWell(
      onTap: onTap,
      borderRadius: AppRadius.brMd,
      child: Container(
        width: 72,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: selected ? vs.trust : context.colors.surface,
          borderRadius: AppRadius.brMd,
          border: Border.all(color: selected ? vs.trust : vs.border),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              month,
              style: AppTypography.bodySmall.copyWith(
                color: selected ? AppColors.white : vs.textSecondary,
              ),
            ),
            AppSpacing.vGapXs,
            Text(
              day,
              style: AppTypography.headlineSmall.copyWith(
                color: selected ? AppColors.white : null,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// A selectable time-slot row with a leading icon and trailing radio.
class _TimeSlotTile extends StatelessWidget {
  const _TimeSlotTile({
    required this.slot,
    required this.selected,
    required this.onSelect,
  });

  final _TimeSlot slot;
  final bool selected;
  final VoidCallback onSelect;

  @override
  Widget build(BuildContext context) {
    final vs = context.vsColors;
    return InkWell(
      onTap: onSelect,
      borderRadius: AppRadius.brLg,
      child: Container(
        padding: const EdgeInsets.all(AppSpacing.lg),
        decoration: BoxDecoration(
          color: context.colors.surface,
          borderRadius: AppRadius.brLg,
          border: Border.all(color: selected ? vs.brand : vs.border),
        ),
        child: Row(
          children: [
            Icon(slot.icon, size: 22, color: vs.textSecondary),
            AppSpacing.hGapMd,
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(slot.label, style: AppTypography.titleMedium),
                  Text(
                    slot.window,
                    style: AppTypography.bodySmall
                        .copyWith(color: vs.textSecondary),
                  ),
                ],
              ),
            ),
            Icon(
              selected
                  ? Icons.radio_button_checked
                  : Icons.radio_button_unchecked,
              color: selected ? vs.brand : vs.textSecondary,
              size: 22,
            ),
          ],
        ),
      ),
    );
  }
}

/// Static card explaining the agent is assigned automatically.
class _AgentCard extends StatelessWidget {
  const _AgentCard();

  @override
  Widget build(BuildContext context) {
    final vs = context.vsColors;
    return Container(
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        color: context.colors.surface,
        borderRadius: AppRadius.brLg,
        border: Border.all(color: vs.border),
      ),
      child: Row(
        children: [
          Container(
            height: 44,
            width: 44,
            decoration:
                BoxDecoration(color: vs.trustTint, shape: BoxShape.circle),
            child: Icon(Icons.support_agent_rounded, color: vs.trust, size: 22),
          ),
          AppSpacing.hGapMd,
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Assigned Automatically',
                    style: AppTypography.titleMedium),
                AppSpacing.vGapXs,
                Text(
                  'Agent details will be shared once confirmed',
                  style: AppTypography.bodySmall
                      .copyWith(color: vs.textSecondary),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Tinted informational banner shown above the submit bar.
class _InfoBanner extends StatelessWidget {
  const _InfoBanner({
    required this.color,
    required this.tint,
    required this.icon,
    required this.message,
  });

  final Color color;
  final Color tint;
  final IconData icon;
  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        color: tint,
        borderRadius: AppRadius.brLg,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 20, color: color),
          AppSpacing.hGapMd,
          Expanded(
            child: Text(
              message,
              style: AppTypography.bodyMedium
                  .copyWith(color: context.vsColors.textSecondary),
            ),
          ),
        ],
      ),
    );
  }
}

/// Sticky bottom bar with the primary submit CTA.
class _SubmitBar extends StatelessWidget {
  const _SubmitBar({required this.onPressed});

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final vs = context.vsColors;
    return Container(
      padding: AppSpacing.screen,
      decoration: BoxDecoration(
        color: context.colors.surface,
        border: Border(top: BorderSide(color: vs.border)),
      ),
      child: SafeArea(
        top: false,
        child: VSButton(label: 'Request Collection', onPressed: onPressed),
      ),
    );
  }
}
