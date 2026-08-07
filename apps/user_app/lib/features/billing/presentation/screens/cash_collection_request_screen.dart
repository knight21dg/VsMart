import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../app/theme/app_theme.dart';
import '../../../../core/errors/app_error_presenter.dart';
import '../../../../core/extensions/context_extensions.dart';
import '../../../../core/widgets/widgets.dart';
import '../../../address/presentation/providers/address_providers.dart';
import '../../../credit/presentation/providers/credit_providers.dart';
import '../providers/billing_providers.dart';

/// Cash Collection Request — lets the customer request an at-home cash pickup
/// for their outstanding credit balance. The customer enters the amount (and an
/// optional note); a VS Mart collection agent is then assigned by the back
/// office and visits their registered address.
///
/// The backend only persists the requested amount, so the form intentionally
/// does NOT collect a date/time slot — surfacing a schedule the server can't
/// honour would be misleading.
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

  bool _prefilled = false;
  bool _submitting = false;

  /// Stable idempotency key for this pickup request. Generated once on the first
  /// submit and reused across retries so a timed-out request that actually
  /// reached the server can't create a duplicate pickup. Reset after success.
  String? _idempotencyKey;

  @override
  void dispose() {
    _amountController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_submitting) return;
    if (!(_formKey.currentState?.validate() ?? false)) return;
    context.hideKeyboard();

    final amount = num.tryParse(_amountController.text.trim()) ?? 0;
    // Reuse the same key across retries of this submit; only mint a new one for
    // a fresh request.
    _idempotencyKey ??= 'collect_${DateTime.now().microsecondsSinceEpoch}';
    setState(() => _submitting = true);

    // Real server call — creates the pickup on the backend (idempotent).
    final result =
        await ref.read(billingRepositoryProvider).requestCollection(
              amount: amount,
              idempotencyKey: _idempotencyKey,
            );
    if (!mounted) return;
    setState(() => _submitting = false);

    result.fold(
      (failure) => presentFailure(context, ref, failure, onRetry: _submit),
      (_) {
        // Refresh the collections list so the new request shows up.
        _idempotencyKey = null;
        ref.invalidate(collectionsProvider);
        context.showSnack(
          context.l10n.billingCollectionRequestRaised,
        );
        context.pop();
      },
    );
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
      appBar: VSAppBar(title: context.l10n.billingRequestCollection),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: AppSpacing.screen,
          children: [
            _AmountCard(controller: _amountController),
            AppSpacing.vGapXl,
            _SectionHeader(context.l10n.billingCollectionAddress),
            AppSpacing.vGapMd,
            _AddressCard(
              name: address?.name ?? context.l10n.billingRegisteredAddress,
              line: address?.formatted ??
                  context.l10n.billingAgentVisitAddress,
            ),
            AppSpacing.vGapXl,
            VSTextField(
              controller: _notesController,
              label: context.l10n.billingNotes,
              hint: context.l10n.billingCollectionNotesHint,
              maxLines: 3,
              textInputAction: TextInputAction.newline,
            ),
            AppSpacing.vGapLg,
            _InfoBanner(
              color: vs.trust,
              tint: vs.trustTint,
              icon: Icons.shield_outlined,
              message: context.l10n.billingCollectionAgentInfo,
            ),
          ],
        ),
      ),
      bottomNavigationBar:
          _SubmitBar(onPressed: _submit, isLoading: _submitting),
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
            context.l10n.billingAmountToCollect,
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
                return context.l10n.billingEnterValidAmount;
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

/// Read-only pickup address card. The agent visits the customer's registered
/// delivery address, so this is informational only (no editing here).
class _AddressCard extends StatelessWidget {
  const _AddressCard({required this.name, required this.line});

  final String name;
  final String line;

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
  const _SubmitBar({required this.onPressed, required this.isLoading});

  final VoidCallback onPressed;
  final bool isLoading;

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
        child: VSButton(
          label: context.l10n.billingRequestCollection,
          isLoading: isLoading,
          onPressed: onPressed,
        ),
      ),
    );
  }
}
