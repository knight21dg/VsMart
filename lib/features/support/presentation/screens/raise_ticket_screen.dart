import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../app/theme/app_theme.dart';
import '../../../../core/extensions/context_extensions.dart';
import '../../../../core/utils/image_pick_helper.dart';
import '../../../../core/utils/validators.dart';
import '../../../../core/widgets/widgets.dart';
import '../../../auth/presentation/providers/current_user_provider.dart';
import '../../../orders/presentation/providers/order_providers.dart';
import '../providers/support_providers.dart';

/// Support ticket form letting a customer raise an issue with a category,
/// optional related order, priority, description, and attachments. Submits to
/// the backend `/support/tickets` and posts the description as the first message.
class RaiseTicketScreen extends ConsumerStatefulWidget {
  const RaiseTicketScreen({super.key});

  @override
  ConsumerState<RaiseTicketScreen> createState() => _RaiseTicketScreenState();
}

class _RaiseTicketScreenState extends ConsumerState<RaiseTicketScreen> {
  static const _categories = [
    'Order',
    'Payment',
    'Credit',
    'Delivery',
    'Account',
    'Other',
  ];
  static const _maxDescription = 500;

  final _formKey = GlobalKey<FormState>();
  final _description = TextEditingController();

  String? _category;
  String _relatedOrder = 'None';
  _Priority _priority = _Priority.medium;
  int _descriptionLength = 0;

  @override
  void initState() {
    super.initState();
    _description.addListener(_onDescriptionChanged);
  }

  @override
  void dispose() {
    _description
      ..removeListener(_onDescriptionChanged)
      ..dispose();
    super.dispose();
  }

  void _onDescriptionChanged() {
    final length = _description.text.characters.length;
    if (length != _descriptionLength) {
      setState(() => _descriptionLength = length);
    }
  }

  bool _submitting = false;

  Future<void> _submit() async {
    context.hideKeyboard();
    if (!_formKey.currentState!.validate() || _submitting) return;
    setState(() => _submitting = true);
    final category = _category ?? 'Other';
    final priority = switch (_priority) {
      _Priority.low => 'low',
      _Priority.high => 'high',
      _Priority.medium => 'medium',
    };
    final orderCode = _relatedOrder == 'None'
        ? null
        : _relatedOrder.replaceAll(RegExp(r'[^A-Za-z0-9-]'), '');
    try {
      final ds = ref.read(supportDataSourceProvider);
      final ticket = await ds.createTicket(
        category: category,
        subject: '$category Issue',
        priority: priority,
        orderCode: orderCode,
      );
      await ds.sendMessage(ticket.id, _description.text.trim());
      ref.invalidate(ticketsProvider);
      if (!mounted) return;
      context.showSnack('Ticket submitted');
      context.pop();
    } catch (_) {
      if (!mounted) return;
      setState(() => _submitting = false);
      context.showSnack('Could not submit ticket. Please try again.',
          isError: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    // Real orders for the "Related Order" picker (no demo codes).
    final orders = ref.watch(ordersProvider).valueOrNull ?? const [];
    final orderCodes = <String>['None', for (final o in orders) o.id];
    final relatedValue =
        orderCodes.contains(_relatedOrder) ? _relatedOrder : 'None';
    return Scaffold(
      appBar: const VSAppBar(title: 'Raise a Ticket'),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: SingleChildScrollView(
                padding: AppSpacing.screen,
                child: Form(
                  key: _formKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _SectionCard(
                        child: _DropdownField(
                          label: 'Issue Category',
                          required: true,
                          hint: 'Select an issue category',
                          value: _category,
                          items: _categories,
                          onChanged: (v) => setState(() => _category = v),
                          validator: (v) =>
                              Validators.required(v, field: 'Issue category'),
                        ),
                      ),
                      AppSpacing.vGapLg,
                      _SectionCard(
                        child: _DropdownField(
                          label: 'Related Order (Optional)',
                          hint: 'None',
                          value: relatedValue,
                          items: orderCodes,
                          onChanged: (v) =>
                              setState(() => _relatedOrder = v ?? 'None'),
                        ),
                      ),
                      AppSpacing.vGapLg,
                      _SectionCard(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('Priority Level',
                                style: AppTypography.labelLarge),
                            AppSpacing.vGapMd,
                            _PrioritySelector(
                              value: _priority,
                              onChanged: (p) => setState(() => _priority = p),
                            ),
                          ],
                        ),
                      ),
                      AppSpacing.vGapLg,
                      _SectionCard(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                const _RequiredLabel('Issue Description'),
                                const Spacer(),
                                Text(
                                  '$_descriptionLength/$_maxDescription',
                                  style: AppTypography.bodySmall.copyWith(
                                    color: context.vsColors.textSecondary,
                                  ),
                                ),
                              ],
                            ),
                            AppSpacing.vGapSm,
                            VSTextField(
                              controller: _description,
                              hint: 'Please describe your issue in detail...',
                              maxLines: 5,
                              maxLength: _maxDescription,
                              validator: (v) => Validators.required(
                                v,
                                field: 'Issue description',
                              ),
                            ),
                          ],
                        ),
                      ),
                      AppSpacing.vGapLg,
                      _SectionCard(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('Attachments (Optional)',
                                style: AppTypography.labelLarge),
                            AppSpacing.vGapMd,
                            const _AttachmentBox(),
                          ],
                        ),
                      ),
                      AppSpacing.vGapLg,
                      const _ContactInfoCard(),
                      AppSpacing.vGapLg,
                      const _ResponseTimeBanner(),
                    ],
                  ),
                ),
              ),
            ),
            _BottomBar(onSubmit: _submit),
          ],
        ),
      ),
    );
  }
}

