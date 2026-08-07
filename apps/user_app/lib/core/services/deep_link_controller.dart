import 'dart:async';

import 'package:app_links/app_links.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/routes/pending_deep_link.dart';
import '../utils/app_logger.dart';
import 'deep_link.dart';

/// Receives Android App Links / iOS Universal Links and parks them for the router.
///
/// Two delivery paths have to be covered, and they are not the same:
///
///  * **cold start** — the app was launched *by* the link. `getInitialLink()` is
///    read once, because the platform stream does not reliably replay the launch
///    intent on every platform/version.
///  * **warm** — the app was already running (`onNewIntent` on Android,
///    `continueUserActivity` on iOS), delivered through [AppLinks.uriLinkStream].
///
/// Both funnel into [PendingDeepLink] rather than navigating directly: at cold
/// start the router is still holding on splash and would discard the navigation.
class DeepLinkController {
  DeepLinkController({
    required PendingDeepLink pending,
    required void Function() onLink,
    AppLinks? links,
  })  : _pending = pending,
        _onLink = onLink,
        _links = links ?? AppLinks();

  final PendingDeepLink _pending;

  /// Nudges the router to re-run its redirect once a link is parked.
  final void Function() _onLink;

  final AppLinks _links;
  StreamSubscription<Uri>? _sub;

  /// The last link acted on, so the launch link isn't opened twice when a
  /// platform also emits it on the stream.
  Uri? _last;

  Future<void> start() async {
    if (_sub != null) return;
    _sub = _links.uriLinkStream.listen(
      handle,
      onError: (Object e) => AppLogger.w('Deep link stream error: $e'),
    );
    try {
      final initial = await _links.getInitialLink();
      if (initial != null) handle(initial);
    } catch (e) {
      // A missing/!malformed launch intent must never stop the app from opening.
      AppLogger.w('Initial deep link failed: $e');
    }
  }

  /// Visible for testing: resolve [uri] and park it if it's one of ours.
  void handle(Uri uri) {
    if (uri == _last) return;
    _last = uri;
    final path = resolveDeepLink(uri);
    if (path == null) {
      // Not a link shape we publish. Ignored on purpose — the app just opens
      // normally rather than showing an error for a URL we don't own.
      AppLogger.d('Ignoring unrecognised deep link: $uri');
      return;
    }
    _pending.park(path);
    _onLink();
  }

  void dispose() {
    _sub?.cancel();
    _sub = null;
  }
}

final deepLinkControllerProvider = Provider<DeepLinkController>((ref) {
  final controller = DeepLinkController(
    pending: ref.watch(pendingDeepLinkProvider),
    onLink: () => ref.read(deepLinkTickProvider.notifier).state++,
  );
  ref.onDispose(controller.dispose);
  return controller;
});
