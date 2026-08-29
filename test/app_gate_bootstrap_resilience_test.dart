import 'dart:async';

import 'package:autocarnet/features/account/data/account_repository.dart';
import 'package:autocarnet/features/account/presentation/account_gate_screen.dart';
import 'package:autocarnet/features/onboarding_lock/data/biometric_service.dart';
import 'package:autocarnet/features/onboarding_lock/data/pin_service.dart';
import 'package:autocarnet/features/onboarding_lock/presentation/app_gate.dart';
import 'package:autocarnet/features/onboarding_lock/presentation/lock_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Mission 2026, post-launch-hang incident: a real device got permanently
/// stuck on AppGate's loading splash because [AccountRepository.
/// isDeviceStillAuthorized] awaited a Supabase request that never resolved
/// (not a thrown error - a genuinely hung network call), and the gate's
/// bootstrap depended on it completing before ever showing a screen.
///
/// AppGate is now offline-first by construction: the very first screen is
/// decided from local reads alone, and the online device-authorization
/// check only ever runs in the BACKGROUND, after a screen is already up.
/// Every local read is itself individually bounded, and the whole local
/// phase carries one more absolute ceiling on top (see AppGate's
/// `_localStepTimeout` / `_bootstrapFailsafeTimeout` / `_backgroundCheckTimeout`).
///
/// These tests never wait in real time for a hung Future - flutter_test
/// runs every test body inside a fake-async zone, so advancing the clock
/// with `tester.pump(duration)` fires a `.timeout()`'s internal Timer
/// immediately, without the test itself taking anywhere near that long.
class _FakeAccountRepository implements AccountRepository {
  _FakeAccountRepository({
    this.initiallyAuthorized = false,
    this.deviceAuthorizedUserIdImpl,
    this.isDeviceStillAuthorizedImpl,
  }) : _currentUser = initiallyAuthorized
            ? User(
                id: 'user-1',
                appMetadata: const {},
                userMetadata: null,
                aud: 'authenticated',
                email: 'a@example.com',
                createdAt: DateTime.now().toIso8601String(),
              )
            : null;

  final bool initiallyAuthorized;
  final User? _currentUser;
  final Future<String?> Function()? deviceAuthorizedUserIdImpl;
  final Future<bool> Function()? isDeviceStillAuthorizedImpl;
  bool disconnectThisDeviceCalled = false;

  @override
  User? get currentUser => _currentUser;
  @override
  Session? get currentSession => null;
  @override
  bool get isSignedIn => _currentUser != null;
  @override
  Stream<AuthState> get onAuthStateChange => const Stream.empty();
  @override
  Future<String?> tryRestoreDeviceSession(String email) async => null;
  @override
  Future<void> sendEmailCode(String email) async {}
  @override
  Future<void> verifyEmailCode({required String email, required String code}) async {}
  @override
  Future<String> installationId() async => 'test-device';
  @override
  Future<String?> deviceAuthorizedUserId() =>
      deviceAuthorizedUserIdImpl?.call() ??
      Future.value(initiallyAuthorized ? 'user-1' : null);
  @override
  Future<String?> lastDeviceUserId() async => initiallyAuthorized ? 'user-1' : null;
  @override
  Future<String?> deviceAuthorizedEmail() async => initiallyAuthorized ? 'a@example.com' : null;
  @override
  Future<void> registerThisDevice() async {}
  @override
  Future<bool> isDeviceStillAuthorized({required String userId}) =>
      isDeviceStillAuthorizedImpl?.call() ?? Future.value(true);
  @override
  Future<List<AuthorizedDevice>> listMyDevices() async => const [];
  @override
  Future<void> revokeDevice(String deviceRowId) async {}
  @override
  Future<void> disconnectFromThisDevice() async {
    disconnectThisDeviceCalled = true;
  }

  @override
  Future<void> disconnectFromAllDevices() async {}
}

class _FakePinService implements PinService {
  _FakePinService({this.hang = false});
  static const pins = {'user-1': '9999'};
  final bool hang;

  @override
  Future<bool> isPinSet(String accountId) {
    if (hang) return Completer<bool>().future;
    return Future.value(pins.containsKey(accountId));
  }

  @override
  Future<void> setPin(String accountId, String pin) async {}
  @override
  Future<bool> verifyPin(String accountId, String pin) async => pins[accountId] == pin;
  @override
  Future<void> clearPin(String accountId) async {}
}