enum _Priority { low, medium, high }

/// White rounded container that groups a labeled form section.
class _SectionCard extends StatelessWidget {
  const _SectionCard({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        color: context.colors.surface,
        borderRadius: AppRadius.brLg,
        border: Border.all(color: context.vsColors.border),
      ),
      child: child,
    );
  }
}

/// A label with a trailing red asterisk to mark required fields.
class _RequiredLabel extends StatelessWidget {
  const _RequiredLabel(this.label);

  final String label;

  @override
  Widget build(BuildContext context) {
    return Text.rich(
      TextSpan(
        text: label,
        style: AppTypography.labelLarge,
        children: [
          TextSpan(
            text: ' *',
            style: AppTypography.labelLarge.copyWith(color: AppColors.error),
          ),
        ],
      ),
    );
  }
}

/// Theme-styled dropdown that matches [VSTextField]'s look.
class _DropdownField extends StatelessWidget {
  const _DropdownField({
    required this.label,
    required this.hint,
    required this.value,
    required this.items,
    required this.onChanged,
    this.required = false,
    this.validator,
  });

  final String label;
  final String hint;
  final String? value;
  final List<String> items;
  final ValueChanged<String?> onChanged;
  final bool required;
  final String? Function(String?)? validator;

  @override
  Widget build(BuildContext context) {
    final vs = context.vsColors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (required)
          _RequiredLabel(label)
        else
          Text(label, style: AppTypography.labelLarge),
        AppSpacing.vGapSm,
        DropdownButtonFormField<String>(
          value: value,
          isExpanded: true,
          hint: Text(
            hint,
            style: AppTypography.bodyMedium.copyWith(color: vs.textSecondary),
          ),
          icon: Icon(Icons.keyboard_arrow_down_rounded, color: vs.textSecondary),
          style:
              AppTypography.bodyMedium.copyWith(color: context.colors.onSurface),
          validator: validator,
          items: [
            for (final item in items)
              DropdownMenuItem(value: item, child: Text(item)),
          ],
          onChanged: onChanged,
        ),
      ],
    );
  }
}

/// Segmented Low / Medium / High priority selector.
class _PrioritySelector extends StatelessWidget {
  const _PrioritySelector({required this.value, required this.onChanged});

  final _Priority value;
  final ValueChanged<_Priority> onChanged;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        for (final priority in _Priority.values) ...[
          if (priority != _Priority.low) AppSpacing.hGapMd,
          Expanded(
            child: _PriorityChip(
              priority: priority,
              selected: priority == value,
              onTap: () => onChanged(priority),
            ),
          ),
        ],
      ],
    );
  }
}

class _PriorityChip extends StatelessWidget {
  const _PriorityChip({
    required this.priority,
    required this.selected,
    required this.onTap,
  });

  final _Priority priority;
  final bool selected;
  final VoidCallback onTap;

  String get _label => switch (priority) {
        _Priority.low => 'Low',
        _Priority.medium => 'Medium',
        _Priority.high => 'High',
      };

  @override
  Widget build(BuildContext context) {
    final vs = context.vsColors;
    return Material(
      color: selected ? vs.trust : context.colors.surface,
      borderRadius: AppRadius.brPill,
      child: InkWell(
        onTap: onTap,
        borderRadius: AppRadius.brPill,
        child: Container(
          height: 40,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            borderRadius: AppRadius.brPill,
            border: Border.all(color: selected ? vs.trust : vs.border),
          ),
          child: Text(
            _label,
            style: AppTypography.labelMedium.copyWith(
              color: selected ? AppColors.white : context.colors.onSurface,
            ),
          ),
        ),
      ),
    );
  }
}

/// Dashed-look tappable box prompting the user to upload files. Tapping it
/// picks images from the camera/gallery and lists what was attached.
class _AttachmentBox extends StatefulWidget {
  const _AttachmentBox();

  @override
  State<_AttachmentBox> createState() => _AttachmentBoxState();
}

class _AttachmentBoxState extends State<_AttachmentBox> {
  final List<File> _files = [];

