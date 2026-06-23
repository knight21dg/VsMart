import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../app/routes/route_paths.dart';
import '../../../../app/theme/app_theme.dart';
import '../../../../core/extensions/context_extensions.dart';
import '../../../../core/utils/validators.dart';
import '../../../../core/widgets/widgets.dart';
import '../../../../shared/providers/core_providers.dart';
import '../../domain/entities/verification_enums.dart';
import '../providers/verification_providers.dart';
import '../widgets/verification_widgets.dart';

/// Step 3 of verification: the credit application. Captures employment, income,
/// household and the requested limit, autosaving each field to the draft.
class CreditApplicationScreen extends ConsumerStatefulWidget {
  const CreditApplicationScreen({super.key});

  @override
  ConsumerState<CreditApplicationScreen> createState() =>
      _CreditApplicationScreenState();
}

class _CreditApplicationScreenState
    extends ConsumerState<CreditApplicationScreen> {
  final _formKey = GlobalKey<FormState>();
  final _occupation = TextEditingController();
  final _income = TextEditingController();

  int _family = 1;
  HouseType? _houseType;
  Ownership? _ownership;
  num? _requestedLimit;

  static const _limits = [1000, 2000, 3000, 5000];

  @override
  void initState() {
    super.initState();
    final d = ref.read(verificationControllerProvider);
    _occupation.text = d.occupation;
    if (d.monthlyIncome != null) _income.text = '${d.monthlyIncome}';
    _family = d.familyMembers ?? 1;
    _houseType = d.houseType;
    _ownership = d.ownership;
    _requestedLimit = d.requestedLimit;
    ref.read(analyticsServiceProvider).creditApplicationStarted();
  }

  @override
  void dispose() {
    _occupation.dispose();
    _income.dispose();
    super.dispose();
  }

  VerificationController get _ctrl =>
      ref.read(verificationControllerProvider.notifier);

  void _saveText() => _ctrl.patchCredit(
        occupation: _occupation.text.trim(),
        monthlyIncome: num.tryParse(_income.text.trim()),
      );

  void _continue() {
    context.hideKeyboard();
    if (!_formKey.currentState!.validate()) return;
    if (_houseType == null || _ownership == null || _requestedLimit == null) {
      context.showSnack('Please complete all selections', isError: true);
      return;
    }
    _ctrl.patchCredit(
      occupation: _occupation.text.trim(),
      monthlyIncome: num.tryParse(_income.text.trim()),
      familyMembers: _family,
      houseType: _houseType,
      ownership: _ownership,
      requestedLimit: _requestedLimit,
    );
    ref.read(analyticsServiceProvider).creditApplicationCompleted();
    context.pushNamed(RouteNames.verificationReview);
  }

  @override
  Widget build(BuildContext context) {
    final vs = context.vsColors;
    return Scaffold(
      appBar: const VSAppBar(title: 'Credit Application'),
      body: Column(
        children: [
          const VSVerificationProgress(step: 3, total: 4),
          Expanded(
            child: Form(
              key: _formKey,
              child: ListView(
                padding: AppSpacing.screen,
                children: [
                  Text('Financial Information',
                      style: AppTypography.headlineMedium),
                  AppSpacing.vGapXs,
                  Text('Help us determine your credit eligibility.',
                      style: AppTypography.bodyMedium
                          .copyWith(color: vs.textSecondary)),
                  AppSpacing.vGapLg,
                  const _EligibilityCard(),
                  AppSpacing.vGapLg,
                  _Card(
                    title: 'Employment Details',
                    icon: Icons.work_outline_rounded,
                    children: [
                      VSTextField(
                        controller: _occupation,
                        label: 'Occupation',
                        hint: 'e.g. Software Engineer, Teacher',
                        validator: (v) =>
                            Validators.required(v, field: 'Occupation'),
                        onChanged: (_) => _saveText(),
                      ),
                    ],
                  ),
                  AppSpacing.vGapLg,
                  _Card(
                    title: 'Income Information',
                    icon: Icons.payments_outlined,
                    children: [
                      VSTextField(
                        controller: _income,
                        label: 'Monthly Income (₹)',
                        hint: '0',
                        keyboardType: TextInputType.number,
                        inputFormatters: [
                          FilteringTextInputFormatter.digitsOnly
                        ],
                        validator: Validators.income,
                        onChanged: (_) => _saveText(),
                      ),
                    ],
                  ),
                  AppSpacing.vGapLg,
                  _Card(
                    title: 'Household',
                    icon: Icons.home_outlined,
                    children: [
                      Text('Family Members', style: AppTypography.labelMedium),
                      AppSpacing.vGapSm,
                      _FamilyStepper(
                        value: _family,
                        onChanged: (v) {
                          setState(() => _family = v);
                          _ctrl.patchCredit(familyMembers: v);
                        },
                      ),
                      AppSpacing.vGapLg,
                      Text('House Type', style: AppTypography.labelMedium),
                      AppSpacing.vGapSm,
                      _ChoiceChips<HouseType>(
                        values: HouseType.values,
                        selected: _houseType,
                        labelOf: _houseLabel,
                        onSelect: (v) {
                          setState(() => _houseType = v);
                          _ctrl.patchCredit(houseType: v);
                        },
                      ),
                      AppSpacing.vGapLg,
                      Text('Ownership', style: AppTypography.labelMedium),
                      AppSpacing.vGapSm,
                      _ChoiceChips<Ownership>(
                        values: Ownership.values,
                        selected: _ownership,
                        labelOf: _ownershipLabel,
                        onSelect: (v) {
                          setState(() => _ownership = v);
                          _ctrl.patchCredit(ownership: v);
                        },
                      ),
                    ],
                  ),
                  AppSpacing.vGapLg,
                  Text('Requested Credit Limit',
                      style: AppTypography.titleLarge),
                  AppSpacing.vGapMd,
                  Row(
                    children: [
                      for (var i = 0; i < _limits.length; i++) ...[
                        Expanded(
                          child: VSCreditOptionCard(
                            amount: _limits[i],
                            selected: _requestedLimit == _limits[i],
                            onTap: () {
                              setState(() => _requestedLimit = _limits[i]);
                              _ctrl.patchCredit(requestedLimit: _limits[i]);
                            },
                          ),
                        ),
                        if (i < _limits.length - 1) AppSpacing.hGapSm,
                      ],
                    ],
                  ),
                ],
              ),
            ),
          ),
          Container(
            decoration: BoxDecoration(
              color: context.colors.surface,
              border: Border(top: BorderSide(color: vs.border)),
            ),
            child: SafeArea(
              minimum: AppSpacing.screen,
              child: Row(
                children: [
                  Expanded(
                    child: VSOutlinedButton(
                      label: 'Save Draft',
                      icon: Icons.save_outlined,
                      onPressed: () {
                        _saveText();
                        context.showSnack('Draft saved');
                      },
                    ),
                  ),
                  AppSpacing.hGapMd,
                  Expanded(
                    flex: 2,
                    child: VSButton(
                      label: 'Continue',
                      trailingIcon: Icons.arrow_forward_rounded,
                      onPressed: _continue,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _houseLabel(HouseType t) => switch (t) {
        HouseType.independent => 'Independent',
        HouseType.apartment => 'Apartment',
        HouseType.shared => 'Shared',
      };

  String _ownershipLabel(Ownership o) => switch (o) {
        Ownership.owned => 'Owned',
        Ownership.rented => 'Rented',
        Ownership.family => 'Family',
      };
}

class _EligibilityCard extends StatelessWidget {
  const _EligibilityCard();

  @override
  Widget build(BuildContext context) {
    final faint = AppColors.white.withValues(alpha: 0.85);
    return Container(
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: const BoxDecoration(
        gradient: AppColors.creditGradient,
        borderRadius: AppRadius.brXl,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.verified_rounded,
                  color: AppColors.white, size: 18),
              AppSpacing.hGapSm,
              Text('Potential Credit Limit',
                  style: AppTypography.labelMedium.copyWith(color: faint)),
            ],
          ),
          AppSpacing.vGapSm,
          Text('₹3,000 – ₹10,000',
              style:
                  AppTypography.displayMedium.copyWith(color: AppColors.white)),
          Text('Based on initial profile assessment.',
              style: AppTypography.bodySmall.copyWith(color: faint)),
        ],
      ),
    );
  }
}

class _Card extends StatelessWidget {
  const _Card({required this.title, required this.icon, required this.children});

  final String title;
  final IconData icon;
  final List<Widget> children;

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
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                height: 32,
                width: 32,
                decoration:
                    BoxDecoration(color: vs.brandTint, shape: BoxShape.circle),
                child: Icon(icon, size: 18, color: vs.brand),
              ),
              AppSpacing.hGapSm,
              Text(title, style: AppTypography.titleMedium),
            ],
          ),
          const Divider(height: AppSpacing.lg),
          ...children,
        ],
      ),
    );
  }
}

