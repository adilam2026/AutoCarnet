import 'package:autocarnet/core/database/database.dart';
import 'package:autocarnet/core/database/providers.dart';
import 'package:autocarnet/core/sync/vehicle_sync_service.dart';
import 'package:autocarnet/features/account/data/account_repository.dart';
import 'package:autocarnet/features/audit/data/audit_repository.dart';
import 'package:autocarnet/features/reminders/data/reminder_repository.dart';
import 'package:autocarnet/features/vehicles/data/vehicle_repository.dart';
import 'package:autocarnet/features/vehicles/presentation/screens/vehicle_home_screen.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// A minimal signed-out stand-in for [AccountRepository] - VehicleHomeScreen
/// only ever reads `currentUser`/`onAuthStateChange` from it (to know
/// ownership/edit rights), and this test isn't exercising that - it must
/// just never touch a real (uninitialized-in-test) Supabase client.
class _FakeAccountRepository implements AccountRepository {
  @override
  User? get currentUser => null;
  @override
  Session? get currentSession => null;
  @override
  bool get isSignedIn => false;
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
  Future<void> disconnectFromThisDevice() async {}
  @override
  Future<void> disconnectFromAllDevices() async {}
}

/// A no-op stand-in for [VehicleSyncService] - `implements`, never `extends`,
/// so this never constructs a real [SupabaseClient] (its constructor starts
/// GoTrueClient's periodic auto-refresh Timer, which outlives the widget
/// tree and trips flutter_test's "no pending timers after dispose" check).
class _NoopVehicleSyncService implements VehicleSyncService {
  @override
  Future<void> syncNow() async {}

  @override
  void Function(String stage, String message)? onStep;
}

/// Regression coverage for the "Rejoindre un véhicule" crash: right after
/// accepting a share invite, the vehicle exists on the cloud but hasn't
/// necessarily reached this device's local Drift mirror yet.
/// VehicleHomeScreen used to `.watchSingle()` that row directly, which threw
/// `StateError('Expected exactly one element, but got 0')` the instant it
/// was navigated to during that window - the exact crash reported, surfaced
/// through the screen's own `error:` branch as a raw ErrorView. This test
/// drives the *real* VehicleHomeScreen through that exact window using a
/// real (in-memory) Drift database, never a mocked provider value, so it
/// actually exercises watchOne()/vehicleByIdProvider end to end.
void main() {
  late AppDatabase db;
  late VehicleRepository repo;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    repo = VehicleRepository(db, AuditRepository(db), ReminderRepository(db));
  });

  tearDown(() => db.close());

  Future<void> pumpScreen(WidgetTester tester, String vehicleId) async {
    final router = GoRouter(
      initialLocation: '/vehicles/$vehicleId',
      routes: [
        GoRoute(path: '/', builder: (context, state) => const Scaffold(body: Text('MES VEHICULES'))),
        GoRoute(
          path: '/vehicles/:id',
          builder: (context, state) => VehicleHomeScreen(vehicleId: state.pathParameters['id']!),
        ),
      ],
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appDatabaseProvider.overrideWithValue(db),
          vehicleRepositoryProvider.overrideWithValue(repo),
          accountRepositoryProvider.overrideWithValue(_FakeAccountRepository()),
          vehicleSyncServiceProvider.overrideWithValue(_NoopVehicleSyncService()),
        ],
        child: MaterialApp.router(routerConfig: router),
      ),
    );
  }

  testWidgets(
      'TEST G: membership/vehicle created on the cloud but not yet synced locally - the screen '
      'shows a syncing state, never the crash, then shows the real vehicle once it lands',
      (tester) async {
    const vehicleId = 'not-synced-yet';
    await pumpScreen(tester, vehicleId);
    await tester.pump();

    expect(find.text('Synchronisation en cours...'), findsOneWidget);
    expect(find.textContaining('Expected exactly one element'), findsNothing);
    expect(find.byType(AlertDialog), findsNothing);

    // The local sync pass "catches up": the row lands mid-flight, exactly
    // like VehicleSyncService._pull() inserting it a moment after
    // acceptInvite() returns.
    final now = DateTime.now();
    await db.into(db.vehicles).insert(
          VehiclesCompanion.insert(
            id: vehicleId,
            brand: 'Peugeot',
            model: '308',
            currentMileage: 42000,
            createdAt: now,
            updatedAt: now,
          ),
        );
    await db.into(db.mileageEntries).insert(
          MileageEntriesCompanion.insert(
            id: 'mileage-1',
            vehicleId: vehicleId,
            value: 42000,
            recordedAt: now,
            source: 'manual',
            createdAt: now,
          ),
        );

    await tester.pump();
    await tester.pump();

    expect(find.text('Synchronisation en cours...'), findsNothing);
    expect(find.text('Peugeot 308'), findsOneWidget);

    // Explicitly dispose the widget tree (and therefore every Drift stream
    // provider _VehicleHomeBody just started watching) while still inside
    // this pump loop, so the debounced Timer Drift schedules to actually
    // cancel each underlying query stream gets a chance to fire before the
    // test ends - otherwise flutter_test's own implicit teardown disposes
    // the tree one frame too late for that Timer to run, and its "no timer
    // left pending" invariant check fails on a leak that has nothing to do
    // with the behavior under test here.
    await tester.pumpWidget(const SizedBox());
    await tester.pump(Duration.zero);
  });

  testWidgets(
      'a vehicle id that never arrives locally (stale/invalid link) gives up after bounded '
      'retries with a safe way out, instead of hanging or crashing forever', (tester) async {
    await pumpScreen(tester, 'never-arrives');
    await tester.pump();
    expect(find.text('Synchronisation en cours...'), findsOneWidget);

    for (var i = 0; i < 7; i++) {
      await tester.pump(const Duration(seconds: 1));
    }

    expect(find.text('Synchronisation en cours...'), findsNothing);
    expect(find.text('Retour à mes véhicules'), findsOneWidget);
    expect(find.textContaining('Expected exactly one element'), findsNothing);

    await tester.tap(find.text('Retour à mes véhicules'));
    await tester.pumpAndSettle();
    expect(find.text('MES VEHICULES'), findsOneWidget);

    // See the comment on the previous test: let Drift's debounced
    // query-stream-close Timer fire before the test ends.
    await tester.pumpWidget(const SizedBox());
    await tester.pump(Duration.zero);
  });
}
