import 'package:autocarnet/features/account/data/account_repository.dart';
import 'package:autocarnet/features/account/presentation/account_gate_screen.dart';
import 'package:autocarnet/features/onboarding_lock/data/biometric_service.dart';
import 'package:autocarnet/features/onboarding_lock/data/pin_service.dart';
import 'package:autocarnet/features/onboarding_lock/presentation/lock_screen.dart';
import 'package:autocarnet/features/onboarding_lock/presentation/pin_recovery_screen.dart';
import 'package:autocarnet/features/onboarding_lock/presentation/pin_setup_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Regression coverage for a real bug found on a real device: "Code oublié
/// ?" and "Changer de compte", from the lock screen, opened their
/// confirmation dialog correctly and the underlying app state (`_step` in
/// AppGate) genuinely changed - but the screen never visibly moved on,
/// staying frozen on the lock screen forever.
///
/// Root cause: AppGate renders every pre-unlock step through the exact same
/// widget shape (a stateless wrapper around a bare
/// `Navigator(onGenerateRoute: ...)`), with no `key` distinguishing one
/// step's wrapper from another's. Since Flutter's element diffing matches
/// by (runtimeType, key), and every step produced the identical
/// (runtimeType, key=null) pair, a transition between two pre-unlock steps
/// was treated as an *update* of the same Element rather than a fresh
/// mount - and a bare Navigator's `onGenerateRoute` is only ever consulted
/// for its *initial* route, so the Navigator kept showing whatever screen
/// it first mounted, no matter how many times the outer step changed
/// afterwards. The very first transition after a cold start (`_Splash` ->
/// a real step) was never affected, since `_Splash` is a different widget
/// type - which is exactly why this shipped unnoticed: the initial
/// email->OTP->PIN-setup->locked journey worked, but *any subsequent*
/// transition between two pre-unlock steps within the same running
/// session (locked -> pinRecovery, locked -> email, ...) silently did
/// nothing visible.
///
/// Fixed by giving each step's wrapper a distinct key (see app_gate.dart's
/// `_GateNavigator(key: const ValueKey(_GateStep...), ...)`), forcing a
/// genuine remount - and therefore a fresh `onGenerateRoute` call - on
/// every transition. This test reproduces the exact same structural shape
/// (a keyed, per-step wrapper around a bare Navigator, inside
/// MaterialApp.router's `builder`) driving the *real* LockScreen/
/// PinRecoveryScreen/PinSetupScreen/AccountGateScreen widgets through
/// actual transitions - not just checking that a callback fires in
/// isolation, which alone would never have caught this.

class _FakeAccountRepository implements AccountRepository {
  final List<String> sentEmails = [];
  String expectedCode = '654321';

  @override
  User? get currentUser => null;
  @override
  Session? get currentSession => null;
  @override
  bool get isSignedIn => true;
  @override
  Stream<AuthState> get onAuthStateChange => const Stream.empty();
  @override
  Future<String?> tryRestoreDeviceSession(String email) async => null;
  @override
  Future<void> sendEmailCode(String email) async => sentEmails.add(email);
  @override
  Future<void> verifyEmailCode({required String email, required String code}) async {
    if (code.trim() != expectedCode) throw AuthException('Code incorrect');
  }

  @override
  Future<String> installationId() async => 'test-device';
  @override
  Future<String?> deviceAuthorizedUserId() async => 'user-1';
  @override
  Future<String?> lastDeviceUserId() async => 'user-1';
  @override
  Future<String?> deviceAuthorizedEmail() async => 'a@example.com';
  @override
  Future<void> registerThisDevice() async {}
  @override
  Future<bool> isDeviceStillAuthorized({required String userId}) async => true;
  @override
  Future<List<AuthorizedDevice>> listMyDevices() async => const [];
  @override
  Future<void> revokeDevice(String deviceRowId) async {}
  @override
  Future<void> disconnectFromThisDevice() async {}
  @override
  Future<void> disconnectFromAllDevices() async {}
}

class _FakePinService implements PinService {
  final Map<String, String> _pins = {'user-1': '9999'};
  @override
  Future<bool> isPinSet(String accountId) async => _pins.containsKey(accountId);
  @override
  Future<void> setPin(String accountId, String pin) async => _pins[accountId] = pin;
  @override
  Future<bool> verifyPin(String accountId, String pin) async => _pins[accountId] == pin;
  @override
  Future<void> clearPin(String accountId) async => _pins.remove(accountId);
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

enum _Step { locked, pinRecovery, email, home }

/// The exact structural shape of AppGate's real render tree - a switch
/// over the current step, each pre-unlock branch wrapped in a keyed
/// stateless helper around a bare Navigator, rendered from
/// MaterialApp.router's `builder`.
class _GateLikeWrapper extends StatelessWidget {
  const _GateLikeWrapper({super.key, required this.child});
  final Widget child;
  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      child: Navigator(
        onGenerateRoute: (settings) => MaterialPageRoute(builder: (_) => child),
      ),
    );
  }
}