class _FamilyStepper extends StatelessWidget {
  const _FamilyStepper({required this.value, required this.onChanged});

  final int value;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    final vs = context.vsColors;
    return Container(
      decoration: BoxDecoration(
        borderRadius: AppRadius.brMd,
        border: Border.all(color: vs.border),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            icon: const Icon(Icons.remove_rounded),
            onPressed: value > 1 ? () => onChanged(value - 1) : null,
          ),
          Text('$value', style: AppTypography.titleMedium),
          IconButton(
            icon: Icon(Icons.add_rounded, color: vs.brand),
            onPressed: value < 20 ? () => onChanged(value + 1) : null,
          ),
        ],
      ),
    );
  }
}

class _ChoiceChips<T> extends StatelessWidget {
  const _ChoiceChips({
    required this.values,
    required this.selected,
    required this.labelOf,
    required this.onSelect,
  });

  final List<T> values;
  final T? selected;
  final String Function(T) labelOf;
  final ValueChanged<T> onSelect;

  @override
  Widget build(BuildContext context) {
    final vs = context.vsColors;
    return Wrap(
      spacing: AppSpacing.sm,
      runSpacing: AppSpacing.sm,
      children: [
        for (final v in values)
          InkWell(
            onTap: () => onSelect(v),
            borderRadius: AppRadius.brMd,
            child: Container(
              padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.lg, vertical: AppSpacing.sm),
              decoration: BoxDecoration(
                color: selected == v ? vs.brandTint : context.colors.surface,
                borderRadius: AppRadius.brMd,
                border:
                    Border.all(color: selected == v ? vs.brand : vs.border),
              ),
              child: Text(
                labelOf(v),
                style: AppTypography.labelMedium.copyWith(
                  color: selected == v ? vs.brand : null,
                  fontWeight: selected == v ? FontWeight.w700 : FontWeight.w500,
                ),
              ),
            ),
          ),
      ],
    );
  }
}
