import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/routes/route_paths.dart';
import '../../features/auth/presentation/providers/session_provider.dart';
import '../extensions/context_extensions.dart';
import 'failures.dart';

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
        context.pushNamed(routeName);
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
  context.showSnack(_snackText(failure), isError: isError);
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
        content: Text(_snackText(failure)),
        backgroundColor: isError ? context.vsColors.danger : null,
        action: onRetry != null
            ? SnackBarAction(
                label: 'Retry',
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
  final title = failure.title ?? 'Something went wrong';
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
            Text(failure.message),
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
              child: const Text('Retry'),
            ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('OK'),
          ),
        ],
      );
    },
  );
}

/// Compact one-line snack text: title (when present) + message, with nextStep
/// appended. Dialogs render these as separate fields instead.
String _snackText(Failure failure) {
  final buffer = StringBuffer();
  if (failure.title != null && failure.title!.isNotEmpty) {
    buffer.write('${failure.title}: ');
  }
  buffer.write(failure.message);
  if (failure.nextStep != null && failure.nextStep!.isNotEmpty) {
    buffer.write(' ${failure.nextStep}');
  }
  return buffer.toString();
}
