import 'package:autocarnet/core/database/database.dart';
import 'package:autocarnet/features/audit/data/audit_repository.dart';
import 'package:autocarnet/features/expenses/data/expense_repository.dart';
import 'package:autocarnet/features/maintenance/data/maintenance_repository.dart';
import 'package:autocarnet/features/reminders/data/reminder_repository.dart';
import 'package:autocarnet/features/timeline/data/timeline_repository.dart';
import 'package:autocarnet/features/vehicles/data/vehicle_repository.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

/// TEST 22 from the cahier des charges: a simple "Montant" (no itemized
/// parts) must produce exactly one linked expense, kept in sync when the
/// amount is corrected - never a duplicate.
void main() {
  late AppDatabase db;
  late VehicleRepository vehicles;
  late MaintenanceRepository maintenance;
  late ExpenseRepository expenses;
  late String vehicleId;

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    final audit = AuditRepository(db);
    final timeline = TimelineRepository(db);
    final reminders = ReminderRepository(db);
    vehicles = VehicleRepository(db, audit, reminders);
    maintenance = MaintenanceRepository(db, timeline, reminders, vehicles);
    expenses = ExpenseRepository(db, timeline);

    vehicleId = await vehicles.createVehicle(
      brand: 'Renault',
      model: 'Clio',
      currentMileage: 88700,
    );
  });

  tearDown(() => db.close());

  test('TEST 22: montant simple (sans pièces) crée exactement une dépense '
      'liée du même montant, sans doublon', () async {
    final id = await maintenance.createEntry(
      vehicleId: vehicleId,
      category: 'Vidange',
      date: DateTime(2026, 8, 16),
      mileage: 88700,
      laborCost: 2500,
    );

    final entry = await maintenance.getById(id);
    expect(entry!.partsCost + entry.laborCost, 2500);

    final allExpenses = await expenses.watchForVehicle(vehicleId).first;
    expect(allExpenses, hasLength(1));
    expect(allExpenses.first.amount, 2500);
    expect(allExpenses.first.linkedMaintenanceId, id);

    final stats = expenses.computeStats(allExpenses);
    expect(stats.totalAll, 2500);
  });

  test('correcting the montant (2500 -> 2800) updates the linked expense in '
      'place - it never creates a second one', () async {
    final id = await maintenance.createEntry(
      vehicleId: vehicleId,
      category: 'Vidange',
      date: DateTime(2026, 8, 16),
      mileage: 88700,
      laborCost: 2500,
    );

    await maintenance.updateEntry(
      id: id,
      vehicleId: vehicleId,
      category: 'Vidange',
      date: DateTime(2026, 8, 16),
      mileage: 88700,
      laborCost: 2800,
    );

    final allExpenses = await expenses.watchForVehicle(vehicleId).first;
    expect(allExpenses, hasLength(1));
    expect(allExpenses.first.amount, 2800);

    final stats = expenses.computeStats(allExpenses);
    expect(stats.totalAll, 2800);
  });
}
