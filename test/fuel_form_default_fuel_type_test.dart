import 'package:autocarnet/core/database/database.dart';
import 'package:autocarnet/core/database/providers.dart';
import 'package:autocarnet/features/account/data/account_repository.dart';
import 'package:autocarnet/features/audit/data/audit_repository.dart';
import 'package:autocarnet/features/fuel/presentation/fuel_tab.dart';
import 'package:autocarnet/features/reminders/data/reminder_repository.dart';
import 'package:autocarnet/features/vehicles/data/vehicle_repository.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class _FakeSignedInAccountRepository implements AccountRepository {
  @override
  User? get currentUser => User(
        id: 'me',
        appMetadata: const {},
        userMetadata: null,
        aud: 'authenticated',
        email: 'me@example.com',
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
  Future<String?> deviceAuthorizedUserId() async => 'me';
  @override
  Future<String?> lastDeviceUserId() async => 'me';
  @override
  Future<String?> deviceAuthorizedEmail() async => 'me@example.com';
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

/// Mission regression: opening "Plein" for a Diesel vehicle used to show
/// the form pre-filled with "Essence" (the dropdown's first generic option)
/// regardless of the vehicle's actual, already-known fuel type. The fiche
/// véhicule is the source of truth - the form must prefill from it, and
/// must never invent a value when the vehicle's own fuel type is unknown.
void main() {
  late AppDatabase db;
  late VehicleRepository vehicles;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    final audit = AuditRepository(db);
    final reminders = ReminderRepository(db);
    vehicles = VehicleRepository(db, audit, reminders);
  });

  tearDown(() => db.close());

  Future<void> pumpFuelTab(WidgetTester tester, String vehicleId) async {
    final container = ProviderContainer(overrides: [
      appDatabaseProvider.overrideWithValue(db),
      accountRepositoryProvider.overrideWithValue(_FakeSignedInAccountRepository()),
      // The default vehicleRepositoryProvider pulls in VehicleSyncService,
      // which reads Supabase.instance - never initialized in tests. Reuse
      // the manually-constructed [vehicles] (no sync arg) instead, exactly
      // like every repository used directly in this file already is.
      vehicleRepositoryProvider.overrideWithValue(vehicles),
    ]);
    addTearDown(container.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(home: FuelTab(vehicleId: vehicleId)),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('a Diesel vehicle opens "Plein" with Diesel already selected, never Essence',
      (tester) async {
    final vehicleId = await vehicles.createVehicle(
      brand: 'Audi',
      model: 'Q5',
      currentMileage: 86950,
      fuelType: 'Diesel',
    );

    await pumpFuelTab(tester, vehicleId);
    await tester.tap(find.text('Ajouter un plein').first);
    await tester.pumpAndSettle();

    expect(find.text('Diesel'), findsOneWidget);
    expect(find.text('Essence'), findsNothing);
  });

  testWidgets(
      'a vehicle with no known fuel type opens "Plein" with no fuel type '
      'preselected - never a silent guess', (tester) async {
    final vehicleId = await vehicles.createVehicle(
      brand: 'Audi',
      model: 'Q5',
      currentMileage: 86950,
    );

    await pumpFuelTab(tester, vehicleId);
    await tester.tap(find.text('Ajouter un plein').first);
    await tester.pumpAndSettle();

    expect(find.text('Essence'), findsNothing);
    expect(find.text('Sélectionner'), findsOneWidget);
  });

  testWidgets(
      'saving without picking a fuel type is rejected with a validation error, and no '
      'entry is created', (tester) async {
    final vehicleId = await vehicles.createVehicle(
      brand: 'Audi',
      model: 'Q5',
      currentMileage: 86950,
    );

    final container = ProviderContainer(overrides: [
      appDatabaseProvider.overrideWithValue(db),
      accountRepositoryProvider.overrideWithValue(_FakeSignedInAccountRepository()),
      // The default vehicleRepositoryProvider pulls in VehicleSyncService,
      // which reads Supabase.instance - never initialized in tests. Reuse
      // the manually-constructed [vehicles] (no sync arg) instead, exactly
      // like every repository used directly in this file already is.
      vehicleRepositoryProvider.overrideWithValue(vehicles),
    ]);
    addTearDown(container.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(home: FuelTab(vehicleId: vehicleId)),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Ajouter un plein').first);
    await tester.pumpAndSettle();

    await tester.enterText(find.widgetWithText(TextFormField, 'Quantité *'), '40');
    await tester.pump();
    await tester.enterText(find.widgetWithText(TextFormField, 'Prix / L *'), '12');
    await tester.pump();
    await tester.tap(find.widgetWithText(FilledButton, 'Enregistrer'));
    // Not pumpAndSettle(): the validation-error decoration keeps a frame
    // scheduled indefinitely in this test harness (unrelated to app
    // correctness - confirmed the save is genuinely rejected and no entry
    // is created either way), so a bounded pump is used instead.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    expect(find.text('Champ requis'), findsWidgets);
    // A one-shot query, not .watchForVehicle(...).first: awaiting a Drift
    // reactive stream directly inside a widget test's fake-async zone
    // hangs (it needs tester.runAsync, unlike a plain one-shot query).
    final entries =
        await (db.select(db.fuelEntries)..where((f) => f.vehicleId.equals(vehicleId))).get();
    expect(entries, isEmpty);
  });
}
