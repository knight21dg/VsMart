import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/routes/route_paths.dart';
import '../../app/theme/theme_extensions.dart';
import '../../features/auth/presentation/providers/session_provider.dart';
import '../extensions/context_extensions.dart';
import 'failures.dart';
import 'localized_codes.dart';

/// Central, UI-driving presenter for [Failure]s. Reads the backend "actionable"
/// error envelope (code/title/action/severity/nextStep) off the failure and
/// turns it into the right UX: navigation, logout, retry, a styled snackbar, or
/// a blocking dialog.
///
/// Call this instead of a bare `context.showSnack` wherever a failure may carry
/// a machine code. Non-enveloped failures degrade gracefully to a severity-based
/// snackbar using the failure's [Failure.message].
void presentFailure(
  BuildContext context,
  WidgetRef ref,
  Failure failure, {
  VoidCallback? onRetry,
}) {
  switch (failure.actionType) {
    case 'navigate':
      final routeName = _mapTarget(failure.actionTarget);
      if (routeName != null) {
        // `go`, not `push`. An actionable error means "you can't do that here,
        // go there instead" — a destination change, not a drill-down.
        //
        // It also has to be `go`: half the targets (`/home`, `/cart`, `/credit`)
        // are StatefulShellRoute branches and `/login` is an entry route the
        // redirect rewrites to `/home`. Pushing any of those imperatively onto
        // the ROOT navigator renders a blank page — which is exactly what a
        // failed address save looked like: the POST 401'd, the presenter pushed
        // `/login`, the redirect turned it into `/home`, and the customer landed
        // on an empty screen with their address unsaved and no error shown.
        //
        // Navigating is not enough on its own — it also has to SAY WHY. Moving
        // the user silently is what made a blocked checkout look like a dead
        // button: MIN_ORDER_NOT_MET carries `navigate -> /cart`, so the order
        // just didn't place, the customer was dropped back on the cart, and
        // nothing ever told them the area has a minimum order. Every
        // navigate-action code had the same problem.
        //
        // The message must not DELAY the navigation though — a blocking dialog
        // here would strand an expired session on the failed screen until the
        // user tapped OK. So: capture the messenger first (it lives above the
        // router, so it survives the route change), navigate, then speak. The
        // message lands on the destination.
        final messenger = context.messenger;
        final text = _snackText(context, failure);
        final isError =
            failure.severity == 'error' || failure.severity == 'critical';
        // Resolved defensively: `context.vsColors` null-asserts the VSColors
        // theme extension, which is absent anywhere the full app theme isn't
        // installed — throwing on the way to showing an error message.
        final dangerColor = Theme.of(context).extension<VSColors>()?.danger ??
            Theme.of(context).colorScheme.error;
        context.goNamed(routeName);
        messenger
          ..hideCurrentSnackBar()
          ..showSnackBar(
            SnackBar(
              content: Text(text),
              backgroundColor: isError ? dangerColor : null,
              duration: const Duration(seconds: 6),
            ),
          );
        return;
      }
      // No known mapping -> fall through to a message.
      _showMessage(context, failure);
      return;

    case 'logout':
      _logoutAndRedirect(context, ref);
      return;

    case 'retry':
    case 'refresh':
      if (onRetry != null) {
        onRetry();
      } else {
        _showRetrySnack(context, failure, null);
      }
      return;

    case 'retry_verification':
      // Send the user back into the verification flow to re-attempt.
      context.pushNamed(RouteNames.kyc);
      return;

    case 'contact_support':
      context.pushNamed(RouteNames.support);
      return;

    default:
      _showMessage(context, failure, onRetry: onRetry);
  }
}

