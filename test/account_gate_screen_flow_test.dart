import 'package:autocarnet/features/account/data/account_repository.dart';
import 'package:autocarnet/features/account/presentation/account_gate_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// A fully in-memory stand-in for [AccountRepository] - no Supabase network
/// call, no secure storage - so the real [AccountGateScreen]/
/// [EmailEntryScreen]/[VerifyEmailScreen] widgets can be driven through a
/// complete email -> OTP journey deterministically.
class FakeAccountRepository implements AccountRepository {
  final List<String> sentEmails = [];
  int verifyCallCount = 0;
  int restoreCallCount = 0;
  String expectedCode = '123456';
  bool _signedIn = false;
  User? _user;

  /// Emails this fake device already knows (spec CAS 3) - a submit for one
  /// of these must skip OTP entirely, exactly like a real
  /// tryRestoreDeviceSession success.
  final Set<String> knownEmails = {};

  /// Known emails whose device association has since been revoked (spec
  /// TEST E) - tryRestoreDeviceSession must behave exactly as if the email
  /// were never known at all, falling through to a real OTP.
  final Set<String> revokedEmails = {};

  User _userFor(String email) => User(
        id: 'user-$email',
        appMetadata: const {},
        userMetadata: null,
        aud: 'authenticated',
        email: email,
        createdAt: DateTime.now().toIso8601String(),
      );

  @override
  User? get currentUser => _user;
  @override
  Session? get currentSession => null;
  @override
  bool get isSignedIn => _signedIn;
  @override
  Stream<AuthState> get onAuthStateChange => const Stream.empty();

  @override
  Future<String?> tryRestoreDeviceSession(String email) async {
    restoreCallCount++;
    if (!knownEmails.contains(email) || revokedEmails.contains(email)) return null;
    _signedIn = true;
    _user = _userFor(email);
    return _user!.id;
  }

  @override
  Future<void> sendEmailCode(String email) async {
    sentEmails.add(email);
  }

  @override
  Future<void> verifyEmailCode({required String email, required String code}) async {
    verifyCallCount++;
    if (code.trim() != expectedCode) {
      throw AuthException('Code incorrect');
    }
    _signedIn = true;
    _user = _userFor(email);
  }

  @override
  Future<String> installationId() async => 'test-device';
  @override
  Future<String?> deviceAuthorizedUserId() async => null;
  @override
  Future<String?> lastDeviceUserId() async => null;
  @override
  Future<String?> deviceAuthorizedEmail() async => null;
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
    _signedIn = false;
    _user = null;
  }

  @override
  Future<void> disconnectFromAllDevices() async {
    _signedIn = false;
    _user = null;
  }
}

