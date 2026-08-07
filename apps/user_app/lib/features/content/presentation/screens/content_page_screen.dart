import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../app/theme/app_theme.dart';
import '../../../../core/extensions/context_extensions.dart';
import '../../../../core/widgets/widgets.dart';
import '../providers/content_providers.dart';

/// Renders a CMS page (About / Contact / Careers / Terms / Privacy) fetched
/// from the backend by [slug]. The optional [title] seeds the app bar while the
/// page loads, before the real title arrives from the server.
///
/// The body is plain text from the CMS: it is split on blank lines into
/// readable paragraphs with comfortable line height, matching the reading
/// layout of the existing legal screens.
class ContentPageScreen extends ConsumerWidget {
  const ContentPageScreen({
    super.key,
    required this.slug,
    this.title,
  });

  final String slug;
  final String? title;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final pageAsync = ref.watch(contentPageProvider(slug));

    return pageAsync.when(
      loading: () => Scaffold(
        appBar: VSAppBar(title: title ?? ''),
        body: const VSLoadingView(),
      ),
      error: (_, __) => Scaffold(
        appBar: VSAppBar(title: title ?? ''),
        body: VSErrorView(
          onRetry: () => ref.invalidate(contentPageProvider(slug)),
        ),
      ),
      data: (page) {
        final paragraphs = _paragraphs(page.body);
        if (paragraphs.isEmpty) {
          // The page loaded fine but has no body text yet (unpublished/empty
          // CMS content). Show a friendly placeholder instead of a blank page.
          return Scaffold(
            appBar: VSAppBar(title: page.title),
            body: const SafeArea(
              top: false,
              child: VSEmptyState(
                icon: Icons.article_outlined,
                title: 'Nothing here yet',
                message:
                    'This page has no content right now. Please check back later.',
              ),
            ),
          );
        }
        return Scaffold(
          appBar: VSAppBar(title: page.title),
          body: SafeArea(
            top: false,
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.lg,
                AppSpacing.lg,
                AppSpacing.lg,
                AppSpacing.xxl,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (var i = 0; i < paragraphs.length; i++) ...[
                    if (i != 0) AppSpacing.vGapLg,
                    Text(
                      paragraphs[i],
                      style: AppTypography.bodyMedium.copyWith(
                        height: 1.6,
                        color: context.vsColors.textSecondary,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  /// Splits CMS body text into paragraphs on blank lines, trimming each and
  /// dropping empties. Falls back to a single trimmed block when there are no
  /// blank-line separators.
  static List<String> _paragraphs(String body) {
    final parts = body
        .replaceAll('\r\n', '\n')
        .split(RegExp(r'\n[ \t]*\n'))
        .map((p) => p.trim())
        .where((p) => p.isNotEmpty)
        .toList();
    return parts.isEmpty ? const [] : parts;
  }
}
