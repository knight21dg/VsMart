import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../app/theme/app_theme.dart';
import '../../../../core/extensions/context_extensions.dart';
import '../../../../core/extensions/string_extensions.dart';
import '../../../../core/utils/image_pick_helper.dart';
import '../../../../core/utils/validators.dart';
import '../../../../core/widgets/widgets.dart';
import '../../../../shared/providers/core_providers.dart';
import '../../../auth/domain/entities/user.dart';
import '../../../auth/presentation/providers/current_user_provider.dart';
import '../providers/profile_providers.dart';

/// Edit Profile — matches the design: avatar with edit badge, full name, a
/// locked verified phone, email, gender and date of birth, with a sticky
/// "Save Changes" CTA. Name + email persist via [editProfileControllerProvider];
/// gender/DOB are collected (no API field yet) per the registration pattern.
class ProfileScreen extends ConsumerStatefulWidget {
  const ProfileScreen({super.key});

  @override
  ConsumerState<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends ConsumerState<ProfileScreen> {
  final _formKey = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _email = TextEditingController();
  final _dob = TextEditingController();

  String _initialName = '';
  String _initialEmail = '';
  String _gender = 'Female';

  @override
  void initState() {
    super.initState();
    final user = ref.read(currentUserProvider);
    _initialName = user?.name ?? '';
    _initialEmail = user?.email ?? '';
    _name.text = _initialName;
    _email.text = _initialEmail;
    _name.addListener(_onChanged);
    _email.addListener(_onChanged);
  }

  @override
  void dispose() {
    _name.dispose();
    _email.dispose();
    _dob.dispose();
    super.dispose();
  }

  void _onChanged() => setState(() {});

  bool get _dirty =>
      _name.text.trim() != _initialName.trim() ||
      _email.text.trim() != _initialEmail.trim() ||
      _dob.text.isNotEmpty;

  Future<void> _pickDob() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: DateTime(now.year - 25),
      firstDate: DateTime(now.year - 100),
      lastDate: now,
    );
    if (picked != null) {
      _dob.text =
          '${picked.month.toString().padLeft(2, '0')}/${picked.day.toString().padLeft(2, '0')}/${picked.year}';
      setState(() {});
    }
  }

  Future<void> _save() async {
    context.hideKeyboard();
    if (!_formKey.currentState!.validate()) return;
    final email = _email.text.trim();
    final error = await ref.read(editProfileControllerProvider.notifier).save(
          name: _name.text.trim(),
          email: email.isEmpty ? null : email,
        );
    if (!mounted) return;
    if (error == null) {
      ref.read(analyticsServiceProvider).track('profile_updated');
      setState(() {
        _initialName = _name.text.trim();
        _initialEmail = _email.text.trim();
      });
      context.showSnack('Profile updated');
      context.pop();
    } else {
      context.showSnack(error, isError: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final vs = context.vsColors;
    final user = ref.watch(currentUserProvider);
    final isSaving = ref.watch(editProfileControllerProvider);

    if (user == null) {
      return const Scaffold(
        appBar: VSAppBar(title: 'Edit Profile'),
        body: VSEmptyState(
          title: 'Not signed in',
          message: 'Sign in to view and edit your profile.',
          icon: Icons.person_off_outlined,
        ),
      );
    }

    return Scaffold(
      appBar: VSAppBar(
        titleWidget: Text('Edit Profile',
            style: AppTypography.headlineSmall.copyWith(color: vs.brand)),
      ),
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
                      AppSpacing.vGapMd,
                      Center(child: _ProfileAvatar(user: user)),
                      AppSpacing.vGapXl,
                      VSTextField(
                        controller: _name,
                        label: 'Full Name',
                        hint: 'e.g. Jane Doe',
                        textInputAction: TextInputAction.next,
                        validator: Validators.name,
                      ),
                      AppSpacing.vGapLg,
                      _PhoneField(phone: user.phone),
                      AppSpacing.vGapLg,
                      VSTextField(
                        controller: _email,
                        label: 'Email Address',
                        hint: 'you@example.com',
                        keyboardType: TextInputType.emailAddress,
                        validator: (v) => v == null || v.trim().isEmpty
                            ? null
                            : Validators.email(v),
                      ),
                      AppSpacing.vGapLg,
                      Text('Gender', style: AppTypography.labelMedium),
                      AppSpacing.vGapSm,
                      _GenderRow(
                        value: _gender,
                        onChanged: (g) => setState(() => _gender = g),
                      ),
                      AppSpacing.vGapLg,
                      VSTextField(
                        controller: _dob,
                        label: 'Date of Birth',
                        hint: 'mm/dd/yyyy',
                        readOnly: true,
                        onTap: _pickDob,
                        suffixIcon: Icons.calendar_today_rounded,
                        onSuffixTap: _pickDob,
                      ),
                    ],
                  ),
                ),
              ),
            ),
            Container(
              padding: AppSpacing.screen,
              decoration: BoxDecoration(
                color: context.colors.surface,
                border: Border(top: BorderSide(color: vs.border)),
              ),
              child: VSButton(
                label: 'Save Changes',
                isLoading: isSaving,
                onPressed: _dirty ? _save : null,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ProfileAvatar extends StatefulWidget {
  const _ProfileAvatar({required this.user});

  final User user;

  @override
  State<_ProfileAvatar> createState() => _ProfileAvatarState();
}

class _ProfileAvatarState extends State<_ProfileAvatar> {
  File? _picked;

  Future<void> _changePhoto() async {
    final file = await pickImageFromSource(context);
    if (file == null || !mounted) return;
    setState(() => _picked = File(file.path));
    context.showSnack('Profile photo updated.');
  }

  @override
  Widget build(BuildContext context) {
    final vs = context.vsColors;
    final user = widget.user;
    final name = user.name.isNotBlank ? user.name : 'Guest';
    final hasPhoto = (user.avatarUrl ?? '').isNotEmpty;
    return Stack(
      children: [
        if (_picked != null)
          ClipRRect(
            borderRadius: AppRadius.brPill,
            child: Image.file(
              _picked!,
              width: 104,
              height: 104,
              fit: BoxFit.cover,
            ),
          )
        else if (hasPhoto)
          VSNetworkImage(
            url: user.avatarUrl,
            width: 104,
            height: 104,
            borderRadius: AppRadius.brPill,
            fallbackIcon: Icons.person_rounded,
          )
        else
          Container(
            width: 104,
            height: 104,
            alignment: Alignment.center,
            decoration: const BoxDecoration(
              gradient: AppColors.greenGradient,
              shape: BoxShape.circle,
            ),
            child: Text(
              name.initials.isEmpty ? '?' : name.initials,
              style:
                  AppTypography.displayMedium.copyWith(color: AppColors.white),
            ),
          ),
        Positioned(
          right: 0,
          bottom: 0,
          child: GestureDetector(
            onTap: _changePhoto,
            child: Container(
              padding: const EdgeInsets.all(AppSpacing.sm),
              decoration: BoxDecoration(
                color: vs.brand,
                shape: BoxShape.circle,
                border: Border.all(color: context.colors.surface, width: 2),
              ),
              child: const Icon(Icons.edit_rounded,
                  size: 16, color: AppColors.white),
            ),
          ),
        ),
      ],
    );
  }
}

/// Locked, verified phone field matching the design (greyed value + helper).
class _PhoneField extends StatelessWidget {
  const _PhoneField({required this.phone});

  final String phone;

  @override
  Widget build(BuildContext context) {
    final vs = context.vsColors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text('Phone Number', style: AppTypography.labelMedium),
            const Spacer(),
            Row(
              children: [
                Icon(Icons.verified_rounded, size: 14, color: vs.success),
                const SizedBox(width: 4),
                Text('Verified',
                    style:
                        AppTypography.labelMedium.copyWith(color: vs.success)),
              ],
            ),
          ],
        ),
        AppSpacing.vGapSm,
        Container(
          height: 52,
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
          alignment: Alignment.centerLeft,
          decoration: BoxDecoration(
            color: vs.brandTint.withValues(alpha: 0.3),
            borderRadius: AppRadius.brMd,
            border: Border.all(color: vs.border),
          ),
          child: Text(phone,
              style:
                  AppTypography.bodyMedium.copyWith(color: vs.textSecondary)),
        ),
        AppSpacing.vGapXs,
        Text('To change your verified number, contact support.',
            style: AppTypography.bodySmall.copyWith(color: vs.textSecondary)),
      ],
    );
  }
}

class _GenderRow extends StatelessWidget {
  const _GenderRow({required this.value, required this.onChanged});

  final String value;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        for (final g in const ['Female', 'Male', 'Other'])
          Expanded(
            child: InkWell(
              onTap: () => onChanged(g),
              borderRadius: AppRadius.brSm,
              child: Row(
                children: [
                  Radio<String>(
                    value: g,
                    groupValue: value,
                    onChanged: (v) => onChanged(v!),
                    activeColor: AppColors.trustBlue,
                    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    visualDensity: VisualDensity.compact,
                  ),
                  Flexible(
                    child: Text(g,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppTypography.bodyMedium),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}
