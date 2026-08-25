import 'dart:io';

import 'package:autocarnet/core/database/database.dart';
import 'package:autocarnet/core/sync/sync_outbox_repository.dart';
import 'package:autocarnet/features/audit/data/audit_repository.dart';
import 'package:autocarnet/features/maintenance/data/maintenance_repository.dart';
import 'package:autocarnet/features/reminders/data/reminder_repository.dart';
import 'package:autocarnet/features/timeline/data/timeline_repository.dart';
import 'package:autocarnet/features/vehicles/data/vehicle_repository.dart';
import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

/// Mission 2026 sync-hardening pass, after the GLC vehicle was lost to an
/// uninstall that happened before it ever reached the cloud. These tests
/// cover exactly what CAN be verified without a live Supabase account (pure
/// local persistence, idempotency, no-duplication) - see the final report
/// for which of the mission's numbered TEST cases still require the user's
/// own device + Supabase SQL editor to confirm (TEST 1, 7, 8: does a row
/// genuinely reach/redownload from the real cloud).
void main() {
  group('TEST 2/3/4 - offline write survives a real app restart, not just '
      'the current session', () {
    late Directory tempDir;
    late File dbFile;
    late AppDatabase db;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('autocarnet_sync_test_');
      dbFile = File('${tempDir.path}/offline.sqlite');
      db = AppDatabase(NativeDatabase(dbFile));
    });

    tearDown(() async {
      await db.close();
      if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
    });

    test('a vehicle created with no Internet (no sync service reachable) is '
        'still on disk, still flagged pendingSync, after the app is fully '
        'closed and reopened', () async {
      final vehicles = VehicleRepository(db, AuditRepository(db), ReminderRepository(db));
      final id = await vehicles.createVehicle(
        brand: 'Mercedes',
        model: 'GLC',
        currentMileage: 42000,
      );

      // Simulate the app being killed and relaunched: a brand new
      // AppDatabase instance over the same on-disk file, not the same
      // in-memory session.
      await db.close();
      db = AppDatabase(NativeDatabase(dbFile));
      final reloadedVehicles = VehicleRepository(db, AuditRepository(db), ReminderRepository(db));

      final vehicle = await reloadedVehicles.getOne(id);
      expect(vehicle.brand, 'Mercedes');
      expect(vehicle.model, 'GLC');
      // Never actually synced - still queued, exactly what makes the next
      // sync pass (whenever connectivity/session comes back) pick it up.
      expect(vehicle.syncStatus, 'pendingSync');
      expect(vehicle.version, 0);
    });

    test('an entretien added offline for that vehicle also survives the '
        'restart and is still queued to reach the cloud', () async {
      final vehicles = VehicleRepository(db, AuditRepository(db), ReminderRepository(db));
      final reminders = ReminderRepository(db);
      final maintenance = MaintenanceRepository(db, TimelineRepository(db), reminders, vehicles);
      final vehicleId =
          await vehicles.createVehicle(brand: 'Audi', model: 'Q5', currentMileage: 80000);
      final entryId = await maintenance.createEntry(
        vehicleId: vehicleId,
        category: 'Vidange',
        date: DateTime(2026, 1, 10),
        mileage: 80500,
      );

      await db.close();
      db = AppDatabase(NativeDatabase(dbFile));
      final reloadedMaintenance = MaintenanceRepository(
        db,
        TimelineRepository(db),
        ReminderRepository(db),
        VehicleRepository(db, AuditRepository(db), ReminderRepository(db)),
      );

      final entry = await reloadedMaintenance.getById(entryId);
      expect(entry, isNotNull);
      expect(entry!.category, 'Vidange');
      expect(entry.syncStatus, 'pendingSync');
    });
  });

  group('TEST 5/6 - editing/retrying before the cloud confirms never '
      'duplicates anything, and always converges on the latest state', () {
    late AppDatabase db;
    late SyncOutboxRepository outbox;
    late VehicleRepository vehicles;

    setUp(() {
      db = AppDatabase(NativeDatabase.memory());
      outbox = SyncOutboxRepository(db);
      vehicles = VehicleRepository(db, AuditRepository(db), ReminderRepository(db), null, outbox);
    });

    tearDown(() => db.close());

    test('modifying the same vehicle three times before it ever syncs '
        'leaves exactly one pending outbox entry for THIS vehicle, and the '
        'final row matches only the LAST edit', () async {
      final id = await vehicles.createVehicle(
        brand: 'Mercedes',
        model: 'GLC',
        currentMileage: 42000,
      );
      // The create itself already enqueued exactly one outbox row for the
      // vehicle (creating it also seeds an initial mileage entry, which is
      // a genuinely separate pending item - see [_vehicleOutboxCount]).
      expect(await _vehicleOutboxCount(db, id), 1);

      final v1 = await vehicles.getOne(id);
      await vehicles.updateVehicle(v1.copyWith(comments: const Value('Première note')));
      await vehicles.updateVehicle(v1.copyWith(comments: const Value('Deuxième note')));
      await vehicles.updateVehicle(v1.copyWith(comments: const Value('Note finale')));

      // Still one row for this vehicle in the outbox - upserted in place,
      // never appended.
      expect(await _vehicleOutboxCount(db, id), 1);

      final finalVehicle = await vehicles.getOne(id);
      expect(finalVehicle.comments, 'Note finale');
      expect(finalVehicle.syncStatus, 'pendingSync');
    });

    test('calling softDelete twice on the same vehicle never duplicates the '
        'outbox entry either', () async {
      final id = await vehicles.createVehicle(
        brand: 'Renault',
        model: 'Clio',
        currentMileage: 10000,
      );
      await vehicles.softDelete(id);
      await vehicles.softDelete(id);

      expect(await _vehicleOutboxCount(db, id), 1);
      final vehicle = await vehicles.getOne(id);
      expect(vehicle.isDeleted, isTrue);
      expect(vehicle.syncStatus, 'pendingSync');
    });
  });

  group('regression: sync-hardening pass fixed real pre-existing bugs where '
      'a write never re-flagged syncStatus, so an already-synced row would '
      'silently never reach the cloud again', () {
    late AppDatabase db;
    late SyncOutboxRepository outbox;
    late VehicleRepository vehicles;

    setUp(() {
      db = AppDatabase(NativeDatabase.memory());
      outbox = SyncOutboxRepository(db);
      vehicles = VehicleRepository(db, AuditRepository(db), ReminderRepository(db), null, outbox);
    });

    tearDown(() => db.close());

    test('updateOperationMileage re-flags an already-synced mileage entry '
        'AND the vehicle itself back to pendingSync, and enqueues both in '
        'the outbox', () async {
      final id = await vehicles.createVehicle(
        brand: 'Opel',
        model: 'Astra',
        currentMileage: 100000,
      );
      await vehicles.recordOperationMileage(
        vehicleId: id,
        value: 100500,
        source: 'maintenance',
        sourceId: 'op-1',
      );
      final entryId = (await (db.select(db.mileageEntries)
                ..where((m) => m.source.equals('maintenance') & m.sourceId.equals('op-1')))
              .getSingle())
          .id;

      // Simulate a completed sync pass: everything marked synced, outbox
      // drained, exactly what happens right after a real push confirms -
      // including the initial mileage entry createVehicle also seeded,
      // which this scenario doesn't otherwise care about.
      await (db.update(db.vehicles)..where((v) => v.id.equals(id)))
          .write(const VehiclesCompanion(syncStatus: Value('synced'), version: Value(1)));
      await db.update(db.mileageEntries).write(const MileageEntriesCompanion(
            syncStatus: Value('synced'),
          ));
      await (db.delete(db.syncOutbox)).go();
      expect(await outbox.pendingCount(), 0);

      // Correcting the value after that point must re-flag everything -
      // this was the exact bug: neither the entry nor the vehicle used to
      // get re-marked pendingSync here.
      await vehicles.updateOperationMileage(
        vehicleId: id,
        source: 'maintenance',
        sourceId: 'op-1',
        newValue: 100750,
      );

      final entry =
          await (db.select(db.mileageEntries)..where((m) => m.id.equals(entryId))).getSingle();
      expect(entry.syncStatus, 'pendingSync');
      expect(entry.value, 100750);

      final vehicle = await vehicles.getOne(id);
      expect(vehicle.syncStatus, 'pendingSync');
      expect(vehicle.currentMileage, 100750);

      expect(await outbox.pendingCount(), 2);
    });

    test('backfillMissingCardColors re-flags an already-synced vehicle back '
        'to pendingSync when it assigns a colour, and enqueues + nudges '
        'sync (it used to do neither)', () async {
      final id = await vehicles.createVehicle(
        brand: 'Dacia',
        model: 'Duster',
        currentMileage: 5000,
      );
      // Simulate: already synced, then the colour column is cleared
      // (mirrors a legacy row created before this feature existed).
      await (db.update(db.vehicles)..where((v) => v.id.equals(id))).write(
        const VehiclesCompanion(
          cardColorKey: Value(null),
          syncStatus: Value('synced'),
          version: Value(1),
        ),
      );
      await (db.delete(db.syncOutbox)).go();
      expect(await outbox.pendingCount(), 0);

      await vehicles.backfillMissingCardColors();

      final vehicle = await vehicles.getOne(id);
      expect(vehicle.cardColorKey, isNotNull);
      expect(vehicle.syncStatus, 'pendingSync');
      expect(await outbox.pendingCount(), 1);
    });
  });

  group('a linked cross-table write (an operation + its auto-generated '
      'expense) enqueues BOTH entities, not just the one the caller named', () {
    test('creating a maintenance entry with a linked expense enqueues both '
        '"maintenance" and "expense" outbox rows', () async {
      final db = AppDatabase(NativeDatabase.memory());
      final outbox = SyncOutboxRepository(db);
      final reminders = ReminderRepository(db);
      final vehicles = VehicleRepository(db, AuditRepository(db), reminders);
      final maintenance =
          MaintenanceRepository(db, TimelineRepository(db), reminders, vehicles, null, outbox);

      final vehicleId =
          await vehicles.createVehicle(brand: 'Peugeot', model: '208', currentMileage: 20000);
      await maintenance.createEntry(
        vehicleId: vehicleId,
        category: 'Vidange',
        date: DateTime(2026, 2, 1),
        mileage: 20500,
        laborCost: 400,
      );

      final pendingByType = <String, int>{};
      for (final row in await (db.select(db.syncOutbox)).get()) {
        pendingByType[row.entityType] = (pendingByType[row.entityType] ?? 0) + 1;
      }
      expect(pendingByType['maintenance'], 1);
      expect(pendingByType['expense'], 1);

      await db.close();
    });
  });
}

/// How many outbox rows exist for a specific vehicle - deliberately
/// narrower than [SyncOutboxRepository.pendingCount] (which counts every
/// entity type at once): creating a vehicle also seeds a genuinely
/// separate mileage-entry outbox row, so asserting "no duplication" must
/// scope to the one entity actually being edited.
Future<int> _vehicleOutboxCount(AppDatabase db, String vehicleId) async {
  final rows = await (db.select(db.syncOutbox)
        ..where((o) => o.entityType.equals('vehicle') & o.entityId.equals(vehicleId)))
      .get();
  return rows.length;
}
