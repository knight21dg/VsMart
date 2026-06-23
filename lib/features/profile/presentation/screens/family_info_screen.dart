import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../app/theme/app_theme.dart';
import '../../../../core/extensions/context_extensions.dart';
import '../../../../core/extensions/string_extensions.dart';
import '../../../../core/widgets/widgets.dart';
import '../../../auth/presentation/providers/current_user_provider.dart';
import '../../data/family_data.dart';
import '../providers/family_providers.dart';

/// Membership state of a household member.
enum _MemberStatus { active, pending, none }

/// View model for a single household row (primary holder or invited member).
class _Member {
  const _Member({
    required this.id,
    required this.name,
    required this.relationship,
    required this.phone,
    this.status = _MemberStatus.none,
    this.isPrimary = false,
    this.showMenu = false,
    this.sharedUsage,
  });

  final String id;
  final String name;
  final String relationship;
  final String phone;
  final _MemberStatus status;
  final bool isPrimary;
  final bool showMenu;

  /// Formatted shared credit-limit usage (e.g. `₹124`), or null to hide.
  final String? sharedUsage;
}

/// Family Information screen: manage shared credit limits and shopping profiles
/// for household members, backed by `GET/POST /credit/family` and
/// `DELETE /credit/family/members/{id}`.
class FamilyInfoScreen extends ConsumerWidget {
  const FamilyInfoScreen({super.key});

  _MemberStatus _statusOf(String s) => switch (s) {
        'active' => _MemberStatus.active,
        'pending' => _MemberStatus.pending,
        _ => _MemberStatus.none,
      };

  List<_Member> _members(WidgetRef ref, FamilyGroupModel group) {
    final user = ref.read(currentUserProvider);
    return [
      _Member(
        id: 'primary',
        name: (user?.name.isNotEmpty ?? false) ? user!.name : 'You',
        relationship: 'Primary Account Holder',
        phone: user?.phone ?? '',
        status: _MemberStatus.active,
        isPrimary: true,
      ),
      for (final m in group.members)
        _Member(
          id: m.id,
          name: m.relationship.isEmpty ? 'Family Member' : m.relationship,
          relationship: m.status == 'pending'
              ? 'Invitation pending'
              : 'Household member',
          phone: m.phone,
          status: _statusOf(m.status),
          showMenu: true,
          sharedUsage:
              m.sharedUsage > 0 ? '₹${m.sharedUsage.toStringAsFixed(0)}' : null,
        ),
    ];
  }

  Future<void> _removeMember(
    BuildContext context,
    WidgetRef ref,
    _Member member,
  ) async {
    try {
      await ref.read(familyDataSourceProvider).removeMember(member.id);
      ref.invalidate(familyGroupProvider);
      if (context.mounted) context.showSnack('${member.name} removed.');
    } catch (_) {
      if (context.mounted) {
        context.showSnack('Could not remove member.', isError: true);
      }
    }
  }

