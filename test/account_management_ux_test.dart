import 'package:autocarnet/core/database/database.dart';
import 'package:autocarnet/core/database/providers.dart';
import 'package:autocarnet/core/notifications/notification_repository.dart';
import 'package:autocarnet/core/sync/conflict_repository.dart';
import 'package:autocarnet/core/sync/document_sync_service.dart';
import 'package:autocarnet/core/sync/expense_sync_service.dart';
import 'package:autocarnet/core/sync/frequency_pref_sync_service.dart';
import 'package:autocarnet/core/sync/fuel_sync_service.dart';
import 'package:autocarnet/core/sync/maintenance_sync_service.dart';
import 'package:autocarnet/core/sync/mileage_sync_service.dart';
import 'package:autocarnet/core/sync/provider_sync_service.dart';
import 'package:autocarnet/core/sync/reminder_sync_service.dart';
import 'package:autocarnet/core/sync/sync_coordinator.dart';
import 'package:autocarnet/core/sync/sync_outbox_repository.dart';
import 'package:autocarnet/core/sync/vehicle_sync_service.dart';
import 'package:autocarnet/features/account/data/account_repository.dart';
import 'package:autocarnet/features/dashboard/presentation/app_shell.dart';
import 'package:autocarnet/features/onboarding_lock/data/biometric_service.dart';
import 'package:autocarnet/features/onboarding_lock/data/pin_service.dart';
import 'package:autocarnet/features/onboarding_lock/presentation/app_gate.dart';
import 'package:autocarnet/features/settings/presentation/account_management_screen.dart';
import 'package:autocarnet/features/settings/presentation/settings_screen.dart';
import 'package:autocarnet/features/timeline/data/timeline_repository.dart';
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

class _NoOpSyncCoordinator extends SyncCoordinator {
  _NoOpSyncCoordinator({
    required super.db,
    required super.clientFn,
    required super.vehicles,
    required super.maintenance,
    required super.expenses,
    required super.fuel,
    required super.documents,
    required super.reminders,
    required super.mileage,
    required super.frequencyPrefs,
    required super.providers,
    required super.notifications,
    required super.conflicts,
  });

  bool syncAllCalled = false;

  @override
  Future<void> syncAll() async {
    syncAllCalled = true;
  }
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

  // A SyncCoordinator whose syncAll() is a pure no-op recording that it was
  // called - never a real SupabaseClient: constructing one inside a
  // testWidgets test hangs the test outright (RealtimeClient/GoTrue try to
  // do real network/socket work even when unauthenticated, which the
  // sandboxed test environment never resolves). Every *SyncService field
  // still gets a real instance (harmless - db-only, no network) so the
  // constructor's required parameters are satisfied, but [syncAll] itself
  // never touches them.
  ({SyncCoordinator coordinator, bool Function() wasCalled}) buildNoOpCoordinator() {
    SupabaseClient client() => throw StateError('must never be called - syncAll is overridden');
    final conflicts = ConflictRepository(db);
    final timeline = TimelineRepository(db);
    final outbox = SyncOutboxRepository(db);
    final coordinator = _NoOpSyncCoordinator(
      db: db,
      clientFn: client,
      vehicles: VehicleSyncService(db, client, conflicts, outbox),
      maintenance: MaintenanceSyncService(db, client, conflicts, timeline, outbox),
      expenses: ExpenseSyncService(db, client, conflicts, outbox),
      fuel: FuelSyncService(db, client, conflicts, timeline, outbox),
      documents: DocumentSyncService(db, client, conflicts, timeline, outbox),
      reminders: ReminderSyncService(db, client, conflicts, outbox),
      mileage: MileageSyncService(db, client, outbox),
      frequencyPrefs: FrequencyPrefSyncService(db, client, conflicts, outbox),
      providers: ProviderSyncService(db, client, conflicts, outbox),
      notifications: NotificationRepository(db),
      conflicts: conflicts,
    );
    return (coordinator: coordinator, wasCalled: () => coordinator.syncAllCalled);
  }

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

    testWidgets(
        'mission point 7: with pending unsynced changes, dissociating shows the '
        'warning FIRST, and Annuler blocks the action entirely - the normal '
        'confirmation dialog never even appears', (tester) async {
      await SyncOutboxRepository(db)
          .enqueue(entityType: 'vehicle', entityId: 'v1', operation: 'create');

      final container = ProviderContainer(overrides: commonOverrides());
      addTearDown(container.dispose);
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(home: AccountManagementScreen()),
        ),
      );
      await tester.pump();

      await tester.tap(find.text('Dissocier ce compte de cet appareil'));
      await tester.pumpAndSettle();

      expect(find.text('Modifications non sauvegardées'), findsOneWidget);
      expect(find.textContaining('pas encore sauvegardées dans le cloud'), findsOneWidget);
      expect(find.textContaining('vérifier votre adresse email'), findsNothing,
          reason: 'the normal confirm dialog must never appear before this warning is resolved');

      await tester.tap(find.widgetWithText(TextButton, 'Annuler'));
      await tester.pumpAndSettle();

      expect(container.read(accountDissociateRequestProvider), 0);
      expect(find.textContaining('vérifier votre adresse email'), findsNothing);
    });

    testWidgets(
        'mission point 7: "Synchroniser maintenant" nudges a sync pass and '
        'still blocks the destructive action for this tap - never lets the user '
        'believe everything is saved', (tester) async {
      await SyncOutboxRepository(db)
          .enqueue(entityType: 'vehicle', entityId: 'v1', operation: 'create');
      final fakeSync = buildNoOpCoordinator();

      final container = ProviderContainer(overrides: [
        ...commonOverrides(),
        syncCoordinatorProvider.overrideWithValue(fakeSync.coordinator),
      ]);
      addTearDown(container.dispose);
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(home: AccountManagementScreen()),
        ),
      );
      await tester.pump();

      await tester.tap(find.text('Déconnecter tous les appareils'));
      await tester.pumpAndSettle();
      expect(find.text('Modifications non sauvegardées'), findsOneWidget);

      await tester.tap(find.widgetWithText(FilledButton, 'Synchroniser maintenant'));
      await tester.pumpAndSettle();

      expect(container.read(accountDisconnectEverywhereRequestProvider), 0,
          reason: 'a sync nudge must never itself count as having disconnected');
      expect(find.text('Synchronisation en cours...'), findsOneWidget);
      expect(fakeSync.wasCalled(), isTrue, reason: 'must actually trigger a sync pass');
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
