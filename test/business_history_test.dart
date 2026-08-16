import 'package:autocarnet/core/database/database.dart';
import 'package:autocarnet/features/audit/data/audit_repository.dart';
import 'package:autocarnet/features/maintenance/data/maintenance_repository.dart';
import 'package:autocarnet/features/reminders/data/reminder_repository.dart';
import 'package:autocarnet/features/timeline/data/timeline_repository.dart';
import 'package:autocarnet/features/vehicles/data/vehicle_repository.dart';
import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

/// Cahier des charges bloc 20: business history (what the driver sees on
/// the vehicle dashboard) must never be polluted by data-entry/CRUD facts -
/// those belong to the separate audit trail.
void main() {
  late AppDatabase db;
  late AuditRepository audit;
  late TimelineRepository timeline;
  late ReminderRepository reminders;
  late VehicleRepository vehicles;
  late MaintenanceRepository maintenance;
  late String vehicleId;

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    audit = AuditRepository(db);
    timeline = TimelineRepository(db);
    reminders = ReminderRepository(db);
    vehicles = VehicleRepository(db, audit, reminders);
    maintenance = MaintenanceRepository(db, timeline, reminders, vehicles);

    vehicleId = await vehicles.createVehicle(
      brand: 'Audi',
      model: 'Q5',
      currentMileage: 70000,
    );

    // 2 fiche modifications.
    for (var i = 0; i < 2; i++) {
      final v = await vehicles.getOne(vehicleId);
      await vehicles.updateVehicle(v.copyWith(comments: Value('note $i')));
    }

    // 4 manual mileage updates.
    var mileage = 72000.0;
    for (var i = 0; i < 4; i++) {
      await vehicles.recordManualMileage(vehicleId, mileage);
      mileage += 500;
    }

    // 3 real operations.
    await maintenance.createEntry(
      vehicleId: vehicleId,
      category: 'Vidange',
      date: DateTime(2026, 1, 1),
      mileage: 74000,
    );
    await maintenance.createEntry(
      vehicleId: vehicleId,
      category: 'Révision',
      date: DateTime(2026, 2, 1),
      mileage: 74500,
    );
    await maintenance.createEntry(
      vehicleId: vehicleId,
      category: 'Changement plaquettes',
      date: DateTime(2026, 3, 1),
      mileage: 75000,
    );
  });

  tearDown(() => db.close());

  test('"Dernières opérations" (business history) shows only the 3 real '
      'operations - never vehicle-created, fiche-modifiée or '
      'kilométrage-mis-à-jour', () async {
    final events = await timeline.watchForVehicle(vehicleId).first;
    expect(events, hasLength(3));

    final titles = events.map((e) => e.title).toSet();
    expect(titles, {'Vidange', 'Révision', 'Changement plaquettes'});

    for (final e in events) {
      expect(e.title, isNot(contains('ajouté')));
      expect(e.title, isNot(contains('modifié')));
      expect(e.title, isNot(contains('Kilométrage')));
      expect(e.moduleOrigin, isNot('vehicles'));
    }
  });

  test('vehicle creation, fiche edits and mileage corrections are recorded '
      'as audit facts instead, not lost', () async {
    final auditEvents = await audit.watchForVehicle(vehicleId).first;
    // 1 created + 2 updated + 4 mileage_corrected = 7.
    expect(auditEvents, hasLength(7));
    expect(auditEvents.where((e) => e.action == 'created'), hasLength(1));
    expect(auditEvents.where((e) => e.action == 'updated'), hasLength(2));
    expect(auditEvents.where((e) => e.action == 'mileage_corrected'), hasLength(4));
  });

  test('G. correcting the vehicle mileage never creates a fake business '
      'operation in the historique', () async {
    final before = await timeline.watchForVehicle(vehicleId).first;
    await vehicles.recordManualMileage(vehicleId, 76000);
    final after = await timeline.watchForVehicle(vehicleId).first;
    expect(after.length, before.length);
  });
}
