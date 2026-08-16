import 'package:autocarnet/core/database/database.dart';
import 'package:autocarnet/features/expenses/data/expense_repository.dart';
import 'package:autocarnet/features/fuel/data/fuel_repository.dart';
import 'package:autocarnet/features/maintenance/data/maintenance_repository.dart';
import 'package:autocarnet/features/reminders/data/reminder_repository.dart';
import 'package:autocarnet/features/timeline/data/timeline_repository.dart';
import 'package:autocarnet/features/vehicles/data/vehicle_repository.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

/// The profile's currency preference must actually reach every entry
/// created from it (expenses, maintenance, fuel) instead of silently
/// defaulting to MAD everywhere - otherwise the setting is cosmetic.
void main() {
  late AppDatabase db;
  late TimelineRepository timeline;
  late ReminderRepository reminders;
  late VehicleRepository vehicles;
  late ExpenseRepository expenseRepo;
  late MaintenanceRepository maintenanceRepo;
  late FuelRepository fuelRepo;
  late String vehicleId;

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    timeline = TimelineRepository(db);
    reminders = ReminderRepository(db);
    vehicles = VehicleRepository(db, timeline, reminders);
    expenseRepo = ExpenseRepository(db, timeline);
    maintenanceRepo = MaintenanceRepository(db, timeline, reminders, vehicles);
    fuelRepo = FuelRepository(db, timeline, vehicles);
    vehicleId = await vehicles.createVehicle(
      brand: 'Peugeot',
      model: '208',
      currentMileage: 20000,
    );
  });

  tearDown(() => db.close());

  test('a direct expense is stored with the caller-supplied currency', () async {
    final id = await expenseRepo.createExpense(
      vehicleId: vehicleId,
      category: 'Divers',
      date: DateTime.now(),
      amount: 100,
      currency: 'EUR',
    );
    final expense =
        await (db.select(db.expenses)..where((e) => e.id.equals(id))).getSingle();
    expect(expense.currency, 'EUR');
  });

  test('a maintenance entry and its auto-generated expense both use the '
      'caller-supplied currency', () async {
    final entryId = await maintenanceRepo.createEntry(
      vehicleId: vehicleId,
      category: 'Vidange',
      date: DateTime.now(),
      mileage: 20000,
      currency: 'USD',
      laborCost: 50,
    );
    final entry = await (db.select(db.maintenanceEntries)
          ..where((m) => m.id.equals(entryId)))
        .getSingle();
    expect(entry.currency, 'USD');
    final linkedExpense = await (db.select(db.expenses)
          ..where((e) => e.linkedMaintenanceId.equals(entryId)))
        .getSingle();
    expect(linkedExpense.currency, 'USD');
  });

  test('a fuel entry\'s auto-generated expense uses the caller-supplied '
      'currency', () async {
    final fuelId = await fuelRepo.createEntry(
      vehicleId: vehicleId,
      date: DateTime.now(),
      mileage: 20500,
      fuelType: 'Essence',
      quantityLiters: 40,
      pricePerLiter: 2,
      currency: 'GBP',
    );
    final linkedExpense = await (db.select(db.expenses)
          ..where((e) => e.linkedFuelId.equals(fuelId)))
        .getSingle();
    expect(linkedExpense.currency, 'GBP');
  });

  test('omitting the currency still falls back to MAD (backward compatible '
      'default)', () async {
    final id = await expenseRepo.createExpense(
      vehicleId: vehicleId,
      category: 'Divers',
      date: DateTime.now(),
      amount: 50,
    );
    final expense =
        await (db.select(db.expenses)..where((e) => e.id.equals(id))).getSingle();
    expect(expense.currency, 'MAD');
  });
}