/// Maps a backend `action.target` route string to an app [RouteNames] id.
/// Returns null when there is no sensible mapping (caller falls back to a toast).
String? _mapTarget(String? target) {
  if (target == null || target.isEmpty) return null;
  // Match on the leading path segment so query/extra segments don't break it.
  final path = target.split('?').first;
  return switch (path) {
    '/verification' ||
    '/verification/identity' ||
    '/kyc' =>
      RouteNames.kyc,
    '/credit' || '/credit/dashboard' => RouteNames.creditDashboard,
    '/serviceability' || '/location' || '/not-serviceable' =>
      RouteNames.notServiceable,
    '/cart' => RouteNames.cart,
    '/login' => RouteNames.login,
    '/orders' => RouteNames.orders,
    '/support' => RouteNames.support,
    '/home' => RouteNames.home,
    _ => null,
  };
}

Future<void> _logoutAndRedirect(BuildContext context, WidgetRef ref) async {
  await ref.read(sessionControllerProvider.notifier).clearLocalSession();
  if (!context.mounted) return;
  context.goNamed(RouteNames.login);
}

/// Severity-driven message presentation for non-action (or unmapped) failures.
/// - info/warning  -> snackbar
/// - error         -> snackbar (error styling)
/// - critical      -> blocking AlertDialog
void _showMessage(
  BuildContext context,
  Failure failure, {
  VoidCallback? onRetry,
}) {
  final severity = failure.severity ?? (failure.title != null ? 'error' : null);
  if (severity == 'critical') {
    _showBlockingDialog(context, failure, onRetry: onRetry);
    return;
  }
  if (failure.retryable && onRetry != null) {
    _showRetrySnack(context, failure, onRetry);
    return;
  }
  final isError = severity == 'error' || severity == 'critical';
  context.showSnack(_snackText(context, failure), isError: isError);
}

void _showRetrySnack(
  BuildContext context,
  Failure failure,
  VoidCallback? onRetry,
) {
  final isError = failure.severity == 'error' || failure.severity == 'critical';
  context.messenger
    ..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(
        content: Text(_snackText(context, failure)),
        backgroundColor: isError ? context.vsColors.danger : null,
        action: onRetry != null
            ? SnackBarAction(
                label: context.l10n.commonRetry,
                onPressed: onRetry,
              )
            : null,
      ),
    );
}

void _showBlockingDialog(
  BuildContext context,
  Failure failure, {
  VoidCallback? onRetry,
}) {
  final loc = localizedForCode(context.l10n, failure.code);
  final title =
      loc?.title ?? failure.title ?? context.l10n.commonSomethingWentWrong;
  final body = loc?.message ?? failure.message;
  showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (dialogContext) {
      return AlertDialog(
        title: Text(title),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(body),
            if (failure.nextStep != null) ...[
              const SizedBox(height: 12),
              Text(
                failure.nextStep!,
                style: dialogContext.textStyles.bodySmall
                    ?.copyWith(color: dialogContext.vsColors.textSecondary),
              ),
            ],
          ],
        ),
        actions: [
          if (failure.retryable && onRetry != null)
            TextButton(
              onPressed: () {
                Navigator.of(dialogContext).pop();
                onRetry();
              },
              child: Text(dialogContext.l10n.commonRetry),
            ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: Text(dialogContext.l10n.commonOk),
          ),
        ],
      );
    },
  );
}

/// Compact one-line snack text: title (when present) + message, with nextStep
/// appended. Prefers the locale-mapped strings for the failure's backend code,
/// falling back to the backend-provided (English) title/message. Dialogs render
/// these as separate fields instead.
String _snackText(BuildContext context, Failure failure) {
  final loc = localizedForCode(context.l10n, failure.code);
  final title = loc?.title ?? failure.title;
  final message = loc?.message ?? failure.message;
  final buffer = StringBuffer();
  if (title != null && title.isNotEmpty) {
    buffer.write('$title: ');
  }
  buffer.write(message);
  // nextStep stays as the backend hint (untranslated) only when no code mapping.
  if (loc == null &&
      failure.nextStep != null &&
      failure.nextStep!.isNotEmpty) {
    buffer.write(' ${failure.nextStep}');
  }
  return buffer.toString();
}
