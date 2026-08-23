import 'package:autocarnet/core/database/database.dart';
import 'package:autocarnet/core/database/providers.dart';
import 'package:autocarnet/features/account/data/account_repository.dart';
import 'package:autocarnet/features/audit/data/audit_repository.dart';
import 'package:autocarnet/features/expenses/presentation/expenses_tab.dart';
import 'package:autocarnet/features/fuel/data/fuel_repository.dart';
import 'package:autocarnet/features/fuel/presentation/fuel_tab.dart';
import 'package:autocarnet/features/maintenance/data/maintenance_repository.dart';
import 'package:autocarnet/features/reminders/data/reminder_repository.dart';
import 'package:autocarnet/features/timeline/data/timeline_repository.dart';
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

/// Regression coverage for the mission bug: the "Dépenses" screen rendered
/// completely empty (only the FAB visible) for a vehicle that genuinely had
/// linked expenses, while the dashboard's own "Dépenses 2026" stat tile -
/// backed by the exact same provider - showed the correct total.
///
/// Root cause: StatTileRow (lib/core/widgets/stat_tile.dart) used
/// `Row(crossAxisAlignment: CrossAxisAlignment.stretch)` directly inside a
/// Column. A Row's non-flexible layout pass inside a Column always receives
/// an unbounded max height - `stretch` in that situation makes Flutter try
/// to give its children an *infinite* height, which crashes deep inside a
/// descendant RenderConstrainedBox ("BoxConstraints forces an infinite
/// height"). That layout exception is thrown before paint, so the whole
/// body Column never renders - only the Scaffold's own
/// floatingActionButton ("Ajouter une dépense") survives, since it isn't
/// part of that Column. It only ever fires once the stats are non-null
/// (there IS data), which is exactly why no existing test caught it: every
/// prior ExpensesTab/FuelTab test only ever pumped an empty vehicle,
/// hitting the EmptyState branch and never actually building StatTileRow.
///
/// Fix: wrap the Row in an IntrinsicHeight (lib/core/widgets/stat_tile.dart)
/// so stretch has a bounded height to work with - the standard Flutter
/// pattern for "a Row of equal-height children" in an unbounded context.
void main() {
  late AppDatabase db;
  late VehicleRepository vehicles;
  late MaintenanceRepository maintenance;
  late String vehicleId;

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    final audit = AuditRepository(db);
    final timeline = TimelineRepository(db);
    final reminders = ReminderRepository(db);
    vehicles = VehicleRepository(db, audit, reminders);
    maintenance = MaintenanceRepository(db, timeline, reminders, vehicles);

    vehicleId = await vehicles.createVehicle(
      brand: 'Audi',
      model: 'Q5',
      currentMileage: 85450,
    );
  });

  tearDown(() => db.close());

  Future<void> pumpExpensesTab(WidgetTester tester) async {
    final container = ProviderContainer(overrides: [
      appDatabaseProvider.overrideWithValue(db),
      accountRepositoryProvider.overrideWithValue(_FakeSignedInAccountRepository()),
    ]);
    addTearDown(container.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(home: ExpensesTab(vehicleId: vehicleId)),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets(
      'CAS mission: Audi Q5 with 5500 MAD + 2200 MAD vidanges shows both '
      'rows and a 7700 MAD total - no layout crash, no empty state',
      (tester) async {
    await maintenance.createEntry(
      vehicleId: vehicleId,
      category: 'Vidange',
      date: DateTime(2026, 8, 9),
      mileage: 85450,
      laborCost: 5500,
    );
    await maintenance.createEntry(
      vehicleId: vehicleId,
      category: 'Vidange',
      date: DateTime(2026, 2, 3),
      mileage: 76500,
      laborCost: 2200,
    );

    // A regression here throws during performLayout(), which flutter_test
    // surfaces as a FlutterError from this very call - the exception is the
    // test failure, so no additional plumbing is needed to detect it.
    await pumpExpensesTab(tester);

    expect(find.text('Aucune dépense enregistrée'), findsNothing);
    expect(find.text('5 500 MAD'), findsOneWidget);
    expect(find.text('2 200 MAD'), findsOneWidget);
    // "Cette année" and "Total" tiles both read 7 700 for this scenario.
    expect(find.text('7 700'), findsNWidgets(2));
  });

  testWidgets(
      'correcting the montant (5500 -> 6000) updates the row AND the total '
      'shown on screen - never a duplicate line', (tester) async {
    final id = await maintenance.createEntry(
      vehicleId: vehicleId,
      category: 'Vidange',
      date: DateTime(2026, 8, 9),
      mileage: 85450,
      laborCost: 5500,
    );

    await pumpExpensesTab(tester);
    expect(find.text('5 500 MAD'), findsOneWidget);

    await maintenance.updateEntry(
      id: id,
      vehicleId: vehicleId,
      category: 'Vidange',
      date: DateTime(2026, 8, 9),
      mileage: 85450,
      laborCost: 6000,
    );
    await tester.pumpAndSettle();

    expect(find.text('5 500 MAD'), findsNothing);
    expect(find.text('6 000 MAD'), findsOneWidget);
    // "Ce mois", "Cette année" and "Total" all read 6 000 for this
    // single-entry scenario (the entry's date falls in the current month).
    expect(find.text('6 000'), findsNWidgets(3));
  });

  testWidgets(
      'deleting the maintenance entry also removes it from Dépenses - back '
      'to the empty state', (tester) async {
    final id = await maintenance.createEntry(
      vehicleId: vehicleId,
      category: 'Vidange',
      date: DateTime(2026, 8, 9),
      mileage: 85450,
      laborCost: 5500,
    );

    await pumpExpensesTab(tester);
    expect(find.text('5 500 MAD'), findsOneWidget);

    await maintenance.softDelete(id);
    await tester.pumpAndSettle();

    expect(find.text('5 500 MAD'), findsNothing);
    expect(find.text('Aucune dépense enregistrée'), findsOneWidget);
  });

  testWidgets(
      'multi-vehicle: switching to a different vehicle only shows its own '
      'expenses (RG-DEP-003)', (tester) async {
    await maintenance.createEntry(
      vehicleId: vehicleId,
      category: 'Vidange',
      date: DateTime(2026, 8, 9),
      mileage: 85450,
      laborCost: 5500,
    );
    final otherVehicleId = await vehicles.createVehicle(
      brand: 'Opel',
      model: 'Astra',
      currentMileage: 40000,
    );
    await maintenance.createEntry(
      vehicleId: otherVehicleId,
      category: 'Freins',
      date: DateTime(2026, 5, 1),
      mileage: 40000,
      laborCost: 900,
    );

    final container = ProviderContainer(overrides: [
      appDatabaseProvider.overrideWithValue(db),
      accountRepositoryProvider.overrideWithValue(_FakeSignedInAccountRepository()),
    ]);
    addTearDown(container.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(home: ExpensesTab(vehicleId: otherVehicleId)),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('900 MAD'), findsOneWidget);
    expect(find.text('5 500 MAD'), findsNothing);
  });

  testWidgets('FuelTab (same StatTileRow) also survives real, non-empty '
      'stats without a layout crash', (tester) async {
    final fuel = FuelRepository(db, TimelineRepository(db), vehicles);
    await fuel.createEntry(
      vehicleId: vehicleId,
      date: DateTime(2026, 8, 9),
      mileage: 85450,
      fuelType: 'Diesel',
      quantityLiters: 45,
      pricePerLiter: 13.5,
      isFullTank: true,
    );

    final container = ProviderContainer(overrides: [
      appDatabaseProvider.overrideWithValue(db),
      accountRepositoryProvider.overrideWithValue(_FakeSignedInAccountRepository()),
    ]);
    addTearDown(container.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(home: FuelTab(vehicleId: vehicleId)),
      ),
    );
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
  });
}
