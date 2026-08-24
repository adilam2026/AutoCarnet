import 'package:autocarnet/core/database/database.dart';
import 'package:autocarnet/core/database/providers.dart';
import 'package:autocarnet/features/account/data/account_repository.dart';
import 'package:autocarnet/features/dashboard/presentation/app_shell.dart';
import 'package:autocarnet/features/onboarding_lock/data/biometric_service.dart';
import 'package:autocarnet/features/onboarding_lock/data/pin_service.dart';
import 'package:autocarnet/features/onboarding_lock/presentation/app_gate.dart';
import 'package:autocarnet/features/settings/presentation/account_management_screen.dart';
import 'package:autocarnet/features/settings/presentation/settings_screen.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Signed-in, in-memory stand-in for [AccountRepository] - no Supabase
/// network call, no secure storage - just enough for SettingsScreen/
/// AppShell to render as if a real account were active.
class _FakeSignedInAccountRepository implements AccountRepository {
  @override
  User? get currentUser => User(
        id: 'user-1',
        appMetadata: const {},
        userMetadata: null,
        aud: 'authenticated',
        email: 'a@example.com',
        createdAt: DateTime.now().toIso8601String(),
      );
  @override
  Session? get currentSession => null;
  @override
  bool get isSignedIn => true;
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
  @override
  Future<bool> isPinSet(String accountId) async => true;
  @override
  Future<void> setPin(String accountId, String pin) async {}
  @override
  Future<bool> verifyPin(String accountId, String pin) async => false;
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
  late AppDatabase db;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
  });

  tearDown(() => db.close());

  List<Override> commonOverrides() => [
        appDatabaseProvider.overrideWithValue(db),
        accountRepositoryProvider.overrideWithValue(_FakeSignedInAccountRepository()),
        pinServiceProvider.overrideWithValue(_FakePinService()),
        biometricServiceProvider.overrideWithValue(_FakeBiometricService()),
      ];

  group('Compte & sécurité (SettingsScreen)', () {
    testWidgets(
        'TEST D: "Changer de compte" no longer appears on the main page - only '
        '"Gestion du compte" does, and it opens a screen with the two moved actions',
        (tester) async {
      final container = ProviderContainer(overrides: commonOverrides());
      addTearDown(container.dispose);
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(home: SettingsScreen()),
        ),
      );
      await tester.pump();

      expect(find.text('Changer de compte'), findsNothing);
      expect(find.text('Dissocier ce compte de cet appareil'), findsNothing,
          reason: 'must be moved behind Gestion du compte, not shown on the main page');
      expect(find.text('Déconnecter tous les appareils'), findsNothing,
          reason: 'must be moved behind Gestion du compte, not shown on the main page');
      expect(find.text('Gestion du compte'), findsOneWidget);

      await tester.tap(find.text('Gestion du compte'));
      await tester.pumpAndSettle();

      expect(find.byType(AccountManagementScreen), findsOneWidget);
      expect(find.text('Dissocier ce compte de cet appareil'), findsOneWidget);
      expect(find.text('Déconnecter tous les appareils'), findsOneWidget);
    });

    testWidgets('"Verrouiller maintenant" (Sécurité) still bumps sessionLockRequestProvider',
        (tester) async {
      final container = ProviderContainer(overrides: commonOverrides());
      addTearDown(container.dispose);
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(home: SettingsScreen()),
        ),
      );
      await tester.pump();

      // "Mes documents personnels" (mission 2026) pushes "Sécurité" further
      // down the page - scroll to it rather than assuming it's on-screen.
      await tester.ensureVisible(find.text('Verrouiller maintenant'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Verrouiller maintenant'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Verrouiller'));
      await tester.pumpAndSettle();

      expect(container.read(sessionLockRequestProvider), 1);
    });
  });

  group('AccountManagementScreen', () {
    testWidgets('TEST B: dissociate asks for a strong confirmation, then bumps the request',
        (tester) async {
      final container = ProviderContainer(overrides: commonOverrides());
      addTearDown(container.dispose);
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(home: AccountManagementScreen()),
        ),
      );

      await tester.tap(find.text('Dissocier ce compte de cet appareil'));
      await tester.pumpAndSettle();
      expect(container.read(accountDissociateRequestProvider), 0,
          reason: 'must ask for confirmation first');
      expect(find.textContaining('vérifier votre adresse email'), findsOneWidget);

      await tester.tap(find.widgetWithText(FilledButton, 'Dissocier'));
      await tester.pumpAndSettle();

      expect(container.read(accountDissociateRequestProvider), 1);
    });

    testWidgets('TEST C: disconnect-everywhere asks for confirmation, then bumps the request',
        (tester) async {
      final container = ProviderContainer(overrides: commonOverrides());
      addTearDown(container.dispose);
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(home: AccountManagementScreen()),
        ),
      );

      await tester.tap(find.text('Déconnecter tous les appareils'));
      await tester.pumpAndSettle();
      expect(container.read(accountDisconnectEverywhereRequestProvider), 0);

      await tester.tap(find.widgetWithText(FilledButton, 'Déconnecter tout'));
      await tester.pumpAndSettle();

      expect(container.read(accountDisconnectEverywhereRequestProvider), 1);
    });
  });

  group('AppShell drawer', () {
    Future<ProviderContainer> pumpShell(WidgetTester tester) async {
      final container = ProviderContainer(overrides: commonOverrides());
      addTearDown(container.dispose);
      final router = GoRouter(routes: [
        GoRoute(path: '/', builder: (_, _) => const AppShell()),
        GoRoute(path: '/settings', builder: (_, _) => const SettingsScreen()),
        GoRoute(path: '/providers', builder: (_, _) => const SizedBox()),
        GoRoute(path: '/audit-log', builder: (_, _) => const SizedBox()),
      ]);
      addTearDown(router.dispose);
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp.router(routerConfig: router),
        ),
      );
      await tester.pump();
      return container;
    }

    testWidgets(
        'TEST A: "Verrouiller AutoCarnet" is reachable from the main drawer, asks a light '
        'confirmation, then bumps sessionLockRequestProvider', (tester) async {
      final container = await pumpShell(tester);

      // Open the drawer via the Scaffold's hamburger button.
      final scaffoldState = tester.state<ScaffoldState>(find.byType(Scaffold).first);
      scaffoldState.openDrawer();
      await tester.pumpAndSettle();

      expect(find.text('Verrouiller AutoCarnet'), findsOneWidget);

      await tester.tap(find.text('Verrouiller AutoCarnet'));
      await tester.pumpAndSettle();

      expect(container.read(sessionLockRequestProvider), 0,
          reason: 'must ask for confirmation first');
      await tester.tap(find.widgetWithText(FilledButton, 'Verrouiller'));
      await tester.pumpAndSettle();

      expect(container.read(sessionLockRequestProvider), 1);
    });
  });
}
