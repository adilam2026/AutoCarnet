import 'package:autocarnet/features/account/data/account_repository.dart';
import 'package:autocarnet/features/account/presentation/account_gate_screen.dart';
import 'package:autocarnet/features/account/presentation/email_entry_screen.dart';
import 'package:autocarnet/features/account/presentation/verify_email_screen.dart';
import 'package:autocarnet/features/onboarding_lock/data/biometric_service.dart';
import 'package:autocarnet/features/onboarding_lock/data/pin_service.dart';
import 'package:autocarnet/features/onboarding_lock/presentation/app_gate.dart';
import 'package:autocarnet/features/onboarding_lock/presentation/lock_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Regression coverage for three historical auth/session bugs that had no
/// test exercising the real [AppGate] end to end:
///
/// 1. A token/session that vanishes the instant after a "successful" OTP
///    verification (Supabase accepted the code, but `currentUser` is
///    already null by the time the post-auth chain runs) used to crash
///    with an unhandled null-check `TypeError`, leaving the user stuck on
///    a screen with an already-consumed code and no way to retry except
///    starting completely over.
/// 2. A logout ("Déconnecter tous les appareils" / "Dissocier ce compte")
///    bumping its request provider was only ever proven to bump a counter
///    (see account_management_ux_test.dart) - never that [AppGate] itself
///    reacts by genuinely revoking access: leaving the lock screen,
///    clearing the stored PIN, and calling into the account repository.
/// 3. "Changer de compte" must hand back a genuinely empty email field -
///    never one pre-filled with the previous account's address.
///
/// All three drive the real [AppGate] widget (not a lookalike), the same
/// class that shipped every one of these bugs.
class _FakeAccountRepository implements AccountRepository {
  _FakeAccountRepository({this.initiallyAuthorized = false})
      : _currentUser = initiallyAuthorized
            ? User(
                id: 'user-1',
                appMetadata: const {},
                userMetadata: null,
                aud: 'authenticated',
                email: 'a@example.com',
                createdAt: DateTime.now().toIso8601String(),
              )
            : null;

  bool initiallyAuthorized;
  User? _currentUser;
  bool disconnectThisDeviceCalled = false;
  bool disconnectAllDevicesCalled = false;
  final List<String> sentCodes = [];

  /// When true, [verifyEmailCode] succeeds (Supabase accepted the code)
  /// but [currentUser] stays null - the exact "token expired the instant
  /// after success" shape.
  bool sessionVanishesAfterVerify = false;

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
  Future<void> sendEmailCode(String email) async => sentCodes.add(email);
  @override
  Future<void> verifyEmailCode({required String email, required String code}) async {
    if (!sessionVanishesAfterVerify) {
      _currentUser = User(
        id: 'user-1',
        appMetadata: const {},
        userMetadata: null,
        aud: 'authenticated',
        email: email,
        createdAt: DateTime.now().toIso8601String(),
      );
    }
    // else: Supabase reports success (no throw) but the session is gone -
    // currentUser stays null.
  }

  @override
  Future<String> installationId() async => 'test-device';
  @override
  Future<String?> deviceAuthorizedUserId() async => initiallyAuthorized ? 'user-1' : null;
  @override
  Future<String?> lastDeviceUserId() async => initiallyAuthorized ? 'user-1' : null;
  @override
  Future<String?> deviceAuthorizedEmail() async => initiallyAuthorized ? 'a@example.com' : null;
  @override
  Future<void> registerThisDevice() async {}
  @override
  Future<bool> isDeviceStillAuthorized({required String userId}) async => true;
  @override
  Future<List<AuthorizedDevice>> listMyDevices() async => const [];
  @override
  Future<void> revokeDevice(String deviceRowId) async {}
  @override
  Future<void> disconnectFromThisDevice() async {
    disconnectThisDeviceCalled = true;
    initiallyAuthorized = false;
    _currentUser = null;
  }

  @override
  Future<void> disconnectFromAllDevices() async {
    disconnectAllDevicesCalled = true;
    initiallyAuthorized = false;
    _currentUser = null;
  }
}

