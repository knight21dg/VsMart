import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/constants/api_constants.dart';
import '../../../app/theme/app_theme.dart';
import '../../../core/extensions/context_extensions.dart';
import '../../../core/widgets/widgets.dart';
import '../../../shared/providers/core_providers.dart';

/// A pending cash collection the customer must confirm.
class CollectionConfirmInfo {
  const CollectionConfirmInfo({
    required this.collectionId,
    required this.amount,
    required this.otp,
    required this.agentName,
  });

  final String collectionId;
  final double amount;
  final String otp;
  final String agentName;

  static CollectionConfirmInfo? fromEnvelope(dynamic raw) {
    final data = raw is Map && raw['data'] is Map ? raw['data'] : raw;
    final pending = data is Map ? data['pending'] : null;
    if (pending is! Map) return null;
    final m = Map<String, dynamic>.from(pending);
    return CollectionConfirmInfo(
      collectionId: '${m['collectionId'] ?? ''}',
      amount: double.tryParse('${m['amount'] ?? ''}') ?? 0,
      otp: '${m['otp'] ?? ''}',
      agentName: '${m['agentName'] ?? 'The agent'}',
    );
  }
}

/// Fetches the customer's pending collection confirmation (null if none).
final collectionConfirmProvider =
    FutureProvider.autoDispose<CollectionConfirmInfo?>((ref) async {
  final res =
      await ref.watch(apiClientProvider).get<dynamic>(ApiConstants.collectionConfirm);
  return CollectionConfirmInfo.fromEnvelope(res.data);
});

String _money(double v) {
  final cents = (v.abs() * 100).round();
  final whole = (cents ~/ 100).toString();
  final paise = (cents % 100).toString().padLeft(2, '0');
  return '₹$whole.$paise';
}

/// Customer-facing screen showing the OTP to read out to the agent so they can
/// collect the shown amount. The OTP lives only in the app — never in an SMS.
///
/// Polls in the background while open so a customer staring at the code sees
/// it flip to a "Payment confirmed" state the moment the agent verifies it,
/// instead of the code just sitting there with no feedback.
class CollectionConfirmScreen extends ConsumerStatefulWidget {
  const CollectionConfirmScreen({super.key});

  @override
  ConsumerState<CollectionConfirmScreen> createState() =>
      _CollectionConfirmScreenState();
}

class _CollectionConfirmScreenState
    extends ConsumerState<CollectionConfirmScreen> {
  Timer? _poll;
  CollectionConfirmInfo? _lastSeen;
  bool _justConfirmed = false;

  @override
  void initState() {
    super.initState();
    _poll = Timer.periodic(const Duration(seconds: 4), (_) {
      if (mounted) ref.invalidate(collectionConfirmProvider);
    });
  }

  @override
  void dispose() {
    _poll?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final async = ref.watch(collectionConfirmProvider);

    async.whenData((info) {
      if (info == null && _lastSeen != null && !_justConfirmed) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) setState(() => _justConfirmed = true);
        });
      } else if (info != null) {
        _lastSeen = info;
      }
    });

    return Scaffold(
      appBar: AppBar(title: Text(l10n.collectionConfirmTitle)),
      body: Stack(
        children: [
          const _TopBrandWash(),
          async.when(
            loading: () => const VSLoadingView(),
            error: (_, __) => VSErrorView(
              message: l10n.collectionConfirmLoadError,
              onRetry: () => ref.invalidate(collectionConfirmProvider),
            ),
            data: (info) {
              if (_justConfirmed && _lastSeen != null) {
                return _ConfirmedView(info: _lastSeen!);
              }
              if (info == null) {
                return VSEmptyState(
                  icon: Icons.check_circle_outline_rounded,
                  title: l10n.collectionConfirmNothingTitle,
                  message: l10n.collectionConfirmNothingBody,
                );
              }
              return RefreshIndicator(
                onRefresh: () async => ref.invalidate(collectionConfirmProvider),
                child: _PendingView(info: info),
              );
            },
          ),
        ],
      ),
    );
  }
}

/// The live "share this code" body.
class _PendingView extends StatelessWidget {
  const _PendingView({required this.info});

  final CollectionConfirmInfo info;

  @override
  Widget build(BuildContext context) {
    final vs = context.vsColors;
    final l10n = context.l10n;
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: AppSpacing.screen,
      children: [
        AppSpacing.vGapMd,
        const _AgentIllustration(),
        AppSpacing.vGapLg,
        Text(
          l10n.collectionConfirmCollecting(info.agentName),
          textAlign: TextAlign.center,
          style: AppTypography.bodyMedium.copyWith(color: vs.textSecondary),
        ),
        AppSpacing.vGapXs,
        Text(
          _money(info.amount),
          textAlign: TextAlign.center,
          style: AppTypography.displayMedium.copyWith(
            color: vs.brand,
            fontWeight: FontWeight.w800,
          ),
        ),
        AppSpacing.vGapXl,
        _PulsingCodeCard(otp: info.otp),
        AppSpacing.vGapLg,
        Container(
          padding: AppSpacing.card,
          decoration: BoxDecoration(
            color: vs.warning.withValues(alpha: 0.08),
            borderRadius: AppRadius.brMd,
            border: Border.all(color: vs.warning.withValues(alpha: 0.3)),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.info_outline_rounded, color: vs.warning, size: 20),
              AppSpacing.hGapSm,
              Expanded(
                child: Text(
                  l10n.collectionConfirmSafetyWarning(_money(info.amount)),
                  style: AppTypography.bodySmall.copyWith(color: vs.textSecondary),
                ),
              ),
            ],
          ),
        ),
        AppSpacing.vGapLg,
      ],
    );
  }
}