  void _memberMenu(BuildContext context, WidgetRef ref, _Member member) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: context.colors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.all(AppSpacing.lg),
              child: Text(member.name, style: AppTypography.titleLarge),
            ),
            ListTile(
              leading: Icon(Icons.delete_outline_rounded,
                  color: context.vsColors.danger),
              title: Text('Remove member',
                  style: TextStyle(color: context.vsColors.danger)),
              onTap: () {
                Navigator.of(ctx).pop();
                _removeMember(context, ref, member);
              },
            ),
            const SizedBox(height: AppSpacing.sm),
          ],
        ),
      ),
    );
  }

  Future<void> _addMember(BuildContext context, WidgetRef ref) async {
    final relationController = TextEditingController();
    final phoneController = TextEditingController();
    final added = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Invite Family Member'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: phoneController,
              autofocus: true,
              keyboardType: TextInputType.phone,
              decoration: const InputDecoration(labelText: 'Phone number'),
            ),
            TextField(
              controller: relationController,
              decoration: const InputDecoration(
                  labelText: 'Relationship (e.g. Spouse)'),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx)
                .pop(phoneController.text.trim().isNotEmpty),
            child: const Text('Invite'),
          ),
        ],
      ),
    );
    if (added != true) return;
    final phone = phoneController.text.trim();
    try {
      await ref.read(familyDataSourceProvider).addMember(
            phone: phone,
            relationship: relationController.text.trim(),
          );
      ref.invalidate(familyGroupProvider);
      if (context.mounted) context.showSnack('Invite sent to $phone.');
    } catch (_) {
      if (context.mounted) {
        context.showSnack('Could not send invite.', isError: true);
      }
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final vs = context.vsColors;
    final groupAsync = ref.watch(familyGroupProvider);

    return Scaffold(
      appBar: const VSAppBar(title: 'Family Information'),
      body: SafeArea(
        child: groupAsync.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (_, __) => VSErrorView(
            message: "Couldn't load your household.",
            onRetry: () => ref.invalidate(familyGroupProvider),
          ),
          data: (group) {
            final members = _members(ref, group);
            return SingleChildScrollView(
              padding: AppSpacing.screen,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Household Members', style: AppTypography.headlineLarge),
                  AppSpacing.vGapSm,
                  Text(
                    'Manage shared credit limits and shopping profiles for '
                    'your family.',
                    style: AppTypography.bodyMedium
                        .copyWith(color: vs.textSecondary),
                  ),
                  AppSpacing.vGapLg,
                  for (final member in members) ...[
                    _MemberCard(
                      member: member,
                      onMenu: () => _memberMenu(context, ref, member),
                    ),
                    AppSpacing.vGapMd,
                  ],
                  AppSpacing.vGapSm,
                  _AddMemberCard(onAdd: () => _addMember(context, ref)),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}

/// Card describing one household member, including avatar, contact details and
/// optional status chip / overflow menu and shared-usage row.
class _MemberCard extends StatelessWidget {
  const _MemberCard({required this.member, required this.onMenu});

  final _Member member;
  final VoidCallback onMenu;

  @override
  Widget build(BuildContext context) {
    final vs = context.vsColors;
    final hasUsage = member.sharedUsage != null;

    final card = Container(
      decoration: BoxDecoration(
        color: context.colors.surface,
        borderRadius: AppRadius.brLg,
        border: Border.all(color: vs.border),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.all(AppSpacing.lg),
            child: Row(
              children: [
                _MemberAvatar(member: member),
                AppSpacing.hGapMd,
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(member.name, style: AppTypography.titleLarge),
                      Text(
                        member.relationship,
                        style: AppTypography.bodySmall
                            .copyWith(color: vs.textSecondary),
                      ),
                      if (member.phone.isNotEmpty) ...[
                        AppSpacing.vGapXs,
                        Text(
                          member.phone,
                          style: AppTypography.bodyMedium
                              .copyWith(color: vs.textSecondary),
                        ),
                      ],
                    ],
                  ),
                ),
                AppSpacing.hGapSm,
                _TrailingAffordance(member: member, onMenu: onMenu),
              ],
            ),
          ),
          if (hasUsage) ...[
            Divider(height: 1, color: vs.border),
            Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.lg,
                vertical: AppSpacing.md,
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Shared Limit Usage',
                          style: AppTypography.bodySmall
                              .copyWith(color: vs.textSecondary),
                        ),
                        Text(
                          member.sharedUsage!,
                          style: AppTypography.titleLarge,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );

    if (!member.isPrimary) return card;

    // Primary holder card carries a brand-colored leading accent bar.
    return ClipRRect(
      borderRadius: AppRadius.brLg,
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(width: AppSpacing.xs, color: vs.brand),
            Expanded(child: card),
          ],
        ),
      ),
    );
  }
}

/// Circular avatar with member initials, or a dashed add-person placeholder for
/// pending members.
class _MemberAvatar extends StatelessWidget {
  const _MemberAvatar({required this.member});

  final _Member member;

  static const double _size = 48;