class _FakePinService implements PinService {
  final Map<String, String> pins = {'user-1': '9999'};
  @override
  Future<bool> isPinSet(String accountId) async => pins.containsKey(accountId);
  @override
  Future<void> setPin(String accountId, String pin) async => pins[accountId] = pin;
  @override
  Future<bool> verifyPin(String accountId, String pin) async => pins[accountId] == pin;
  @override
  Future<void> clearPin(String accountId) async => pins.remove(accountId);
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
    required _FakePinService pinService,
  }) async {
    final container = ProviderContainer(overrides: [
      accountRepositoryProvider.overrideWithValue(account),
      pinServiceProvider.overrideWithValue(pinService),
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
    // initState's postFrameCallback runs _evaluate(), which awaits fake
    // repository calls - settle it fully before assertions.
    await tester.pumpAndSettle();
    return container;
  }

  group('token expired right after a successful OTP verification', () {
    testWidgets(
        'never crashes and never strands the user: shows a friendly "session expirée" error '
        'and re-enables the form for a genuine retry (regression: unguarded currentUser!.id '
        'null-check crash left an already-consumed code with no way to retry)', (tester) async {
      final account = _FakeAccountRepository()..sessionVanishesAfterVerify = true;
      final pinService = _FakePinService();
      await pumpGate(tester, account: account, pinService: pinService);

      expect(find.byType(EmailEntryScreen), findsOneWidget);
      await tester.enterText(find.widgetWithText(TextField, 'Adresse email'), 'a@example.com');
      await tester.tap(find.text('Continuer'));
      await tester.pumpAndSettle();

      expect(find.byType(VerifyEmailScreen), findsOneWidget);
      await tester.enterText(find.widgetWithText(TextField, 'Code de vérification'), '123456');
      await tester.tap(find.text('Vérifier'));
      await tester.pumpAndSettle();

      // No crash: still on the verify screen (never AppGate's home/unlocked
      // state), with a message the user can act on, and the form usable
      // again - not permanently stuck mid-spinner.
      expect(find.byType(VerifyEmailScreen), findsOneWidget);
      expect(find.text('Votre session a expiré. Veuillez réessayer.'), findsOneWidget);
      expect(find.text('Vérifier'), findsOneWidget, reason: 'the button must be re-enabled, not stuck busy');
    });
  });

  group('logout genuinely revokes access', () {
    testWidgets(
        '"Déconnecter tous les appareils" makes AppGate leave the lock screen, clear the '
        'stored PIN and call into the account repository - not just bump a counter nobody '
        'consumes (regression: logout could leave the previous session reachable)',
        (tester) async {
      final account = _FakeAccountRepository(initiallyAuthorized: true);
      final pinService = _FakePinService();
      final container = await pumpGate(tester, account: account, pinService: pinService);

      expect(find.byType(LockScreen), findsOneWidget);
      expect(await pinService.isPinSet('user-1'), isTrue);

      // The confirmation-dialog -> bump flow itself is already covered by
      // account_management_ux_test.dart; this proves AppGate's reaction to
      // the resulting bump, which nothing previously exercised.
      container.read(accountDisconnectEverywhereRequestProvider.notifier).state++;
      await tester.pumpAndSettle();

      expect(find.byType(LockScreen), findsNothing,
          reason: 'logout must genuinely revoke access, not leave the previous session on screen');
      expect(find.byType(AccountGateScreen), findsOneWidget);
      expect(account.disconnectAllDevicesCalled, isTrue);
      expect(await pinService.isPinSet('user-1'), isFalse,
          reason: 'a stale PIN must never survive a logout and re-grant access next time');
    });

    testWidgets('"Dissocier ce compte de cet appareil" has the exact same effect for this device',
        (tester) async {
      final account = _FakeAccountRepository(initiallyAuthorized: true);
      final pinService = _FakePinService();
      final container = await pumpGate(tester, account: account, pinService: pinService);

      container.read(accountDissociateRequestProvider.notifier).state++;
      await tester.pumpAndSettle();

      expect(find.byType(LockScreen), findsNothing);
      expect(find.byType(AccountGateScreen), findsOneWidget);
      expect(account.disconnectThisDeviceCalled, isTrue);
      expect(await pinService.isPinSet('user-1'), isFalse);
    });
  });

  group('"Changer de compte" never pre-fills the next email field', () {
    testWidgets(
        'the email screen reached after switching accounts starts genuinely empty - never '
        'reinjecting the previous account\'s address', (tester) async {
      final account = _FakeAccountRepository(initiallyAuthorized: true);
      final pinService = _FakePinService();
      final container = await pumpGate(tester, account: account, pinService: pinService);

      expect(find.byType(LockScreen), findsOneWidget);

      container.read(accountSwitchRequestProvider.notifier).state++;
      await tester.pumpAndSettle();

      expect(find.byType(EmailEntryScreen), findsOneWidget);
      final field = tester.widget<TextField>(find.widgetWithText(TextField, 'Adresse email'));
      expect(field.controller!.text, isEmpty,
          reason: 'must never show the previous account\'s email pre-filled');
    });
  });
}
