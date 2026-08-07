import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../app/theme/app_theme.dart';
import '../../../../core/extensions/context_extensions.dart';
import '../../data/support_data.dart';
import '../providers/support_providers.dart';
import '../widgets/support_call_button.dart';

/// Help & Support — kept deliberately small: a short FAQ list and one Call
/// Support button. No live chat, no ticket inbox, no topic maze — a
/// customer with a question either finds the answer here or calls the store
/// handling their orders.
class SupportScreen extends ConsumerWidget {
  const SupportScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final faqsAsync = ref.watch(faqsProvider);

    return Scaffold(
      appBar: AppBar(
        centerTitle: true,
        title: Text(context.l10n.supportTitle, style: AppTypography.headlineSmall),
      ),
      body: SafeArea(
        top: false,
        child: RefreshIndicator(
          onRefresh: () async {
            ref.invalidate(faqsProvider);
            await ref.read(faqsProvider.future);
          },
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: AppSpacing.screen,
            children: [
              AppSpacing.vGapSm,
              Text(context.l10n.supportHowCanWeHelp,
                  style: AppTypography.headlineMedium),
              AppSpacing.vGapXl,
              Text(context.l10n.supportFaqs, style: AppTypography.headlineSmall),
              AppSpacing.vGapMd,
              ...faqsAsync.when<List<Widget>>(
                loading: () => const [
                  Padding(
                    padding: EdgeInsets.symmetric(vertical: AppSpacing.xl),
                    child: Center(child: CircularProgressIndicator()),
                  ),
                ],
                error: (_, __) => [
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: AppSpacing.lg),
                    child: Text(
                      context.l10n.supportFaqsLoadError,
                      style: AppTypography.bodyMedium
                          .copyWith(color: context.vsColors.textSecondary),
                    ),
                  ),
                ],
                data: (all) {
                  if (all.isEmpty) return const [];
                  return [
                    for (var i = 0; i < all.length; i++) ...[
                      if (i != 0) AppSpacing.vGapMd,
                      _FaqCard(faq: all[i], initiallyExpanded: i == 0),
                    ],
                  ];
                },
              ),
              AppSpacing.vGapXl,
              const _ContactCard(),
            ],
          ),
        ),
      ),
    );
  }
}

/// White card wrapping an [ExpansionTile] for a single Q&A.
class _FaqCard extends StatelessWidget {
  const _FaqCard({required this.faq, this.initiallyExpanded = false});

  final Faq faq;
  final bool initiallyExpanded;

  @override
  Widget build(BuildContext context) {
    final vs = context.vsColors;
    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: context.colors.surface,
        borderRadius: AppRadius.brLg,
        border: Border.all(color: vs.border),
      ),
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: AppColors.transparent),
        child: ExpansionTile(
          initiallyExpanded: initiallyExpanded,
          tilePadding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.lg, vertical: AppSpacing.xs),
          childrenPadding: const EdgeInsets.fromLTRB(
              AppSpacing.lg, 0, AppSpacing.lg, AppSpacing.lg),
          expandedCrossAxisAlignment: CrossAxisAlignment.start,
          iconColor: vs.textSecondary,
          collapsedIconColor: vs.textSecondary,
          title: Text(faq.question, style: AppTypography.titleMedium),
          children: [
            Text(
              faq.answer,
              style: AppTypography.bodyMedium.copyWith(color: vs.textSecondary),
            ),
          ],
        ),
      ),
    );
  }
}

class _ContactCard extends StatelessWidget {
  const _ContactCard();

  @override
  Widget build(BuildContext context) {
    final vs = context.vsColors;
    return Container(
      padding: const EdgeInsets.all(AppSpacing.xl),
      decoration: BoxDecoration(
        color: vs.trustTint.withValues(alpha: 0.5),
        borderRadius: AppRadius.brLg,
      ),
      child: Column(
        children: [
          Text(context.l10n.supportStillNeedHelp, style: AppTypography.headlineSmall),
          AppSpacing.vGapXs,
          Text(
            context.l10n.supportTeamHereToAssist,
            textAlign: TextAlign.center,
            style: AppTypography.bodyMedium.copyWith(color: vs.textSecondary),
          ),
          AppSpacing.vGapLg,
          const SupportCallButton(),
        ],
      ),
    );
  }
}
