import 'package:autocarnet/core/router/app_router.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// Regression coverage for a real bug: tapping "Rejoindre un véhicule"
/// (which pushes '/vehicles/join') was silently resolving to
/// VehicleHomeScreen(vehicleId: 'join') instead of JoinVehicleScreen,
/// because '/vehicles/:id' was declared *before* '/vehicles/join' in
/// app_router.dart - go_router matches routes in declaration order, and
/// ':id' matches any single segment, including the literal "join". The
/// user never got to see the code-entry form at all: the vehicle screen
/// spun for a few seconds trying to sync a vehicle that (obviously) does
/// not exist, then gave up with a "not available" message - with zero
/// code ever entered.
///
/// This test only ever inspects go_router's *route matching* (which
/// GoRoute pattern a location resolves to) - it deliberately never builds
/// any of the matched screens, so it needs no repository/Supabase
/// overrides at all and can't be fooled by a screen that happens not to
/// crash.
void main() {
  test(
      '"/vehicles/join" resolves to the dedicated join route, never to '
      '"/vehicles/:id" with id="join"', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final router = container.read(appRouterProvider);
    addTearDown(router.dispose);

    // RouteConfiguration.findMatch is the same synchronous matcher
    // go_router itself uses to pick a GoRoute for a location - checking it
    // directly means this test needs no widget tree (and so no
    // repository/Supabase provider overrides) and can't be fooled by a
    // matched screen that happens not to crash when built.
    final matchList = router.configuration.findMatch(Uri.parse('/vehicles/join'));

    expect(matchList.fullPath, '/vehicles/join');
  });

  test('a real vehicle id still resolves to "/vehicles/:id" as normal', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final router = container.read(appRouterProvider);
    addTearDown(router.dispose);

    final matchList = router.configuration.findMatch(Uri.parse('/vehicles/some-real-vehicle-id'));

    expect(matchList.fullPath, '/vehicles/:id');
  });
}