void main() {
  late FakeAccountRepository fake;
  int authenticatedCallCount = 0;

  Future<void> pump(WidgetTester tester) async {
    fake = FakeAccountRepository();
    authenticatedCallCount = 0;
    await tester.pumpWidget(
      ProviderScope(
        overrides: [accountRepositoryProvider.overrideWithValue(fake)],
        child: MaterialApp(
          home: AccountGateScreen(
            onAuthenticated: () async {
              authenticatedCallCount++;
            },
          ),
        ),
      ),
    );
  }

  testWidgets('a fresh device shows only an email field - no name field, no offline escape hatch',
      (tester) async {
    await pump(tester);

    expect(find.widgetWithText(TextField, 'Adresse email'), findsOneWidget);
    expect(find.byType(TextField), findsOneWidget);
    expect(find.textContaining('Nom'), findsNothing);
    expect(find.textContaining('hors connexion'), findsNothing);
  });

  testWidgets(
      'email -> OTP -> success is a single straight line: one send, one verify, never a bounce '
      'back to the email screen', (tester) async {
    await pump(tester);

    await tester.enterText(find.widgetWithText(TextField, 'Adresse email'), 'user@example.com');
    await tester.tap(find.text('Continuer'));
    await tester.pumpAndSettle();

    expect(fake.sentEmails, ['user@example.com']);
    expect(find.widgetWithText(TextField, 'Adresse email'), findsNothing,
        reason: 'the email screen must be fully replaced, not shown alongside the OTP screen');
    expect(find.text('Vérifiez votre email'), findsOneWidget);

    await tester.enterText(find.widgetWithText(TextField, 'Code de vérification'), '123456');
    await tester.tap(find.text('Vérifier'));
    // Not pumpAndSettle: on success the button is deliberately left showing
    // its indeterminate spinner forever (the screen is about to be
    // replaced by the caller, see VerifyEmailScreen's class doc) - an
    // indeterminate CircularProgressIndicator animates forever, so
    // pumpAndSettle would never find a moment with no scheduled frames.
    await tester.pump();
    await tester.pump();

    expect(fake.verifyCallCount, 1);
    expect(authenticatedCallCount, 1);
    expect(find.widgetWithText(TextField, 'Adresse email'), findsNothing,
        reason: 'a successful OTP must never bounce back to the email screen');
  });

  testWidgets('a wrong code shows an error and stays on the OTP screen - never bounces back',
      (tester) async {
    await pump(tester);

    await tester.enterText(find.widgetWithText(TextField, 'Adresse email'), 'user@example.com');
    await tester.tap(find.text('Continuer'));
    await tester.pumpAndSettle();

    await tester.enterText(find.widgetWithText(TextField, 'Code de vérification'), '000000');
    await tester.tap(find.text('Vérifier'));
    await tester.pumpAndSettle();

    expect(fake.verifyCallCount, 1);
    expect(authenticatedCallCount, 0);
    // Still on the OTP screen, not thrown back to email.
    expect(find.text('Vérifiez votre email'), findsOneWidget);
    expect(find.widgetWithText(TextField, 'Adresse email'), findsNothing);

    // A second, correct attempt on the *same* screen must succeed without
    // needing to retype the email (spec bloc 4: a single OTP pass).
    await tester.enterText(find.widgetWithText(TextField, 'Code de vérification'), '123456');
    await tester.tap(find.text('Vérifier'));
    // See the earlier comment: success leaves an indeterminate spinner up
    // forever on purpose, so pumpAndSettle would never settle here.
    await tester.pump();
    await tester.pump();

    expect(fake.verifyCallCount, 2);
    expect(authenticatedCallCount, 1);
    expect(fake.sentEmails, ['user@example.com'],
        reason: 'retrying the code must never re-send a new OTP or re-ask for the email');
  });

  testWidgets(
      'spec CAS 3: an email this device already knows never sends an OTP - it authenticates '
      'directly, skipping the OTP screen entirely', (tester) async {
    await pump(tester);
    fake.knownEmails.add('known@example.com');

    await tester.enterText(find.widgetWithText(TextField, 'Adresse email'), 'known@example.com');
    await tester.tap(find.text('Continuer'));
    await tester.pump();
    await tester.pump();

    expect(fake.restoreCallCount, 1);
    expect(fake.sentEmails, isEmpty, reason: 'a known, already-associated account must never trigger an OTP send');
    expect(fake.verifyCallCount, 0);
    expect(authenticatedCallCount, 1);
    expect(find.text('Vérifiez votre email'), findsNothing,
        reason: 'the OTP screen must never even appear for a known account');
  });

  testWidgets(
      'spec TEST E: a known email whose device association was revoked falls through to a real '
      'OTP, exactly as if it had never been known', (tester) async {
    await pump(tester);
    fake.knownEmails.add('revoked@example.com');
    fake.revokedEmails.add('revoked@example.com');

    await tester.enterText(find.widgetWithText(TextField, 'Adresse email'), 'revoked@example.com');
    await tester.tap(find.text('Continuer'));
    await tester.pumpAndSettle();

    expect(fake.restoreCallCount, 1);
    expect(fake.sentEmails, ['revoked@example.com'],
        reason: 'a revoked association must never bypass a real OTP');
    expect(find.text('Vérifiez votre email'), findsOneWidget);
  });

  // spec TEST C/D: switching between two accounts already known on this
  // device resolves to the *correct* distinct account each time, with no
  // OTP for either. Two independent single-mount tests (rather than one
  // test remounting AccountGateScreen mid-way, which real AppGate does via
  // an entirely separate widget swap driven by its own state machine, not
  // something meaningfully reproducible by juggling two widget trees in
  // one test) - together they prove tryRestoreDeviceSession's result
  // actually determines which account signs in, not a hardcoded one.
  testWidgets('switching to a known account A resolves to A, with no OTP', (tester) async {
    await pump(tester);
    fake.knownEmails.addAll(['a@example.com', 'b@example.com']);

    await tester.enterText(find.widgetWithText(TextField, 'Adresse email'), 'a@example.com');
    await tester.tap(find.text('Continuer'));
    await tester.pump();
    await tester.pump();

    expect(fake.currentUser?.email, 'a@example.com');
    expect(fake.sentEmails, isEmpty);
    expect(authenticatedCallCount, 1);
  });

  testWidgets('switching to a known account B resolves to B, with no OTP', (tester) async {
    await pump(tester);
    fake.knownEmails.addAll(['a@example.com', 'b@example.com']);

    await tester.enterText(find.widgetWithText(TextField, 'Adresse email'), 'b@example.com');
    await tester.tap(find.text('Continuer'));
    await tester.pump();
    await tester.pump();

    expect(fake.currentUser?.email, 'b@example.com',
        reason: 'must resolve to whichever email was actually typed, never a fixed account');
    expect(fake.sentEmails, isEmpty);
    expect(authenticatedCallCount, 1);
  });

  testWidgets('manually tapping back from OTP returns to a fresh email screen', (tester) async {
    await pump(tester);

    await tester.enterText(find.widgetWithText(TextField, 'Adresse email'), 'user@example.com');
    await tester.tap(find.text('Continuer'));
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.arrow_back));
    await tester.pumpAndSettle();

    expect(find.widgetWithText(TextField, 'Adresse email'), findsOneWidget);
  });
}
