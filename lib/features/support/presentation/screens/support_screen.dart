import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../../app/routes/route_paths.dart';
import '../../../../app/theme/app_theme.dart';
import '../../../../core/extensions/context_extensions.dart';
import '../../../../core/widgets/widgets.dart';

/// Help & Support Center — matches the design: a help heading, a search bar,
/// and a 2-column grid of Quick Help Topics.
class SupportScreen extends StatelessWidget {
  const SupportScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final vs = context.vsColors;
    final topics = <_Topic>[
      _Topic(Icons.shopping_bag_rounded, 'Order Issues', 'Missing items, tracking',
          vs.brand, RouteNames.orders),
      _Topic(Icons.credit_card_rounded, 'Payment Issues', 'Failed tx, refunds',
          vs.trust, RouteNames.paymentHistory),
      _Topic(Icons.account_balance_wallet_rounded, 'Credit Issues',
          'Limit, statements', vs.trust, RouteNames.creditDashboard),
      _Topic(Icons.local_shipping_rounded, 'Delivery Issues',
          'Delays, instructions', vs.brand, RouteNames.orders),
      _Topic(Icons.person_rounded, 'Account Issues', 'Login, profile info',
          vs.textSecondary, RouteNames.profile),
      _Topic(Icons.verified_user_rounded, 'KYC Verification', 'Docs, status',
          vs.brand, null),
    ];

    return Scaffold(
      appBar: AppBar(
        centerTitle: true,
        title: Text('Help & Support', style: AppTypography.headlineSmall),
        actions: [
          IconButton(
            icon: const Icon(Icons.receipt_long_outlined),
            tooltip: 'My Tickets',
            onPressed: () => context.pushNamed(RouteNames.tickets),
          ),
        ],
      ),
      body: SafeArea(
        top: false,
        child: ListView(
          padding: AppSpacing.screen,
          children: [
            AppSpacing.vGapSm,
            Text('How can we help you today?',
                style: AppTypography.headlineMedium),
            AppSpacing.vGapLg,
            _HelpSearch(
              onTap: () => context.pushNamed(RouteNames.faq),
            ),
            AppSpacing.vGapXl,
            Text('Quick Help Topics', style: AppTypography.headlineSmall),
            AppSpacing.vGapMd,
            GridView.count(
              crossAxisCount: 2,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              mainAxisSpacing: AppSpacing.md,
              crossAxisSpacing: AppSpacing.md,
              childAspectRatio: 1.35,
              children: [
                for (final t in topics)
                  _TopicCard(
                    topic: t,
                    onTap: () => t.route == null
                        ? context.pushNamed(RouteNames.faq)
                        : t.route == RouteNames.creditDashboard
                            ? context.goNamed(t.route!)
                            : context.pushNamed(t.route!),
                  ),
              ],
            ),
            AppSpacing.vGapLg,
            _ContactRow(
              onCall: () => context.showSnack('Connecting you to support…'),
              onChat: () => context.pushNamed(RouteNames.supportChat),
            ),
          ],
        ),
      ),
    );
  }
}

class _Topic {
  const _Topic(this.icon, this.title, this.subtitle, this.color, this.route);
  final IconData icon;
  final String title;
  final String subtitle;
  final Color color;
  final String? route;
}

class _HelpSearch extends StatelessWidget {
  const _HelpSearch({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final vs = context.vsColors;
    return InkWell(
      onTap: onTap,
      borderRadius: AppRadius.brMd,
      child: Container(
        height: 52,
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
        decoration: BoxDecoration(
          color: vs.trustTint.withValues(alpha: 0.5),
          borderRadius: AppRadius.brMd,
        ),
        child: Row(
          children: [
            Icon(Icons.search_rounded, color: vs.textSecondary),
            AppSpacing.hGapMd,
            Expanded(
              child: Text(
                'Search for help, orders, payments, credit issues…',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style:
                    AppTypography.bodyMedium.copyWith(color: vs.textSecondary),
              ),
            ),
            Icon(Icons.mic_none_rounded, color: vs.textSecondary),
          ],
        ),
      ),
    );
  }
}

class _TopicCard extends StatelessWidget {
  const _TopicCard({required this.topic, required this.onTap});

  final _Topic topic;
  final VoidCallback onTap;

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
          border: Border.all(color: vs.border),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Container(
              width: 40,
              height: 40,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: topic.color.withValues(alpha: 0.14),
                shape: BoxShape.circle,
              ),
              child: Icon(topic.icon, size: 20, color: topic.color),
            ),
            const Spacer(),
            Text(topic.title, style: AppTypography.titleMedium),
            const SizedBox(height: 2),
            Text(topic.subtitle,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style:
                    AppTypography.bodySmall.copyWith(color: vs.textSecondary)),
          ],
        ),
      ),
    );
  }
}

class _ContactRow extends StatelessWidget {
  const _ContactRow({required this.onCall, required this.onChat});

  final VoidCallback onCall;
  final VoidCallback onChat;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: VSOutlinedButton(
            label: 'Call Us',
            icon: Icons.call_rounded,
            onPressed: onCall,
          ),
        ),
        AppSpacing.hGapMd,
        Expanded(
          child: VSButton(
            label: 'Live Chat',
            icon: Icons.chat_bubble_outline_rounded,
            onPressed: onChat,
          ),
        ),
      ],
    );
  }
}