  @override
  Widget build(BuildContext context) {
    final vs = context.vsColors;

    if (member.status == _MemberStatus.pending) {
      return DottedCircle(
        size: _size,
        color: vs.textSecondary,
        child: Icon(
          Icons.person_add_alt_1_outlined,
          size: 22,
          color: vs.textSecondary,
        ),
      );
    }

    final isPrimary = member.isPrimary;
    return Container(
      width: _size,
      height: _size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: isPrimary ? vs.brand : vs.brandTint,
        shape: BoxShape.circle,
      ),
      child: Text(
        member.name.initials,
        style: AppTypography.titleLarge.copyWith(
          color: isPrimary ? AppColors.white : vs.brand,
        ),
      ),
    );
  }
}

/// Trailing element of a member row: a status chip, an overflow menu, or nothing.
class _TrailingAffordance extends StatelessWidget {
  const _TrailingAffordance({required this.member, required this.onMenu});

  final _Member member;
  final VoidCallback onMenu;

  @override
  Widget build(BuildContext context) {
    final vs = context.vsColors;

    if (member.showMenu) {
      return InkResponse(
        onTap: onMenu,
        radius: AppSpacing.xl,
        child: Icon(Icons.more_vert_rounded, color: vs.textSecondary),
      );
    }

    return switch (member.status) {
      _MemberStatus.active => const VSStatusChip(
          label: 'Active',
          tone: VSStatusTone.success,
          icon: Icons.verified_user_outlined,
          dense: true,
        ),
      _MemberStatus.pending => const VSStatusChip(
          label: 'Pending',
          tone: VSStatusTone.offer,
          dense: true,
        ),
      _MemberStatus.none => const SizedBox.shrink(),
    };
  }
}

/// Dashed circular outline wrapper used for the pending-member placeholder.
class DottedCircle extends StatelessWidget {
  const DottedCircle({
    super.key,
    required this.size,
    required this.color,
    required this.child,
  });

  final double size;
  final Color color;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: _DashedCirclePainter(color: color),
      child: SizedBox(
        width: size,
        height: size,
        child: Center(child: child),
      ),
    );
  }
}

class _DashedCirclePainter extends CustomPainter {
  const _DashedCirclePainter({required this.color});

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;

    final radius = (size.shortestSide / 2) - paint.strokeWidth;
    final center = Offset(size.width / 2, size.height / 2);

    const dashCount = 28;
    const sweep = 0.62; // fraction of each segment that is drawn
    const segment = 6.283185307179586 / dashCount; // 2*pi / dashCount
    for (var i = 0; i < dashCount; i++) {
      final start = segment * i;
      canvas.drawArc(
        Rect.fromCircle(center: center, radius: radius),
        start,
        segment * sweep,
        false,
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(_DashedCirclePainter oldDelegate) =>
      oldDelegate.color != color;
}

/// Highlighted call-to-action card inviting the user to add a new member.
class _AddMemberCard extends StatelessWidget {
  const _AddMemberCard({required this.onAdd});

  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    final vs = context.vsColors;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.xl),
      decoration: BoxDecoration(
        color: vs.trustTint,
        borderRadius: AppRadius.brLg,
        border: Border.all(color: vs.trust.withValues(alpha: 0.25)),
      ),
      child: Column(
        children: [
          Container(
            width: 48,
            height: 48,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: vs.trust.withValues(alpha: 0.18),
              shape: BoxShape.circle,
            ),
            child: Icon(Icons.group_add_outlined, color: vs.trust),
          ),
          AppSpacing.vGapMd,
          Text(
            'Add a Household Member',
            style: AppTypography.titleLarge,
            textAlign: TextAlign.center,
          ),
          AppSpacing.vGapXs,
          Text(
            'Invite family to share your VS Mart credit limit and shopping '
            'lists.',
            textAlign: TextAlign.center,
            style: AppTypography.bodyMedium.copyWith(color: vs.textSecondary),
          ),
          AppSpacing.vGapLg,
          VSButton(
            label: 'Add Member',
            icon: Icons.add_rounded,
            onPressed: onAdd,
          ),
        ],
      ),
    );
  }
}