/// The success body shown the moment the pending code clears.
class _ConfirmedView extends StatelessWidget {
  const _ConfirmedView({required this.info});

  final CollectionConfirmInfo info;

  @override
  Widget build(BuildContext context) {
    final vs = context.vsColors;
    final l10n = context.l10n;
    return Center(
      child: Padding(
        padding: AppSpacing.screen,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TweenAnimationBuilder<double>(
              tween: Tween(begin: 0, end: 1),
              duration: const Duration(milliseconds: 420),
              curve: Curves.elasticOut,
              builder: (context, t, child) =>
                  Transform.scale(scale: t, child: child),
              child: Container(
                height: 96,
                width: 96,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: vs.success.withValues(alpha: 0.12),
                ),
                child: Icon(Icons.check_rounded, color: vs.success, size: 52),
              ),
            ),
            AppSpacing.vGapLg,
            Text(l10n.collectionConfirmDoneTitle,
                textAlign: TextAlign.center, style: AppTypography.headlineMedium),
            AppSpacing.vGapSm,
            Text(
              l10n.collectionConfirmDoneBody(info.agentName, _money(info.amount)),
              textAlign: TextAlign.center,
              style: AppTypography.bodyMedium.copyWith(color: vs.textSecondary),
            ),
          ],
        ),
      ),
    );
  }
}

/// A friendly icon inside a soft brand halo, mirroring the OTP-verification
/// illustration used elsewhere in the app for a consistent look.
class _AgentIllustration extends StatelessWidget {
  const _AgentIllustration();

  @override
  Widget build(BuildContext context) {
    final vs = context.vsColors;
    return SizedBox(
      height: 108,
      width: 108,
      child: Stack(
        alignment: Alignment.center,
        children: [
          Container(
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: vs.brandTint,
              boxShadow: [
                BoxShadow(
                  color: AppColors.vsGreen.withValues(alpha: 0.16),
                  blurRadius: 28,
                  offset: const Offset(0, 10),
                ),
              ],
            ),
          ),
          Icon(Icons.delivery_dining_rounded, color: vs.brand, size: 48),
        ],
      ),
    );
  }
}

/// The handover code as individually boxed digits with a slow, breathing glow
/// so it reads as the thing on this screen the customer needs to notice.
class _PulsingCodeCard extends StatefulWidget {
  const _PulsingCodeCard({required this.otp});

  final String otp;

  @override
  State<_PulsingCodeCard> createState() => _PulsingCodeCardState();
}

class _PulsingCodeCardState extends State<_PulsingCodeCard>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1400),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final vs = context.vsColors;
    final l10n = context.l10n;
    final digits = widget.otp.split('');
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        final glow = 0.10 + (_controller.value * 0.12);
        return Container(
          padding: const EdgeInsets.symmetric(vertical: AppSpacing.xl),
          decoration: BoxDecoration(
            color: vs.brandTint,
            borderRadius: AppRadius.brLg,
            border: Border.all(color: vs.brand.withValues(alpha: 0.4)),
            boxShadow: [
              BoxShadow(
                color: AppColors.vsGreen.withValues(alpha: glow),
                blurRadius: 24,
                spreadRadius: 2,
              ),
            ],
          ),
          child: child,
        );
      },
      child: Column(
        children: [
          Text(
            l10n.collectionConfirmShareCode,
            style: AppTypography.labelMedium
                .copyWith(color: vs.textSecondary, letterSpacing: 1.5),
          ),
          AppSpacing.vGapMd,
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              for (var i = 0; i < digits.length; i++) ...[
                if (i != 0) const SizedBox(width: 8),
                Container(
                  width: 40,
                  height: 52,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: context.colors.surface,
                    borderRadius: AppRadius.brMd,
                    border: Border.all(color: vs.brand.withValues(alpha: 0.5)),
                  ),
                  child: Text(
                    digits[i],
                    style: AppTypography.headlineMedium.copyWith(
                      color: vs.brand,
                      fontWeight: FontWeight.w800,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                ),
              ],
            ],
          ),
          AppSpacing.vGapSm,
          TextButton.icon(
            onPressed: () {
              Clipboard.setData(ClipboardData(text: widget.otp));
              context.showSnack(l10n.offersCodeCopied);
            },
            icon: const Icon(Icons.copy_rounded, size: 16),
            label: Text(l10n.offersCopy),
          ),
        ],
      ),
    );
  }
}

/// Faint green-to-transparent wash at the top of the screen, matching the
/// OTP-verification screen elsewhere in the app.
class _TopBrandWash extends StatelessWidget {
  const _TopBrandWash();

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Container(
        height: 280,
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              AppColors.vsGreen.withValues(alpha: 0.10),
              AppColors.vsGreen.withValues(alpha: 0.0),
            ],
          ),
        ),
      ),
    );
  }
}
