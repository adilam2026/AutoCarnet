import 'package:autocarnet/core/database/database.dart';
import 'package:autocarnet/core/database/providers.dart';
import 'package:autocarnet/features/account/data/account_repository.dart';
import 'package:autocarnet/features/audit/data/audit_repository.dart';
import 'package:autocarnet/features/dashboard/presentation/vehicles_list_body.dart';
import 'package:autocarnet/features/reminders/data/reminder_repository.dart';
import 'package:autocarnet/features/vehicles/data/vehicle_repository.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Signed-in, in-memory stand-in for [AccountRepository] - same minimal
/// pattern as the other widget-test fakes in this suite (see
/// account_management_ux_test.dart).
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

void main() {
  late AppDatabase db;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
  });

  tearDown(() => db.close());

  List<Override> commonOverrides() => [
        appDatabaseProvider.overrideWithValue(db),
        accountRepositoryProvider.overrideWithValue(_FakeSignedInAccountRepository()),
        // vehicleRepositoryProvider normally also wires vehicleSyncServiceProvider,
        // which reaches for Supabase.instance.client - never initialized in a
        // widget test. Build it without the (optional) sync arg instead, exactly
        // like vehicle_repository_test.dart's direct-construction fixtures do.
        vehicleRepositoryProvider.overrideWith((ref) => VehicleRepository(
              ref.watch(appDatabaseProvider),
              ref.watch(auditRepositoryProvider),
              ref.watch(reminderRepositoryProvider),
            )),
      ];

  Future<ProviderContainer> pumpDashboard(WidgetTester tester) async {
    final container = ProviderContainer(overrides: commonOverrides());
    addTearDown(container.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: Scaffold(body: VehiclesListBody())),
      ),
    );
    // Two pumps: vehiclesListProvider is a drift StreamProvider, so its
    // first emission needs an extra frame beyond the initial pumpWidget.
    await tester.pump();
    await tester.pump();
    return container;
  }

  testWidgets('no vehicles: shows the welcome empty state, never a bare blank screen',
      (tester) async {
    await pumpDashboard(tester);

    expect(find.text('Bienvenue dans AutoCarnet'), findsOneWidget);
    expect(find.text('Ajouter mon premier véhicule'), findsOneWidget);
    expect(find.text('Rejoindre un véhicule'), findsOneWidget);
  });

  testWidgets(
      'one vehicle, no reminders: shows its name/mileage and the positive '
      '"tout est à jour" card (spec: the section turns positive, never an empty list)',
      (tester) async {
    final repo = VehicleRepository(db, AuditRepository(db), ReminderRepository(db));
    await repo.createVehicle(brand: 'Audi', model: 'Q5', currentMileage: 86750);

    await pumpDashboard(tester);
    await tester.pump();

    // Both the header status line ("Votre Audi Q5 est à jour.") and the
    // vehicle card's own title legitimately contain "Audi Q5".
    expect(find.textContaining('Audi Q5'), findsNWidgets(2));
    expect(find.textContaining('86 750'), findsOneWidget);
    expect(find.text('Tout est à jour'), findsOneWidget);
    expect(find.textContaining('est à jour.'), findsOneWidget,
        reason: 'the header status line should read positively too');
  });

  testWidgets('one vehicle with an overdue reminder: it appears in "À faire prochainement"',
      (tester) async {
    final reminders = ReminderRepository(db);
    final repo = VehicleRepository(db, AuditRepository(db), reminders);
    final vehicleId =
        await repo.createVehicle(brand: 'Renault', model: 'Clio', currentMileage: 142300);
    await reminders.upsertForSource(
      vehicleId: vehicleId,
      sourceType: 'maintenance',
      sourceId: 'm1',
      title: 'Vidange',
      dueMileage: 142300 + 100,
    );

    await pumpDashboard(tester);
    await tester.pump();

    expect(find.text('Vidange'), findsOneWidget);
    expect(find.text('Tout est à jour'), findsNothing);
  });

  testWidgets(
      'the vehicle summary card never shows "Prochaine échéance" - only '
      '"Prochaine révision", with no reminder title duplicated in it',
      (tester) async {
    final reminders = ReminderRepository(db);
    final repo = VehicleRepository(db, AuditRepository(db), reminders);
    final vehicleId =
        await repo.createVehicle(brand: 'Audi', model: 'Q5', currentMileage: 86750);
    await reminders.upsertForSource(
      vehicleId: vehicleId,
      sourceType: 'maintenance',
      sourceId: 'm1',
      title: 'Vidange + filtres à prévoir',
      dueMileage: 95400,
    );
    await reminders.upsertForSource(
      vehicleId: vehicleId,
      sourceType: 'document',
      sourceId: 'd1',
      title: 'Assurance à renouveler',
      dueDate: DateTime.now().add(const Duration(days: 260)),
    );

    await pumpDashboard(tester);
    await tester.pump();

    expect(find.textContaining('Prochaine échéance'), findsNothing);
    expect(find.textContaining('PROCHAINE ÉCHÉANCE'), findsNothing);
    expect(find.textContaining('PROCHAINE RÉVISION'), findsOneWidget);
    // The reminder's own title never leaks into this summary slot.
    expect(find.textContaining('Vidange + filtres'), findsNothing);
    expect(find.textContaining('95 400'), findsOneWidget);
  });

  testWidgets('the dashboard renders without a horizontal overflow on a narrow (320px) screen',
      (tester) async {
    final repo = VehicleRepository(db, AuditRepository(db), ReminderRepository(db));
    await repo.createVehicle(brand: 'Audi', model: 'Q5', currentMileage: 86750);

    tester.view.physicalSize = const Size(320, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await pumpDashboard(tester);
    await tester.pump();

    expect(tester.takeException(), isNull);
  });
}
