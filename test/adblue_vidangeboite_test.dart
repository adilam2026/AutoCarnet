import 'package:autocarnet/core/database/database.dart';
import 'package:autocarnet/features/audit/data/audit_repository.dart';
import 'package:autocarnet/features/fuel/data/fuel_repository.dart';
import 'package:autocarnet/features/fuel/domain/adblue_rules.dart';
import 'package:autocarnet/features/maintenance/data/maintenance_repository.dart';
import 'package:autocarnet/features/reminders/data/reminder_repository.dart';
import 'package:autocarnet/features/timeline/data/timeline_repository.dart';
import 'package:autocarnet/features/vehicles/data/vehicle_repository.dart';
import 'package:drift/drift.dart' hide isNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

/// Mission 2026 mandatory tests 3, 4, 6, 7, 8, 9, 10 (AdBlue + "Vidange
/// boîte de vitesses"). TEST 1/2 (date mask) live in date_field_test.dart,
/// TEST 5 (no AdBlue alert for an essence vehicle) lives in
/// add_operation_sheet_adblue_test.dart since it's a UI-reachability
/// guarantee, not a repository one.
void main() {
  late AppDatabase db;
  late VehicleRepository vehicles;
  late ReminderRepository reminders;
  late FuelRepository fuel;
  late MaintenanceRepository maintenance;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    final audit = AuditRepository(db);
    final timeline = TimelineRepository(db);
    reminders = ReminderRepository(db);
    vehicles = VehicleRepository(db, audit, reminders);
    fuel = FuelRepository(db, timeline, vehicles, reminders);
    maintenance = MaintenanceRepository(db, timeline, reminders, vehicles);
  });

  tearDown(() => db.close());

  Future<String> createDiesel({double mileage = 80000}) => vehicles.createVehicle(
        brand: 'Peugeot',
        model: '3008',
        currentMileage: mileage,
        fuelType: 'Diesel',
      );

  test(
    'TEST 3: recording an AdBlue fill-up at 86 950 km sets its échéance '
    'estimate to 96 950 km (86 950 + AutoCarnet\'s 10 000 km default range)',
    () async {
      final vehicleId = await createDiesel(mileage: 86950);
      await fuel.createEntry(
        vehicleId: vehicleId,
        date: DateTime(2026, 8, 25),
        mileage: 86950,
        fuelType: adblueFuelType,
        quantityLiters: 5,
        pricePerLiter: 0,
        totalAmountOverride: 400,
      );

      final active = await reminders.watchActiveForVehicle(vehicleId).first;
      final adblueReminder = active.singleWhere((r) => r.sourceType == 'adblue');
      expect(adblueReminder.dueMileage, 96950);
      expect(adblueReminder.title, 'AdBlue à prévoir');
    },
  );

  test(
    'TEST 4: an AdBlue fill-up never affects fuel consumption/cost stats - '
    'they are computed as if it never happened',
    () async {
      final vehicleId = await createDiesel(mileage: 80000);
      // Two real Diesel full tanks 500 km apart, 40 L consumed between them.
      await fuel.createEntry(
        vehicleId: vehicleId,
        date: DateTime(2026, 1, 1),
        mileage: 80000,
        fuelType: 'Diesel',
        quantityLiters: 50,
        pricePerLiter: 12,
        isFullTank: true,
      );
      await fuel.createEntry(
        vehicleId: vehicleId,
        date: DateTime(2026, 2, 1),
        mileage: 80500,
        fuelType: 'Diesel',
        quantityLiters: 40,
        pricePerLiter: 12,
        isFullTank: true,
      );
      final withoutAdblue = fuel.computeStats(
        await fuel.watchForVehicle(vehicleId).first,
      );
      expect(withoutAdblue.averageConsumption, closeTo(8.0, 0.001));
      expect(withoutAdblue.totalLiters, 90);
      expect(withoutAdblue.totalCost, 90 * 12);

      // An AdBlue fill-up logged in between, at real intermediate mileage.
      await fuel.createEntry(
        vehicleId: vehicleId,
        date: DateTime(2026, 1, 15),
        mileage: 80250,
        fuelType: adblueFuelType,
        quantityLiters: 5,
        pricePerLiter: 0,
        totalAmountOverride: 400,
      );

      final withAdblue = fuel.computeStats(
        await fuel.watchForVehicle(vehicleId).first,
      );
      expect(withAdblue.averageConsumption, withoutAdblue.averageConsumption);
      expect(withAdblue.totalLiters, withoutAdblue.totalLiters,
          reason: 'AdBlue litres must never be added to fuel litres');
      expect(withAdblue.totalCost, withoutAdblue.totalCost,
          reason: 'AdBlue spend must never be added to fuel cost');
    },
  );

  test(
    'TEST 6: "Vidange boîte de vitesses" is saved and read back as its own '
    'distinct operation, never merged with "Vidange" or "Révision"',
    () async {
      final vehicleId = await createDiesel();
      await maintenance.createEntry(
        vehicleId: vehicleId,
        category: 'Vidange boîte de vitesses',
        date: DateTime(2026, 8, 25),
        currency: 'MAD',
        mileage: 86950,
        laborCost: 2500,
      );

      final all = await maintenance.watchForVehicle(vehicleId).first;
      expect(all, hasLength(1));
      expect(all.single.category, 'Vidange boîte de vitesses');
    },
  );

  test(
    'TEST 7: recording a "Vidange boîte de vitesses" never touches the '
    'échéance already active for "Vidange" (engine oil)',
    () async {
      final vehicleId = await createDiesel(mileage: 80000);
      await maintenance.createEntry(
        vehicleId: vehicleId,
        category: 'Vidange',
        date: DateTime(2026, 1, 1),
        currency: 'MAD',
        mileage: 80000,
        laborCost: 300,
        nextDueMileage: 90000,
      );

      await maintenance.createEntry(
        vehicleId: vehicleId,
        category: 'Vidange boîte de vitesses',
        date: DateTime(2026, 8, 25),
        currency: 'MAD',
        mileage: 86950,
        laborCost: 2500,
      );

      final active = await reminders.watchActiveForVehicle(vehicleId).first;
      final vidangeMoteur = active.singleWhere((r) => r.title == 'Vidange à prévoir');
      expect(vidangeMoteur.dueMileage, 90000);
    },
  );

  test(
    'TEST 8: recording a "Vidange boîte de vitesses" never touches the '
    'échéance already active for "Révision"',
    () async {
      final vehicleId = await createDiesel(mileage: 80000);
      await maintenance.createEntry(
        vehicleId: vehicleId,
        category: 'Révision',
        date: DateTime(2026, 1, 1),
        currency: 'MAD',
        mileage: 80000,
        laborCost: 1200,
        nextDueMileage: 90000,
      );

      await maintenance.createEntry(
        vehicleId: vehicleId,
        category: 'Vidange boîte de vitesses',
        date: DateTime(2026, 8, 25),
        currency: 'MAD',
        mileage: 86950,
        laborCost: 2500,
      );

      final active = await reminders.watchActiveForVehicle(vehicleId).first;
      final revision = active.singleWhere((r) => r.title == 'Révision à prévoir');
      expect(revision.dueMileage, 90000);
      // And "Vidange boîte de vitesses" has its own, independent track -
      // no échéance was invented for it (mission point 7: no arbitrary
      // universal periodicity), so it never shows up in active reminders.
      expect(active.where((r) => r.title.contains('boîte')), isEmpty);
    },
  );

  test(
    'TEST 9: both an AdBlue fill-up and a "Vidange boîte de vitesses" '
    'generate their own linked expense, each with its own distinct category',
    () async {
      final vehicleId = await createDiesel(mileage: 80000);
      await fuel.createEntry(
        vehicleId: vehicleId,
        date: DateTime(2026, 8, 25),
        mileage: 86950,
        fuelType: adblueFuelType,
        quantityLiters: 5,
        pricePerLiter: 0,
        totalAmountOverride: 400,
      );
      await maintenance.createEntry(
        vehicleId: vehicleId,
        category: 'Vidange boîte de vitesses',
        date: DateTime(2026, 8, 25),
        currency: 'MAD',
        mileage: 86950,
        laborCost: 2500,
      );

      final expenses = await (db.select(db.expenses)
            ..where((e) => e.vehicleId.equals(vehicleId) & e.isDeleted.equals(false)))
          .get();

      final adblueExpense = expenses.singleWhere((e) => e.category == 'AdBlue');
      expect(adblueExpense.amount, 400);

      final boiteExpense =
          expenses.singleWhere((e) => e.category == 'Vidange boîte de vitesses');
      expect(boiteExpense.amount, 2500);

      // Never blended into plain "Carburant"/"Entretien" totals.
      expect(expenses.where((e) => e.category == 'Carburant'), isEmpty);
    },
  );

  test(
    'TEST 10: an empty/omitted comment never blocks recording an AdBlue '
    'fill-up, a "Vidange boîte de vitesses", or a plain maintenance entry',
    () async {
      final vehicleId = await createDiesel(mileage: 80000);

      // No exception thrown, entry actually persisted, comments genuinely
      // null (never coerced into an empty string that would count as
      // "filled in").
      final adblueId = await fuel.createEntry(
        vehicleId: vehicleId,
        date: DateTime(2026, 8, 25),
        mileage: 86950,
        fuelType: adblueFuelType,
        quantityLiters: 5,
        pricePerLiter: 0,
        totalAmountOverride: 400,
        comments: null,
      );
      final savedAdblue = await fuel.getById(adblueId);
      expect(savedAdblue!.comments, isNull);

      final boiteId = await maintenance.createEntry(
        vehicleId: vehicleId,
        category: 'Vidange boîte de vitesses',
        date: DateTime(2026, 8, 25),
        currency: 'MAD',
        mileage: 86950,
        laborCost: 2500,
        comments: null,
      );
      final savedBoite = await maintenance.getById(boiteId);
      expect(savedBoite!.comments, isNull);
    },
  );
}
