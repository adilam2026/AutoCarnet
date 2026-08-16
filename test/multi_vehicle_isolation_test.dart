import 'package:autocarnet/core/database/database.dart';
import 'package:autocarnet/core/utils/mileage_result.dart';
import 'package:autocarnet/features/audit/data/audit_repository.dart';
import 'package:autocarnet/features/documents/data/document_repository.dart';
import 'package:autocarnet/features/expenses/data/expense_repository.dart';
import 'package:autocarnet/features/fuel/data/fuel_repository.dart';
import 'package:autocarnet/features/maintenance/data/maintenance_repository.dart';
import 'package:autocarnet/features/reminders/data/reminder_repository.dart';
import 'package:autocarnet/features/timeline/data/timeline_repository.dart';
import 'package:autocarnet/features/vehicles/data/vehicle_repository.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

/// AutoCarnet is multi-vehicle by design (bloc 3, §6.2): a user's garage is
/// the norm, not the exception. Every one of these tests proves that no
/// module ever mixes data between two vehicles owned by the same user.
void main() {
  late AppDatabase db;
  late TimelineRepository timeline;
  late ReminderRepository reminders;
  late VehicleRepository vehicles;
  late ExpenseRepository expenses;
  late DocumentRepository documents;
  late MaintenanceRepository maintenance;
  late FuelRepository fuel;

  late String vehicleA;
  late String vehicleB;

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    timeline = TimelineRepository(db);
    reminders = ReminderRepository(db);
    vehicles = VehicleRepository(db, AuditRepository(db), reminders);
    expenses = ExpenseRepository(db, timeline);
    documents = DocumentRepository(db, timeline, reminders);
    maintenance = MaintenanceRepository(db, timeline, reminders, vehicles);
    fuel = FuelRepository(db, timeline, vehicles);

    vehicleA = await vehicles.createVehicle(
      brand: 'Audi',
      model: 'Q5',
      currentMileage: 40000,
    );
    vehicleB = await vehicles.createVehicle(
      brand: 'Dacia',
      model: 'Duster',
      currentMileage: 60000,
    );
  });

  tearDown(() => db.close());

  test('a user can own several vehicles at once', () async {
    final all = await vehicles.watchAll().first;
    expect(all.map((v) => v.id), containsAll([vehicleA, vehicleB]));
    expect(all, hasLength(2));
  });

  test('expenses never mix across vehicles (RG-DEP-001/003)', () async {
    await expenses.createExpense(
      vehicleId: vehicleA,
      category: 'Assurance',
      date: DateTime.now(),
      amount: 1200,
    );
    await expenses.createExpense(
      vehicleId: vehicleB,
      category: 'Carburant',
      date: DateTime.now(),
      amount: 80,
    );

    final expensesA = await expenses.watchForVehicle(vehicleA).first;
    final expensesB = await expenses.watchForVehicle(vehicleB).first;

    expect(expensesA, hasLength(1));
    expect(expensesA.single.category, 'Assurance');
    expect(expensesB, hasLength(1));
    expect(expensesB.single.category, 'Carburant');

    final statsA = expenses.computeStats(expensesA);
    final statsB = expenses.computeStats(expensesB);
    expect(statsA.totalAll, 1200);
    expect(statsB.totalAll, 80);
  });

  test('documents never mix across vehicles (RG-DOC)', () async {
    await documents.createDocument(
      vehicleId: vehicleA,
      type: 'Carte grise',
    );
    final docsA = await documents.watchForVehicle(vehicleA).first;
    final docsB = await documents.watchForVehicle(vehicleB).first;
    expect(docsA, hasLength(1));
    expect(docsB, isEmpty);
  });

  test('maintenance history never mixes across vehicles (RG-ENT-001)', () async {
    await maintenance.createEntry(
      vehicleId: vehicleA,
      category: 'Vidange',
      date: DateTime.now(),
      mileage: 40500,
    );
    final entriesA = await maintenance.watchForVehicle(vehicleA).first;
    final entriesB = await maintenance.watchForVehicle(vehicleB).first;
    expect(entriesA, hasLength(1));
    expect(entriesB, isEmpty);
  });

  test('fuel entries never mix across vehicles (RG-CARB-001)', () async {
    await fuel.createEntry(
      vehicleId: vehicleA,
      date: DateTime.now(),
      mileage: 40200,
      fuelType: 'Essence',
      quantityLiters: 45,
      pricePerLiter: 1.9,
    );
    final entriesA = await fuel.watchForVehicle(vehicleA).first;
    final entriesB = await fuel.watchForVehicle(vehicleB).first;
    expect(entriesA, hasLength(1));
    expect(entriesB, isEmpty);
  });

  test('timeline events never mix across vehicles (RG-TIME)', () async {
    await expenses.createExpense(
      vehicleId: vehicleA,
      category: 'Péage',
      date: DateTime.now(),
      amount: 10,
    );
    final timelineA = await timeline.watchForVehicle(vehicleA).first;
    final timelineB = await timeline.watchForVehicle(vehicleB).first;
    // Vehicle creation is an audit fact, not a business event (bloc
    // "historique métier vs journal d'audit") - only the expense shows up.
    expect(timelineA, hasLength(1));
    expect(timelineB, isEmpty);
  });

  test('reminders never mix across vehicles (RG-ALR)', () async {
    await documents.createDocument(
      vehicleId: vehicleA,
      type: 'Assurance',
      expiryDate: DateTime.now().add(const Duration(days: 5)),
    );
    final activeA = await reminders.watchActiveForVehicle(vehicleA).first;
    final activeB = await reminders.watchActiveForVehicle(vehicleB).first;
    expect(activeA, hasLength(1));
    expect(activeB, isEmpty);
  });

  test(
      'a high-mileage operation on vehicle B never blocks lowering the '
      'mileage on vehicle A (mileage coherence is per-vehicle)', () async {
    // Vehicle B has an operation recorded well above vehicle A's mileage.
    await maintenance.createEntry(
      vehicleId: vehicleB,
      category: 'Révision',
      date: DateTime.now(),
      mileage: 120000,
    );

    // Vehicle A should still be able to lower its own mileage freely,
    // vehicle B's history must not leak into vehicle A's coherence check.
    final result = await vehicles.checkMileageChange(vehicleA, 39000);
    expect(result, isA<MileageNeedsConfirmation>());
  });

  test(
      'lowering vehicle A below its own recorded operation is still '
      'blocked even while vehicle B has unrelated higher-mileage history',
      () async {
    await maintenance.createEntry(
      vehicleId: vehicleA,
      category: 'Vidange',
      date: DateTime.now(),
      mileage: 39500,
    );
    await maintenance.createEntry(
      vehicleId: vehicleB,
      category: 'Révision',
      date: DateTime.now(),
      mileage: 200000,
    );

    final result = await vehicles.checkMileageChange(vehicleA, 39000);
    expect(result, isA<MileageBlocked>());
  });

  test('selling one vehicle does not archive or affect the other', () async {
    await vehicles.setStatus(vehicleA, VehicleStatus.sold);
    final a = await vehicles.getOne(vehicleA);
    final b = await vehicles.getOne(vehicleB);
    expect(a.status, VehicleStatus.sold);
    expect(b.status, VehicleStatus.active);
  });
}
