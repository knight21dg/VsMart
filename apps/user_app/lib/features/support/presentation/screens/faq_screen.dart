import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../app/theme/app_theme.dart';
import '../../../../core/extensions/context_extensions.dart';
import '../../../../core/widgets/widgets.dart';
import '../../data/support_data.dart';
import '../providers/support_providers.dart';
import '../widgets/support_call_button.dart';

/// Frequently Asked Questions — a searchable, category-filtered list (loaded from
/// the backend `/support/faqs`) of expandable cards, plus a "Still Need Help?" CTA.
class FaqScreen extends ConsumerStatefulWidget {
  const FaqScreen({super.key});

  @override
  ConsumerState<FaqScreen> createState() => _FaqScreenState();
}

class _FaqScreenState extends ConsumerState<FaqScreen> {
  static const List<String> _categories = [
    'All',
    'Orders',
    'Payments',
    'Credit',
    'Delivery',
    'KYC',
  ];

  final TextEditingController _searchController = TextEditingController();
  int _selectedCategory = 0;
  String _query = '';

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final selected = _categories[_selectedCategory];
    final q = _query.trim().toLowerCase();
    final faqsAsync = ref.watch(faqsProvider);

    List<Faq> filter(List<Faq> all) => all.where((f) {
          final matchesCategory = selected == 'All' || f.category == selected;
          final matchesQuery = q.isEmpty ||
              f.question.toLowerCase().contains(q) ||
              f.answer.toLowerCase().contains(q);
          return matchesCategory && matchesQuery;
        }).toList();

    return Scaffold(
      appBar: VSAppBar(title: context.l10n.supportFaqs),
      body: SafeArea(
        top: false,
        child: RefreshIndicator(
          onRefresh: () async {
            ref.invalidate(faqsProvider);
            await ref.read(faqsProvider.future);
          },
          child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(
              AppSpacing.lg, AppSpacing.md, AppSpacing.lg, AppSpacing.xxl),
          children: [
            Text(
              context.l10n.supportFaqsHeadline,
              style: AppTypography.headlineMedium,
            ),
            AppSpacing.vGapLg,
            VSSearchField(
              controller: _searchController,
              hint: context.l10n.supportSearchFaqs,
              onChanged: (v) => setState(() => _query = v),
            ),
            AppSpacing.vGapLg,
            SizedBox(
              height: 38,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: _categories.length,
                separatorBuilder: (_, __) => AppSpacing.hGapSm,
                itemBuilder: (context, i) => _CategoryChip(
                  label: _categories[i],
                  selected: i == _selectedCategory,
                  onTap: () => setState(() => _selectedCategory = i),
                ),
              ),
            ),
            AppSpacing.vGapLg,
            ...faqsAsync.when<List<Widget>>(
              loading: () => const [
                Padding(
                  padding: EdgeInsets.symmetric(vertical: AppSpacing.xl),
                  child: Center(child: CircularProgressIndicator()),
                ),
              ],
              error: (_, __) => [
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: AppSpacing.xl),
                  child: Column(
                    children: [
                      Text(
                        context.l10n.supportFaqsLoadError,
                        textAlign: TextAlign.center,
                        style: AppTypography.bodyMedium
                            .copyWith(color: context.vsColors.textSecondary),
                      ),
                      AppSpacing.vGapMd,
                      VSOutlinedButton(
                        label: context.l10n.commonRetry,
                        icon: Icons.refresh_rounded,
                        isExpanded: false,
                        onPressed: () => ref.invalidate(faqsProvider),
                      ),
                    ],
                  ),
                ),
              ],
              data: (all) {
                final visibleFaqs = filter(all);
                if (visibleFaqs.isEmpty) {
                  return [
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: AppSpacing.xl),
                      child: Center(
                        child: Text(
                          context.l10n.supportNoFaqsMatch,
                          style: AppTypography.bodyMedium
                              .copyWith(color: context.vsColors.textSecondary),
                        ),
                      ),
                    ),
                  ];
                }
                return [
                  for (var i = 0; i < visibleFaqs.length; i++) ...[
                    if (i != 0) AppSpacing.vGapMd,
                    _FaqCard(faq: visibleFaqs[i], initiallyExpanded: i == 0),
                  ],
                ];
              },
            ),
            AppSpacing.vGapXl,
            const _StillNeedHelp(),
          ],
          ),
        ),
      ),
    );
  }
}

/// A pill category filter chip mirroring the selected (green) / unselected
/// (tinted) states in the design.
class _CategoryChip extends StatelessWidget {
  const _CategoryChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final vs = context.vsColors;
    return Material(
      color: selected ? vs.brand : vs.brandTint,
      borderRadius: AppRadius.brPill,
      child: InkWell(
        borderRadius: AppRadius.brPill,
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.lg, vertical: AppSpacing.sm),
          child: Center(
            child: Text(
              label,
              style: AppTypography.labelMedium.copyWith(
                color: selected ? AppColors.white : vs.brand,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// White card wrapping an [ExpansionTile] for a single Q&A, with dividers
/// suppressed.
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
          title: Text(faq.question, style: AppTypography.titleLarge),
          children: [
            Text(
              faq.answer,
              style:
                  AppTypography.bodyMedium.copyWith(color: vs.textSecondary),
            ),
            // NOTE: a "Was this helpful?" control used to live here but only
            // showed a snackbar — no backend records FAQ feedback (the /support
            // /faqs endpoint is read-only). Removed rather than fake it; re-add
            // once a feedback-recording endpoint exists.
          ],
        ),
      ),
    );
  }
}

/// Closing support call-to-action — a single Call Support button, matching
/// the tinted panel at the bottom of the design. No live chat, no ticket
/// form: a customer who didn't find their answer above just calls.
class _StillNeedHelp extends StatelessWidget {
  const _StillNeedHelp();

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
          Text(context.l10n.supportStillNeedHelp,
              style: AppTypography.headlineSmall),
          AppSpacing.vGapXs,
          Text(
            context.l10n.supportTeamHereToAssist,
            textAlign: TextAlign.center,
            style:
                AppTypography.bodyMedium.copyWith(color: vs.textSecondary),
          ),
          AppSpacing.vGapLg,
          const SupportCallButton(),
        ],
      ),
    );
  }
}