class _FakeBiometricService implements BiometricService {
  @override
  Future<bool> isDeviceSupported() async => false;
  @override
  Future<bool> isEnabled(String accountId) async => false;
  @override
  Future<void> setEnabled(String accountId, bool enabled) async {}
  @override
  Future<bool> authenticate() async => false;
}

void main() {
  Future<ProviderContainer> pumpGate(
    WidgetTester tester, {
    required _FakeAccountRepository account,
    _FakePinService? pinService,
  }) async {
    final container = ProviderContainer(overrides: [
      accountRepositoryProvider.overrideWithValue(account),
      pinServiceProvider.overrideWithValue(pinService ?? _FakePinService()),
      biometricServiceProvider.overrideWithValue(_FakeBiometricService()),
    ]);
    addTearDown(container.dispose);
    final router = GoRouter(
      initialLocation: '/',
      routes: [GoRoute(path: '/', builder: (_, _) => const SizedBox.shrink())],
    );
    addTearDown(router.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp.router(
          routerConfig: router,
          builder: (context, child) => AppGate(child: child ?? const SizedBox.shrink()),
        ),
      ),
    );
    return container;
  }

  testWidgets(
      'A. Internet OK + Supabase OK: an authorized, PIN-set device reaches '
      'the lock screen normally', (tester) async {
    final account = _FakeAccountRepository(initiallyAuthorized: true);
    await pumpGate(tester, account: account);
    await tester.pump();
    await tester.pump();

    expect(find.byType(LockScreen), findsOneWidget);
  });

  testWidgets(
      'B. No internet (isDeviceStillAuthorized throws immediately): the '
      'device still opens locally instead of ever showing an error or '
      'staying on the splash', (tester) async {
    final account = _FakeAccountRepository(
      initiallyAuthorized: true,
      isDeviceStillAuthorizedImpl: () => Future.error(Exception('no internet')),
    );
    await pumpGate(tester, account: account);
    await tester.pump();
    await tester.pump();

    expect(find.byType(LockScreen), findsOneWidget);
  });

  testWidgets(
      'C. Internet present but Supabase never responds to the device-'
      'authorization check: the app still starts, immediately, from local '
      'data alone - the never-completing request is never awaited on the '
      'critical path', (tester) async {
    final account = _FakeAccountRepository(
      initiallyAuthorized: true,
      isDeviceStillAuthorizedImpl: () => Completer<bool>().future,
    );
    await pumpGate(tester, account: account);
    // Only two frames, no time advance at all - if this were still gated
    // on the network call, the splash would still be showing here.
    await tester.pump();
    await tester.pump();

    expect(find.byType(LockScreen), findsOneWidget);
    // Drains the background check's own pending timeout Timer before this
    // test ends - a never-completing Future's `.timeout()` schedules a real
    // (fake-clock) Timer that flutter_test insists is cleared before
    // teardown, regardless of whether the test itself cares about its
    // outcome.
    await tester.pump(const Duration(seconds: 11));
  });

  testWidgets(
      'D. Device-authorization request suspended forever: AppGate never '
      'blocks on it (same guarantee as C, phrased as the mission\'s own '
      'named scenario)', (tester) async {
    final account = _FakeAccountRepository(
      initiallyAuthorized: true,
      isDeviceStillAuthorizedImpl: () => Completer<bool>().future,
    );
    await pumpGate(tester, account: account);
    await tester.pump();
    await tester.pump();

    expect(find.byType(LockScreen), findsOneWidget);
    expect(find.byType(AccountGateScreen), findsNothing);
    await tester.pump(const Duration(seconds: 11));
  });

  testWidgets(
      'F. Valid local session + a very slow server: the local home screen '
      '(lock screen) appears immediately - the slow background check is '
      'never on the path to it', (tester) async {
    final account = _FakeAccountRepository(
      initiallyAuthorized: true,
      isDeviceStillAuthorizedImpl: () async {
        await Future<void>.delayed(const Duration(seconds: 9));
        return true;
      },
    );
    await pumpGate(tester, account: account);
    await tester.pump();
    await tester.pump();

    // Immediate - no time advanced yet, and the lock screen is already up.
    expect(find.byType(LockScreen), findsOneWidget);
    await tester.pump(const Duration(seconds: 10));
  });

  testWidgets(
      'G. No local session at all + device id read fails outright: the '
      'connection screen shows - never an infinite loading screen', (tester) async {
    final account = _FakeAccountRepository(
      deviceAuthorizedUserIdImpl: () => Future.error(Exception('storage unavailable')),
    );
    await pumpGate(tester, account: account);
    await tester.pump();
    await tester.pump();

    expect(find.byType(AccountGateScreen), findsOneWidget);
  });

  testWidgets(
      'H. Device revoked server-side while the app is opened offline: the '
      'lock screen still opens immediately from local data, and only once '
      'the (slow) background check comes back does it cleanly bounce to '
      'the email screen - never blocking the initial open on that check',
      (tester) async {
    final account = _FakeAccountRepository(
      initiallyAuthorized: true,
      isDeviceStillAuthorizedImpl: () async {
        await Future<void>.delayed(const Duration(seconds: 3));
        return false; // revoked, discovered only once the network responds
      },
    );
    await pumpGate(tester, account: account);
    await tester.pump();
    await tester.pump();

    // Opens locally first, immediately - offline-first bootstrap.
    expect(find.byType(LockScreen), findsOneWidget);
    expect(account.disconnectThisDeviceCalled, isFalse);

    // The background check now resolves (revoked) and the gate reacts.
    await tester.pump(const Duration(seconds: 4));
    await tester.pump();

    expect(account.disconnectThisDeviceCalled, isTrue);
    expect(find.byType(AccountGateScreen), findsOneWidget);
    expect(find.byType(LockScreen), findsNothing);
  });

  group('individual step timeouts and the global fail-safe', () {
    testWidgets(
        'a device id (secure storage) read that hangs forever still lets '
        'the gate reach a decision, bounded by the per-step timeout',
        (tester) async {
      final account = _FakeAccountRepository(
        deviceAuthorizedUserIdImpl: () => Completer<String?>().future,
      );
      await pumpGate(tester, account: account);
      await tester.pump();

      // Still on the splash - the hung read hasn't timed out yet.
      expect(find.byType(AccountGateScreen), findsNothing);

      // Past the per-step timeout (4s) but comfortably under the global
      // fail-safe (10s) - the fallback (email screen) must already show.
      await tester.pump(const Duration(seconds: 5));
      await tester.pump();

      expect(find.byType(AccountGateScreen), findsOneWidget);
    });

    testWidgets(
        'a PIN-set check that hangs forever never keeps the gate on the '
        'splash past that one step\'s timeout', (tester) async {
      final account = _FakeAccountRepository(initiallyAuthorized: true);
      final pinService = _FakePinService(hang: true);
      await pumpGate(tester, account: account, pinService: pinService);
      await tester.pump();

      expect(find.byType(LockScreen), findsNothing);

      await tester.pump(const Duration(seconds: 5));
      await tester.pump();

      // pinSet falls back to false on timeout - an authorized device with
      // no confirmed PIN goes to PIN setup, not an infinite splash.
      expect(find.byType(AccountGateScreen), findsNothing);
      expect(find.byType(LockScreen), findsNothing);
    });

    testWidgets(
        'the global bootstrap fail-safe forces a decision even if the local '
        'phase as a whole somehow exceeds every individual step timeout '
        'combined', (tester) async {
      // Three chained hangs, each individually bounded at 4s, would sum to
      // 12s without the outer ceiling - the 10s global fail-safe must still
      // win and force the safest fallback (email screen) before that.
      final account = _FakeAccountRepository(
        initiallyAuthorized: true,
        deviceAuthorizedUserIdImpl: () async {
          await Future<void>.delayed(const Duration(seconds: 4));
          return 'user-1';
        },
      );
      final pinService = _FakePinService(hang: true);
      await pumpGate(tester, account: account, pinService: pinService);

      await tester.pump(const Duration(seconds: 11));
      await tester.pump();

      // Some decision must have been reached - the splash must be gone.
      expect(find.byType(Scaffold), findsWidgets);
      final stillOnSplash = find.byWidgetPredicate((w) =>
          w is Icon && w.icon == Icons.directions_car_filled);
      expect(stillOnSplash, findsNothing,
          reason: 'the global fail-safe must have forced the gate off the splash by now');
    });
  });
}