class _Harness extends StatefulWidget {
  const _Harness({required this.account, required this.pinService});
  final _FakeAccountRepository account;
  final _FakePinService pinService;
  @override
  State<_Harness> createState() => _HarnessState();
}

class _HarnessState extends State<_Harness> {
  _Step _step = _Step.locked;

  @override
  Widget build(BuildContext context) {
    final router = GoRouter(
      initialLocation: '/',
      routes: [GoRoute(path: '/', builder: (context, state) => const SizedBox.shrink())],
    );
    return ProviderScope(
      overrides: [
        accountRepositoryProvider.overrideWithValue(widget.account),
        pinServiceProvider.overrideWithValue(widget.pinService),
        biometricServiceProvider.overrideWithValue(_FakeBiometricService()),
      ],
      child: MaterialApp.router(
        routerConfig: router,
        builder: (context, child) => switch (_step) {
          _Step.locked => _GateLikeWrapper(
              key: const ValueKey(_Step.locked),
              child: LockScreen(
                accountId: 'user-1',
                email: 'a@example.com',
                onUnlocked: () => setState(() => _step = _Step.home),
                onForgotCode: () => setState(() => _step = _Step.pinRecovery),
                onSwitchAccount: () => setState(() => _step = _Step.email),
              ),
            ),
          _Step.pinRecovery => _GateLikeWrapper(
              key: const ValueKey(_Step.pinRecovery),
              child: PinRecoveryScreen(
                accountId: 'user-1',
                email: 'a@example.com',
                onDone: () => setState(() => _step = _Step.home),
                onCancel: () => setState(() => _step = _Step.locked),
              ),
            ),
          _Step.email => _GateLikeWrapper(
              key: const ValueKey(_Step.email),
              child: AccountGateScreen(onAuthenticated: () async {}),
            ),
          _Step.home => const Scaffold(body: Center(child: Text('ACCUEIL'))),
        },
      ),
    );
  }
}

void main() {
  testWidgets(
      'TEST A/C - from the lock screen, both "Code oublié ?" and "Changer de compte" actually '
      'navigate to their target screen, not just fire a callback into a frozen screen',
      (tester) async {
    final account = _FakeAccountRepository();
    final pinService = _FakePinService();
    await tester.pumpWidget(_Harness(account: account, pinService: pinService));

    // TEST A: Code oublié -> confirmation -> the OTP screen must actually
    // appear, not leave the lock screen sitting underneath forever.
    await tester.tap(find.text('Code oublié ?'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Continuer'));
    await tester.pumpAndSettle();

    expect(find.byType(LockScreen), findsNothing,
        reason: 'the lock screen must be gone, not frozen underneath the closed dialog');
    expect(find.byType(PinRecoveryScreen), findsOneWidget);
    expect(account.sentEmails, ['a@example.com']);
  });

  testWidgets('TEST B - OTP correct -> new PIN screen -> creating a PIN reaches ACCUEIL',
      (tester) async {
    final account = _FakeAccountRepository();
    final pinService = _FakePinService();
    await tester.pumpWidget(_Harness(account: account, pinService: pinService));

    await tester.tap(find.text('Code oublié ?'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Continuer'));
    await tester.pumpAndSettle();

    await tester.enterText(find.widgetWithText(TextField, 'Code de vérification'), '654321');
    await tester.tap(find.text('Vérifier'));
    await tester.pump();
    await tester.pump();

    expect(find.byType(PinSetupScreen), findsOneWidget);

    await tester.enterText(find.widgetWithText(TextField, 'Code (4 à 6 chiffres)'), '1234');
    await tester.enterText(find.widgetWithText(TextField, 'Confirmer le code'), '1234');
    await tester.tap(find.text('Activer le code'));
    await tester.pump();
    await tester.pump();

    expect(find.text('ACCUEIL'), findsOneWidget);
    expect(await pinService.verifyPin('user-1', '1234'), isTrue);
  });

  testWidgets(
      'TEST C/D - from the lock screen, "Changer de compte" actually navigates to the email '
      'screen, and the previous account\'s lock screen is fully gone (nothing to go back to)',
      (tester) async {
    final account = _FakeAccountRepository();
    final pinService = _FakePinService();
    await tester.pumpWidget(_Harness(account: account, pinService: pinService));

    await tester.tap(find.text('Changer de compte'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Changer de compte'));
    await tester.pumpAndSettle();

    expect(find.byType(LockScreen), findsNothing,
        reason: 'the previous account\'s lock screen must be gone, not frozen underneath');
    expect(find.byType(AccountGateScreen), findsOneWidget);
    expect(find.byKey(const Key('email-field')), findsOneWidget);
  });
}
