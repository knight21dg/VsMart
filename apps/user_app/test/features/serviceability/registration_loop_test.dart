import 'package:flutter_test/flutter_test.dart';
import 'package:user_app/app/routes/route_guards.dart';
import 'package:user_app/app/routes/route_paths.dart';
import 'package:user_app/features/serviceability/presentation/providers/serviceability_gate_providers.dart';

/// Regression: a brand-new, out-of-area account got stuck on go_router's
/// "Route not found" error page after sign-in.
///
/// Cause was a redirect loop between the two authenticated gates for a
/// `registrationIncomplete` user who is `unserviceable`:
///   • lifecycle guard pins every non-`/register` location to `/register`
///   • serviceability gate bounces `/register` → `/not-serviceable`
///   • lifecycle guard bounces `/not-serviceable` → `/register` … forever
/// go_router hits its redirect limit, throws, and renders the error page.
///
/// The fix: the serviceability lock only engages once the user is
/// `UserStage.approved` (registration complete). These tests lock that in.
void main() {
  group('the two gates in isolation still describe the loop hazard', () {
    test('lifecycle guard sends an unregistered user off the lock screen', () {
      expect(resolveGuardRedirect(
              UserStage.registrationIncomplete, RoutePaths.notServiceable),
          RoutePaths.register);
    });

    test('serviceability gate would lock the sign-up screen out-of-area', () {
      expect(serviceabilityGateRedirect(
              GateStatus.unserviceable, RoutePaths.register),
          RoutePaths.notServiceable);
    });
  });

  group('resolveAuthenticatedRedirect breaks the loop', () {
    test('out-of-area new account is sent to /register, not /not-serviceable',
        () {
      final target = resolveAuthenticatedRedirect(
        UserStage.registrationIncomplete,
        GateStatus.unserviceable,
        RoutePaths.register,
      );
      // Allowed to render /register (null) — crucially NOT /not-serviceable.
      expect(target, isNot(RoutePaths.notServiceable));
      expect(target, isNull);
    });

    test('the redirect chain terminates (no register <-> lock ping-pong)', () {
      // Walk the composed guard the way go_router would, following each
      // redirect. A fixed point (null or a self-target) must be reached well
      // within go_router's redirect budget.
      var loc = RoutePaths.notServiceable; // where the old loop kicked off
      String? next;
      var hops = 0;
      while ((next = resolveAuthenticatedRedirect(
                  UserStage.registrationIncomplete,
                  GateStatus.unserviceable,
                  loc)) !=
              null &&
          next != loc) {
        loc = next!;
        expect(++hops, lessThan(5), reason: 'redirect loop did not terminate');
      }
      expect(loc, RoutePaths.register); // settles on sign-up
    });

    test('an approved out-of-area user is still funnelled to the lock screen',
        () {
      expect(
        resolveAuthenticatedRedirect(
            UserStage.approved, GateStatus.unserviceable, RoutePaths.home),
        RoutePaths.notServiceable,
      );
    });

    test('an approved serviceable user browses freely', () {
      expect(
        resolveAuthenticatedRedirect(
            UserStage.approved, GateStatus.serviceable, RoutePaths.home),
        isNull,
      );
    });
  });
}
