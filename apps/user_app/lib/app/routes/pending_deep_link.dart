import 'package:flutter_riverpod/flutter_riverpod.dart';

/// A deep link parked until the app is ready to show it.
///
/// An incoming link cannot simply be navigated to on arrival. On a cold start the
/// router holds every location on `/splash` while bootstrap settles, then sends
/// the user to onboarding / login / home by lifecycle stage — so a link delivered
/// in that window is overwritten and lost. The serviceability gate does the same
/// on a fresh install while it resolves its first verdict, and an unauthenticated
/// user is bounced to login regardless.
///
/// So the link is parked here and the router's redirect takes it at the one point
/// where every gate has already allowed the current location. That way a shared
/// product link survives a cold start, onboarding and a sign-in, and still lands
/// on the product.
///
/// Deliberately a plain mutable holder rather than a `StateProvider`: the redirect
/// reads and clears it *during* route resolution, and mutating listened state
/// there would re-enter the redirect.
class PendingDeepLink {
  String? _path;

  bool get isPending => _path != null;

  void park(String path) => _path = path;

  /// Returns the parked path and clears it.
  ///
  /// Taking on the first attempt is intentional: it bounds the work to a single
  /// navigation, so a link whose target a gate still rejects (an out-of-area
  /// customer opening a product) shows the gate screen instead of ping-ponging
  /// between the gate and the link until go_router's redirect limit trips.
  String? take() {
    final path = _path;
    _path = null;
    return path;
  }
}

final pendingDeepLinkProvider = Provider<PendingDeepLink>(
  (ref) => PendingDeepLink(),
);

/// Bumped whenever a link is parked, to re-run the router's redirect.
///
/// The holder above is intentionally not listenable, so this is what tells the
/// router something arrived — needed for a warm link, where no auth/startup state
/// changes and nothing else would trigger a redirect.
final deepLinkTickProvider = StateProvider<int>((ref) => 0);