  Future<void> _add() async {
    if (_files.length >= 3) {
      context.showSnack('You can attach up to 3 files.');
      return;
    }
    final file = await pickImageFromSource(context);
    if (file != null && mounted) {
      setState(() => _files.add(File(file.path)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final vs = context.vsColors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Material(
          color: vs.trustTint,
          borderRadius: AppRadius.brMd,
          child: InkWell(
            onTap: _add,
            borderRadius: AppRadius.brMd,
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: AppSpacing.xxl),
              decoration: BoxDecoration(
                borderRadius: AppRadius.brMd,
                border: Border.all(color: vs.trust.withValues(alpha: 0.4)),
              ),
              child: Column(
                children: [
                  Icon(Icons.cloud_upload_outlined, color: vs.trust, size: 28),
                  AppSpacing.vGapSm,
                  Text(
                    'Tap to upload photos',
                    style: AppTypography.labelMedium.copyWith(color: vs.trust),
                  ),
                  AppSpacing.vGapXs,
                  Text(
                    'Max 3 files, 5MB each',
                    style: AppTypography.bodySmall
                        .copyWith(color: vs.textSecondary),
                  ),
                ],
              ),
            ),
          ),
        ),
        if (_files.isNotEmpty) ...[
          AppSpacing.vGapMd,
          Wrap(
            spacing: AppSpacing.sm,
            runSpacing: AppSpacing.sm,
            children: [
              for (var i = 0; i < _files.length; i++)
                Stack(
                  children: [
                    ClipRRect(
                      borderRadius: AppRadius.brSm,
                      child: Image.file(_files[i],
                          height: 64, width: 64, fit: BoxFit.cover),
                    ),
                    Positioned(
                      top: -6,
                      right: -6,
                      child: IconButton(
                        iconSize: 18,
                        icon: Icon(Icons.cancel, color: vs.danger),
                        onPressed: () => setState(() => _files.removeAt(i)),
                      ),
                    ),
                  ],
                ),
            ],
          ),
        ],
      ],
    );
  }
}

/// Read-only card showing the customer's registered contact details, from the
/// signed-in user profile.
class _ContactInfoCard extends ConsumerWidget {
  const _ContactInfoCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(currentUserProvider);
    final phone = (user?.phone ?? '').isNotEmpty ? user!.phone : 'Not provided';
    final email = (user?.email ?? '').isNotEmpty ? user!.email! : 'Not provided';
    return _SectionCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Contact Information', style: AppTypography.labelLarge),
          AppSpacing.vGapMd,
          _ContactRow(
            icon: Icons.smartphone_outlined,
            label: 'Registered Mobile',
            value: phone,
          ),
          AppSpacing.vGapMd,
          _ContactRow(
            icon: Icons.mail_outline_rounded,
            label: 'Registered Email',
            value: email,
          ),
        ],
      ),
    );
  }
}

class _ContactRow extends StatelessWidget {
  const _ContactRow({
    required this.icon,
    required this.label,
    required this.value,
  });

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final vs = context.vsColors;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: vs.trustTint,
        borderRadius: AppRadius.brMd,
      ),
      child: Row(
        children: [
          Icon(icon, size: 20, color: vs.textSecondary),
          AppSpacing.hGapMd,
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style:
                    AppTypography.bodySmall.copyWith(color: vs.textSecondary),
              ),
              Text(value, style: AppTypography.labelLarge),
            ],
          ),
        ],
      ),
    );
  }
}

/// Highlighted banner with the estimated support response time.
class _ResponseTimeBanner extends StatelessWidget {
  const _ResponseTimeBanner();

  @override
  Widget build(BuildContext context) {
    final vs = context.vsColors;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        color: vs.trustTint,
        borderRadius: AppRadius.brLg,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(AppSpacing.sm),
            decoration: BoxDecoration(
              color: vs.trust,
              borderRadius: AppRadius.brPill,
            ),
            child: const Icon(Icons.access_time_rounded,
                size: 20, color: AppColors.white),
          ),
          AppSpacing.hGapMd,
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Estimated Response Time',
                    style: AppTypography.labelLarge.copyWith(color: vs.trust)),
                AppSpacing.vGapXs,
                Text(
                  'Our team typically responds within 24 hours.',
                  style: AppTypography.bodyMedium
                      .copyWith(color: context.colors.onSurface),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Sticky bottom action bar with Cancel and Submit buttons.
class _BottomBar extends StatelessWidget {
  const _BottomBar({required this.onSubmit});

  final VoidCallback onSubmit;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: AppSpacing.screen,
      decoration: BoxDecoration(
        color: context.colors.surface,
        border: Border(top: BorderSide(color: context.vsColors.border)),
      ),
      child: Row(
        children: [
          Expanded(
            child: VSOutlinedButton(
              label: 'Cancel',
              onPressed: () => context.pop(),
            ),
          ),
          AppSpacing.hGapMd,
          Expanded(
            flex: 2,
            child: VSButton(label: 'Submit Ticket', onPressed: onSubmit),
          ),
        ],
      ),
    );
  }
}
