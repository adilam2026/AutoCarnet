import 'package:autocarnet/features/account/data/account_repository.dart';
import 'package:autocarnet/features/onboarding_lock/data/biometric_service.dart';
import 'package:autocarnet/features/onboarding_lock/data/pin_service.dart';
import 'package:autocarnet/features/onboarding_lock/presentation/lock_screen.dart';
import 'package:autocarnet/features/onboarding_lock/presentation/pin_recovery_screen.dart';
import 'package:autocarnet/features/onboarding_lock/presentation/pin_setup_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Per-account, in-memory - mirrors the real PinService's contract (spec
/// TEST F: account A's PIN must never open account B's data).
class FakePinService implements PinService {
  final Map<String, String> _pins = {};

  @override
  Future<bool> isPinSet(String accountId) async => _pins.containsKey(accountId);
  @override
  Future<void> setPin(String accountId, String pin) async => _pins[accountId] = pin;
  @override
  Future<bool> verifyPin(String accountId, String pin) async => _pins[accountId] == pin;
  @override
  Future<void> clearPin(String accountId) async => _pins.remove(accountId);
}

class FakeBiometricService implements BiometricService {
  final Set<String> _enabled = {};

  @override
  Future<bool> isDeviceSupported() async => false;
  @override
  Future<bool> isEnabled(String accountId) async => _enabled.contains(accountId);
  @override
  Future<void> setEnabled(String accountId, bool enabled) async {
    enabled ? _enabled.add(accountId) : _enabled.remove(accountId);
  }

  @override
  Future<bool> authenticate() async => false;
}

class FakeAccountRepositoryForRecovery implements AccountRepository {
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

void main() {
  group('PinSetupScreen', () {
    testWidgets('a matching 4-6 digit PIN is saved and calls onDone - no skip option exists',
        (tester) async {
      final pinService = FakePinService();
      var done = false;
      await tester.pumpWidget(
        ProviderScope(
          overrides: [pinServiceProvider.overrideWithValue(pinService)],
          child: MaterialApp(home: PinSetupScreen(accountId: 'user-1', onDone: () => done = true)),
        ),
      );

      expect(find.textContaining('Passer'), findsNothing);

      await tester.enterText(find.widgetWithText(TextField, 'Code (4 à 6 chiffres)'), '4321');
      await tester.enterText(find.widgetWithText(TextField, 'Confirmer le code'), '4321');
      await tester.tap(find.text('Activer le code'));
      // Not pumpAndSettle: on success the button is deliberately left
      // showing its indeterminate spinner (the screen is about to be
      // replaced by the caller) - that animates forever, so pumpAndSettle
      // would never settle.
      await tester.pump();
      await tester.pump();

      expect(await pinService.isPinSet('user-1'), isTrue);
      expect(await pinService.verifyPin('user-1', '4321'), isTrue);
      expect(done, isTrue);
    });

    testWidgets('mismatched codes show an error and never call onDone', (tester) async {
      final pinService = FakePinService();
      var done = false;
      await tester.pumpWidget(
        ProviderScope(
          overrides: [pinServiceProvider.overrideWithValue(pinService)],
          child: MaterialApp(home: PinSetupScreen(accountId: 'user-1', onDone: () => done = true)),
        ),
      );

      await tester.enterText(find.widgetWithText(TextField, 'Code (4 à 6 chiffres)'), '1111');
      await tester.enterText(find.widgetWithText(TextField, 'Confirmer le code'), '2222');
      await tester.tap(find.text('Activer le code'));
      await tester.pump();

      expect(find.text('Les deux codes ne correspondent pas'), findsOneWidget);
      expect(done, isFalse);
      expect(await pinService.isPinSet('user-1'), isFalse);
    });
  });

  group('LockScreen', () {
    Future<FakePinService> pumpLocked(
      WidgetTester tester, {
      String accountId = 'user-1',
      String? email,
      VoidCallback? onUnlocked,
      VoidCallback? onForgotCode,
      VoidCallback? onSwitchAccount,
    }) async {
      final pinService = FakePinService();
      await pinService.setPin(accountId, '9999');
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            pinServiceProvider.overrideWithValue(pinService),
            biometricServiceProvider.overrideWithValue(FakeBiometricService()),
          ],
          child: MaterialApp(
            home: LockScreen(
              accountId: accountId,
              email: email,
              onUnlocked: onUnlocked ?? () {},
              onForgotCode: onForgotCode ?? () {},
              onSwitchAccount: onSwitchAccount ?? () {},
            ),
          ),
        ),
      );
      return pinService;
    }

    testWidgets('shows "Bienvenue {email}" and the correct PIN unlocks', (tester) async {
      var unlocked = false;
      await pumpLocked(tester, email: 'a@example.com', onUnlocked: () => unlocked = true);

      expect(find.text('a@example.com'), findsOneWidget);

      await tester.enterText(find.widgetWithText(TextField, 'Code d\'accès'), '9999');
      await tester.tap(find.text('Déverrouiller'));
      await tester.pumpAndSettle();

      expect(unlocked, isTrue);
    });

    testWidgets('a wrong PIN shows an error and never unlocks', (tester) async {
      var unlocked = false;
      await pumpLocked(tester, onUnlocked: () => unlocked = true);

      await tester.enterText(find.widgetWithText(TextField, 'Code d\'accès'), '0000');
      await tester.tap(find.text('Déverrouiller'));
      await tester.pumpAndSettle();

      expect(find.text('Code incorrect'), findsOneWidget);
      expect(unlocked, isFalse);
    });

    testWidgets('spec TEST F: account A\'s PIN never unlocks account B\'s lock screen',
        (tester) async {
      // Both A and B have PINs set on this device (pumpLocked sets '9999'
      // for whichever accountId it's given) but B's screen is showing.
      final pinService = FakePinService();
      await pinService.setPin('user-A', '1111');
      await pinService.setPin('user-B', '2222');
      var unlocked = false;
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            pinServiceProvider.overrideWithValue(pinService),
            biometricServiceProvider.overrideWithValue(FakeBiometricService()),
          ],
          child: MaterialApp(
            home: LockScreen(
              accountId: 'user-B',
              email: 'b@example.com',
              onUnlocked: () => unlocked = true,
              onForgotCode: () {},
              onSwitchAccount: () {},
            ),
          ),
        ),
      );

      // A's PIN must not open B's screen.
      await tester.enterText(find.widgetWithText(TextField, 'Code d\'accès'), '1111');
      await tester.tap(find.text('Déverrouiller'));
      await tester.pumpAndSettle();
      expect(unlocked, isFalse);

      // B's own PIN does.
      await tester.enterText(find.widgetWithText(TextField, 'Code d\'accès'), '2222');
      await tester.tap(find.text('Déverrouiller'));
      await tester.pumpAndSettle();
      expect(unlocked, isTrue);
    });

    testWidgets('"Code oublié ?" asks for confirmation, then calls onForgotCode', (tester) async {
      var forgotCalled = false;
      await pumpLocked(tester, onForgotCode: () => forgotCalled = true);

      await tester.tap(find.text('Code oublié ?'));
      await tester.pumpAndSettle();
      expect(forgotCalled, isFalse, reason: 'must ask for confirmation first');

      await tester.tap(find.text('Continuer'));
      await tester.pumpAndSettle();
      expect(forgotCalled, isTrue);
    });

    testWidgets('"Changer de compte" asks for confirmation, then calls onSwitchAccount',
        (tester) async {
      var switchCalled = false;
      await pumpLocked(tester, onSwitchAccount: () => switchCalled = true);

      await tester.tap(find.text('Changer de compte'));
      await tester.pumpAndSettle();
      expect(switchCalled, isFalse, reason: 'must ask for confirmation first');

      await tester.tap(find.widgetWithText(FilledButton, 'Changer de compte'));
      await tester.pumpAndSettle();
      expect(switchCalled, isTrue);
    });
  });

  group('PinRecoveryScreen', () {
    testWidgets(
        'sends an OTP to the already-known email (no email re-entry), then a correct code '
        'leads to a mandatory new PIN with no skip option', (tester) async {
      final account = FakeAccountRepositoryForRecovery();
      final pinService = FakePinService();
      var done = false;
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            accountRepositoryProvider.overrideWithValue(account),
            pinServiceProvider.overrideWithValue(pinService),
          ],
          child: MaterialApp(
            home: PinRecoveryScreen(
              accountId: 'user-1',
              email: 'a@example.com',
              onDone: () => done = true,
              onCancel: () {},
            ),
          ),
        ),
      );
      // Not pumpAndSettle anywhere in this test: a successful OTP send
      // starts a 30-tick resend-cooldown Timer.periodic that keeps running
      // for the rest of this screen's lifetime (not just while the OTP
      // step is showing), and the final "Activer le code" tap leaves an
      // indeterminate spinner up on purpose - either alone is enough to
      // make pumpAndSettle never find a moment with no scheduled frames.
      await tester.pump();
      await tester.pump();

      expect(account.sentEmails, ['a@example.com']);
      expect(find.textContaining('Adresse email'), findsNothing,
          reason: 'the account is already known, no email field should appear');

      await tester.enterText(find.widgetWithText(TextField, 'Code de vérification'), '654321');
      await tester.tap(find.text('Vérifier'));
      await tester.pump();
      await tester.pump();

      expect(find.byType(PinSetupScreen), findsOneWidget);
      expect(find.textContaining('Passer'), findsNothing);

      await tester.enterText(find.widgetWithText(TextField, 'Code (4 à 6 chiffres)'), '5555');
      await tester.enterText(find.widgetWithText(TextField, 'Confirmer le code'), '5555');
      await tester.tap(find.text('Activer le code'));
      await tester.pump();
      await tester.pump();

      expect(done, isTrue);
      expect(await pinService.verifyPin('user-1', '5555'), isTrue);
    });
  });
}
