
import 'dart:io';
import 'package:autocarnet/core/database/database.dart';
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

/// End-to-end scenario (cahier des charges §22): a demo vehicle with 2
/// maintenance entries, 1 repair, 1 insurance document, 3 fill-ups and
/// several expenses. Every operation must stay consultable, editable, and
/// correctly reflected across historique/dépenses/kilométrage/reminders -
/// and it must all survive an actual app restart, not just an in-memory
/// database session.
void main() {
  late Directory tempDir;
  late File dbFile;
  late AppDatabase db;
  late TimelineRepository timeline;
  late ReminderRepository reminders;
  late VehicleRepository vehicles;
  late MaintenanceRepository maintenance;
  late FuelRepository fuel;
  late ExpenseRepository expenses;
  late DocumentRepository documents;

  late String vehicleId;
  late String otherVehicleId;
  late String vidangeId;
  late String reparationId;
  late String insuranceDocId;
  late List<String> fuelIds;

  void wireRepositories() {
    timeline = TimelineRepository(db);
    reminders = ReminderRepository(db);
    vehicles = VehicleRepository(db, AuditRepository(db), reminders);
    maintenance = MaintenanceRepository(db, timeline, reminders, vehicles);
    fuel = FuelRepository(db, timeline, vehicles);
    expenses = ExpenseRepository(db, timeline);
    documents = DocumentRepository(db, timeline, reminders);
  }

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('autocarnet_test_');
    dbFile = File('${tempDir.path}/scenario.sqlite');
    db = AppDatabase(NativeDatabase(dbFile));
    wireRepositories();

    vehicleId = await vehicles.createVehicle(
      brand: 'Audi',
      model: 'Q5',
      currentMileage: 78000,
    );
    otherVehicleId = await vehicles.createVehicle(
      brand: 'Dacia',
      model: 'Duster',
      currentMileage: 30000,
    );

    vidangeId = await maintenance.createEntry(
      vehicleId: vehicleId,
      category: 'Vidange',
      date: DateTime(2026, 3, 1),
      mileage: 78000,
      laborCost: 200,
      nextDueMileage: 88000,
    );
    await maintenance.createEntry(
      vehicleId: vehicleId,
      category: 'Révision',
      date: DateTime(2026, 1, 1),
      mileage: 70000,
      laborCost: 500,
    );
    reparationId = await maintenance.createEntry(
      vehicleId: vehicleId,
      category: 'Réparation',
      date: DateTime(2026, 4, 1),
      mileage: 79000,
      laborCost: 1200,
    );
    insuranceDocId = await documents.createDocument(
      vehicleId: vehicleId,
      type: 'Assurance',
      expiryDate: DateTime.now().add(const Duration(days: 200)),
      cost: 4500,
    );
    fuelIds = [];
    for (var i = 0; i < 3; i++) {
      fuelIds.add(await fuel.createEntry(
        vehicleId: vehicleId,
        date: DateTime(2026, 2, 1 + i * 10),
        mileage: 78000 + i * 500,
        fuelType: 'Diesel',
        quantityLiters: 40,
        pricePerLiter: 12,
      ));
    }
    await expenses.createExpense(
      vehicleId: vehicleId,
      category: 'Péage',
      date: DateTime(2026, 2, 5),
      amount: 80,
    );
    await expenses.createExpense(
      vehicleId: vehicleId,
      category: 'Lavage',
      date: DateTime(2026, 2, 10),
      amount: 50,
    );
  });

  tearDown(() async {
    await db.close();
    if (await tempDir.exists()) await tempDir.delete(recursive: true);
  });

  test('1. every created operation appears on the vehicle (scoped queries)', () async {
    final entries = await maintenance.watchForVehicle(vehicleId).first;
    final docs = await documents.watchForVehicle(vehicleId).first;
    final fuelEntries = await fuel.watchForVehicle(vehicleId).first;
    final expenseEntries = await expenses.watchForVehicle(vehicleId).first;

    expect(entries, hasLength(3));
    expect(docs, hasLength(1));
    expect(fuelEntries, hasLength(3));
    // 2 standalone + 3 auto-generated from fuel + 3 auto-generated from
    // maintenance (vidange, révision, réparation all have a positive cost).
    expect(expenseEntries.length, greaterThanOrEqualTo(8));
  });

  test('2. "Voir tout l\'historique" (timeline) shows every operation', () async {
    final events = await timeline.watchForVehicle(vehicleId).first;
    final linkedIds = events.map((e) => e.linkedEntityId).toSet();
    expect(linkedIds, containsAll([vidangeId, reparationId, insuranceDocId, ...fuelIds]));
  });

  test('3. every row can be reopened by id (what a tap does)', () async {
    expect(await maintenance.getById(vidangeId), isNotNull);
    expect(await fuel.getById(fuelIds.first), isNotNull);
    expect(await documents.getById(insuranceDocId), isNotNull);
  });

  test('4-6. editing an operation persists and its linked expense amount '
      'updates with it', () async {
    await maintenance.updateEntry(
      id: vidangeId,
      vehicleId: vehicleId,
      category: 'Vidange',
      date: DateTime(2026, 3, 1),
      mileage: 78000,
      laborCost: 350, // was 200
      nextDueMileage: 88000,
    );
    final updated = await maintenance.getById(vidangeId);
    expect(updated!.laborCost, 350);

    final linkedExpense = await (db.select(db.expenses)
          ..where((e) => e.linkedMaintenanceId.equals(vidangeId)))
        .getSingle();
    expect(linkedExpense.amount, 350);
  });

  test('7. mileage stays coherent: the vehicle reflects the highest '
      'recorded operation mileage', () async {
    final vehicle = await vehicles.getOne(vehicleId);
    expect(vehicle.currentMileage, greaterThanOrEqualTo(79000));

    // Correcting an operation's mileage downward must never leave the
    // vehicle's current mileage stale above what history now supports.
    await fuel.updateEntry(
      id: fuelIds.last,
      vehicleId: vehicleId,
      date: DateTime(2026, 2, 21),
      mileage: 78900, // was 79000, now lower than the repair's 79000
      fuelType: 'Diesel',
      quantityLiters: 40,
      pricePerLiter: 12,
    );
    final afterCorrection = await vehicles.getOne(vehicleId);
    // The repair at 79000 km still anchors the current mileage.
    expect(afterCorrection.currentMileage, 79000);
  });

  test('deleting an operation also removes its auto-generated linked '
      'expense, instead of leaving it orphaned in Dépenses', () async {
    final before = await (db.select(db.maintenanceEntries)
          ..where((m) => m.id.equals(vidangeId)))
        .getSingle();
    expect(before.linkedExpenseId, isNotNull);

    await maintenance.softDelete(vidangeId);

    final linkedExpense = await (db.select(db.expenses)
          ..where((e) => e.id.equals(before.linkedExpenseId!)))
        .getSingle();
    expect(linkedExpense.isDeleted, isTrue);

    final visibleExpenses = await expenses.watchForVehicle(vehicleId).first;
    expect(visibleExpenses.any((e) => e.id == before.linkedExpenseId), isFalse);
  });

  test('8. every operation logs a timeline event with the right link', () async {
    final events = await timeline.watchForVehicle(vehicleId).first;
    final vidangeEvent = events.firstWhere((e) => e.linkedEntityId == vidangeId);
    expect(vidangeEvent.moduleOrigin, 'maintenance');
  });

  test('9. changing an operation\'s next-due mileage updates its reminder', () async {
    await maintenance.updateEntry(
      id: vidangeId,
      vehicleId: vehicleId,
      category: 'Vidange',
      date: DateTime(2026, 3, 1),
      mileage: 78000,
      nextDueMileage: 91000, // was 88000
    );
    final active = await reminders.watchActiveForVehicle(vehicleId).first;
    final vidangeReminder = active.firstWhere((r) => r.sourceId == vidangeId);
    expect(vidangeReminder.dueMileage, 91000);
  });

  test('10. nothing created for this vehicle leaks into another', () async {
    final otherEntries = await maintenance.watchForVehicle(otherVehicleId).first;
    final otherDocs = await documents.watchForVehicle(otherVehicleId).first;
    final otherFuel = await fuel.watchForVehicle(otherVehicleId).first;
    final otherExpenses = await expenses.watchForVehicle(otherVehicleId).first;
    expect(otherEntries, isEmpty);
    expect(otherDocs, isEmpty);
    expect(otherFuel, isEmpty);
    expect(otherExpenses, isEmpty);
  });

  test('5. every edit survives an actual app restart (new AppDatabase '
      'instance over the same file, not just the same session)', () async {
    await maintenance.updateEntry(
      id: vidangeId,
      vehicleId: vehicleId,
      category: 'Vidange',
      date: DateTime(2026, 3, 1),
      mileage: 78000,
      laborCost: 777,
      comments: 'Modifié avant redémarrage',
    );
    await db.close();

    // Simulate the app restarting: a brand new AppDatabase over the same
    // on-disk file, not the in-memory connection the rest of the test used.
    db = AppDatabase(NativeDatabase(dbFile));
    wireRepositories();

    final reloaded = await maintenance.getById(vidangeId);
    expect(reloaded, isNotNull);
    expect(reloaded!.laborCost, 777);
    expect(reloaded.comments, 'Modifié avant redémarrage');

    final vehicle = await vehicles.getOne(vehicleId);
    expect(vehicle.brand, 'Audi');

    final allMaintenance = await maintenance.watchForVehicle(vehicleId).first;
    expect(allMaintenance, hasLength(3));
  });
}
