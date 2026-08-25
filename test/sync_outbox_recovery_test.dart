import 'dart:io';

import 'package:autocarnet/core/database/database.dart';
import 'package:autocarnet/core/notifications/notification_repository.dart';
import 'package:autocarnet/core/sync/conflict_repository.dart';
import 'package:autocarnet/core/sync/document_sync_service.dart';
import 'package:autocarnet/core/sync/expense_sync_service.dart';
import 'package:autocarnet/core/sync/frequency_pref_sync_service.dart';
import 'package:autocarnet/core/sync/fuel_sync_service.dart';
import 'package:autocarnet/core/sync/maintenance_sync_service.dart';
import 'package:autocarnet/core/sync/mileage_sync_service.dart';
import 'package:autocarnet/core/sync/provider_sync_service.dart';
import 'package:autocarnet/core/sync/reminder_sync_service.dart';
import 'package:autocarnet/core/sync/sync_coordinator.dart';
import 'package:autocarnet/core/sync/sync_outbox_repository.dart';
import 'package:autocarnet/core/sync/vehicle_sync_service.dart';
import 'package:autocarnet/features/audit/data/audit_repository.dart';
import 'package:autocarnet/features/expenses/data/expense_repository.dart';
import 'package:autocarnet/features/fuel/data/fuel_repository.dart';
import 'package:autocarnet/features/maintenance/data/maintenance_repository.dart';
import 'package:autocarnet/features/reminders/data/reminder_repository.dart';
import 'package:autocarnet/features/timeline/data/timeline_repository.dart';
import 'package:autocarnet/features/vehicles/data/vehicle_repository.dart';
import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Mission 2026, second sync-hardening round: the outbox must be a REAL
/// recovery mechanism, not just a diagnostic ledger - and every synced
/// write must be genuinely atomic with its outbox entry (a single Drift
/// transaction), not merely "logically" sequential. These tests exercise
/// both without ever needing a live Supabase project: every *SyncService
/// here is built with a real (but unauthenticated - no session, no actual
/// HTTP call ever fires) SupabaseClient, so [SyncCoordinator.syncAll]'s
/// own `if (_client.auth.currentSession == null) return;` guard makes the
/// push/pull half of every pass a safe no-op, while the outbox
/// reconciliation logic under test runs for real against the local
/// database - exactly what a genuinely offline device does.
void main() {
  /// Builds a real SyncCoordinator wired to the given [db] and [outbox],
  /// with every *SyncService pointed at a SupabaseClient that has no
  /// session - so syncAll()'s push/pull always no-ops safely, and only the
  /// outbox-reconciliation logic actually touches the database.
  SyncCoordinator buildCoordinator(AppDatabase db, SyncOutboxRepository outbox) {
    final client = SupabaseClient('https://example.invalid.supabase.co', 'anon-key-test');
    final conflicts = ConflictRepository(db);
    final timeline = TimelineRepository(db);
    return SyncCoordinator(
      db: db,
      clientFn: () => client,
      vehicles: VehicleSyncService(db, () => client, conflicts, outbox),
      maintenance: MaintenanceSyncService(db, () => client, conflicts, timeline, outbox),
      expenses: ExpenseSyncService(db, () => client, conflicts, outbox),
      fuel: FuelSyncService(db, () => client, conflicts, timeline, outbox),
      documents: DocumentSyncService(db, () => client, conflicts, timeline, outbox),
      reminders: ReminderSyncService(db, () => client, conflicts, outbox),
      mileage: MileageSyncService(db, () => client, outbox),
      frequencyPrefs: FrequencyPrefSyncService(db, () => client, conflicts, outbox),
      providers: ProviderSyncService(db, () => client, conflicts, outbox),
      notifications: NotificationRepository(db),
      conflicts: conflicts,
    );
  }

  group('TEST outbox = real recovery mechanism (mission point 2): '
      'resyncNow() replays from the outbox itself, not just an '
      'opportunistic syncStatus scan', () {
    late AppDatabase db;
    late SyncOutboxRepository outbox;
    late VehicleRepository vehicles;

    setUp(() {
      db = AppDatabase(NativeDatabase.memory());
      outbox = SyncOutboxRepository(db);
      vehicles = VehicleRepository(db, AuditRepository(db), ReminderRepository(db), null, outbox);
    });

    tearDown(() => db.close());

    test('a vehicle whose syncStatus somehow drifted to "synced" while its '
        'outbox entry was never cleared gets forced back to pendingSync by '
        'resyncNow(), so it is never silently forgotten', () async {
      final id = await vehicles.createVehicle(
        brand: 'Peugeot',
        model: '308',
        currentMileage: 15000,
      );

      // Simulate the exact drift this mechanism guards against: the
      // entity's own syncStatus says "synced" (e.g. a bug, an interrupted
      // push that half-applied) but the outbox row is still there,
      // because it was never told to markSynced.
      await (db.update(db.vehicles)..where((v) => v.id.equals(id)))
          .write(const VehiclesCompanion(syncStatus: Value('synced')));
      final beforeReconcile = await vehicles.getOne(id);
      expect(beforeReconcile.syncStatus, 'synced');
      expect(await outbox.pendingCount(), greaterThan(0));

      final coordinator = buildCoordinator(db, outbox);
      await coordinator.resyncNow();

      final afterReconcile = await vehicles.getOne(id);
      expect(afterReconcile.syncStatus, 'pendingSync');
    });

    test('the same self-healing applies to a mileage entry, keyed by its '
        'own outbox entityType', () async {
      final id = await vehicles.createVehicle(
        brand: 'Renault',
        model: 'Mégane',
        currentMileage: 30000,
      );
      final mileageId =
          (await (db.select(db.mileageEntries)..where((m) => m.vehicleId.equals(id)))
                  .getSingle())
              .id;
      await (db.update(db.mileageEntries)..where((m) => m.id.equals(mileageId)))
          .write(const MileageEntriesCompanion(syncStatus: Value('synced')));

      final coordinator = buildCoordinator(db, outbox);
      await coordinator.resyncNow();

      final entry =
          await (db.select(db.mileageEntries)..where((m) => m.id.equals(mileageId))).getSingle();
      expect(entry.syncStatus, 'pendingSync');
    });
  });

  group('TEST 2/3/4 (crash before any sync attempt) for entretien, plein et '
      'dépense - same principle as VehicleRepository, applied to every '
      'other synced module the mission names explicitly', () {
    late Directory tempDir;
    late File dbFile;
    late AppDatabase db;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('autocarnet_recovery_test_');
      dbFile = File('${tempDir.path}/offline.sqlite');
      db = AppDatabase(NativeDatabase(dbFile));
    });

    tearDown(() async {
      await db.close();
      if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
    });

    test('an entretien (maintenance entry) added offline survives the app '
        'being fully closed and reopened, still queued to reach the cloud',
        () async {
      final vehicles = VehicleRepository(db, AuditRepository(db), ReminderRepository(db));
      final reminders = ReminderRepository(db);
      final timeline = TimelineRepository(db);
      final maintenance = MaintenanceRepository(db, timeline, reminders, vehicles);
      final vehicleId =
          await vehicles.createVehicle(brand: 'Peugeot', model: '208', currentMileage: 20000);
      final maintenanceId = await maintenance.createEntry(
        vehicleId: vehicleId,
        category: 'Vidange',
        date: DateTime(2026, 3, 1),
        mileage: 20100,
        laborCost: 150,
      );

      await db.close();
      db = AppDatabase(NativeDatabase(dbFile));
      final reloadedMaintenance = MaintenanceRepository(
        db,
        TimelineRepository(db),
        ReminderRepository(db),
        VehicleRepository(db, AuditRepository(db), ReminderRepository(db)),
      );

      final entry = await reloadedMaintenance.getById(maintenanceId);
      expect(entry, isNotNull);
      expect(entry!.syncStatus, 'pendingSync');
      expect(entry.category, 'Vidange');
    });

    test('a plein (fuel entry) added offline survives the app being fully '
        'closed and reopened, still queued to reach the cloud', () async {
      final vehicles = VehicleRepository(db, AuditRepository(db), ReminderRepository(db));
      final reminders = ReminderRepository(db);
      final fuel = FuelRepository(db, TimelineRepository(db), vehicles, reminders);
      final vehicleId =
          await vehicles.createVehicle(brand: 'Dacia', model: 'Sandero', currentMileage: 40000);
      final fuelId = await fuel.createEntry(
        vehicleId: vehicleId,
        date: DateTime(2026, 3, 1),
        mileage: 40300,
        fuelType: 'Diesel',
        quantityLiters: 45,
        pricePerLiter: 12.5,
      );

      await db.close();
      db = AppDatabase(NativeDatabase(dbFile));
      final reloadedFuel = FuelRepository(
        db,
        TimelineRepository(db),
        VehicleRepository(db, AuditRepository(db), ReminderRepository(db)),
        ReminderRepository(db),
      );

      final entry = await reloadedFuel.getById(fuelId);
      expect(entry, isNotNull);
      expect(entry!.syncStatus, 'pendingSync');
      expect(entry.quantityLiters, 45);
    });

    test('a dépense added offline survives the same crash-before-sync '
        'scenario', () async {
      final vehicles = VehicleRepository(db, AuditRepository(db), ReminderRepository(db));
      final expenses = ExpenseRepository(db, TimelineRepository(db));
      final vehicleId =
          await vehicles.createVehicle(brand: 'Fiat', model: 'Panda', currentMileage: 5000);
      final expenseId = await expenses.createExpense(
        vehicleId: vehicleId,
        category: 'Lavage',
        date: DateTime(2026, 3, 2),
        amount: 80,
      );

      await db.close();
      db = AppDatabase(NativeDatabase(dbFile));
      final reloadedExpenses = ExpenseRepository(db, TimelineRepository(db));

      final expense = await reloadedExpenses.getById(expenseId);
      expect(expense, isNotNull);
      expect(expense!.syncStatus, 'pendingSync');
      expect(expense.amount, 80);
    });

    test('a manual kilométrage correction added offline survives the same '
        'crash-before-sync scenario', () async {
      final vehicles = VehicleRepository(db, AuditRepository(db), ReminderRepository(db));
      final vehicleId =
          await vehicles.createVehicle(brand: 'Toyota', model: 'Yaris', currentMileage: 12000);
      await vehicles.recordManualMileage(vehicleId, 12500, note: 'Relevé manuel');

      await db.close();
      db = AppDatabase(NativeDatabase(dbFile));
      final reloadedVehicles = VehicleRepository(db, AuditRepository(db), ReminderRepository(db));

      final vehicle = await reloadedVehicles.getOne(vehicleId);
      expect(vehicle.currentMileage, 12500);
      expect(vehicle.syncStatus, 'pendingSync');
      final mileageRows =
          await (db.select(db.mileageEntries)..where((m) => m.vehicleId.equals(vehicleId))).get();
      expect(mileageRows.any((m) => m.value == 12500 && m.syncStatus == 'pendingSync'), isTrue);
    });
  });

  group('TEST (modifier une donnée déjà synchronisée puis tuer '
      'l\'application) - exact mission scenario: create -> synchronize -> '
      'modify -> crash -> restart', () {
    late Directory tempDir;
    late File dbFile;
    late AppDatabase db;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('autocarnet_recovery_test_');
      dbFile = File('${tempDir.path}/offline.sqlite');
      db = AppDatabase(NativeDatabase(dbFile));
    });

    tearDown(() async {
      await db.close();
      if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
    });

    test('a kilométrage correction on an ALREADY-SYNCED vehicle is still '
        'pendingSync after an immediate crash and restart', () async {
      final vehicles = VehicleRepository(db, AuditRepository(db), ReminderRepository(db));
      final vehicleId =
          await vehicles.createVehicle(brand: 'Kia', model: 'Sportage', currentMileage: 60000);

      // Simulate "synchronize": a real push confirmed this exact state -
      // never anything the app itself needs to fake beyond the DB columns
      // a real *SyncService would have written.
      await (db.update(db.vehicles)..where((v) => v.id.equals(vehicleId)))
          .write(const VehiclesCompanion(syncStatus: Value('synced'), version: Value(1)));

      // Modify, then crash immediately - no sync pass, no network call,
      // nothing beyond the local write itself gets to run.
      await vehicles.recordManualMileage(vehicleId, 60250);
      await db.close();

      // Restart: brand new AppDatabase over the same file.
      db = AppDatabase(NativeDatabase(dbFile));
      final reloadedVehicles = VehicleRepository(db, AuditRepository(db), ReminderRepository(db));

      final vehicle = await reloadedVehicles.getOne(vehicleId);
      expect(vehicle.currentMileage, 60250);
      expect(vehicle.syncStatus, 'pendingSync');
    });
  });

  group('TEST suppression (tombstone) - synced vehicle deleted offline '
      'survives a restart, still queued, and never resurfaces locally', () {
    late Directory tempDir;
    late File dbFile;
    late AppDatabase db;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('autocarnet_recovery_test_');
      dbFile = File('${tempDir.path}/offline.sqlite');
      db = AppDatabase(NativeDatabase(dbFile));
    });

    tearDown(() async {
      await db.close();
      if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
    });

    test('softDelete on a synced vehicle, then an immediate crash, still '
        'has the tombstone queued after restart, and the vehicle stays '
        'invisible locally', () async {
      final outbox = SyncOutboxRepository(db);
      final vehicles =
          VehicleRepository(db, AuditRepository(db), ReminderRepository(db), null, outbox);
      final vehicleId =
          await vehicles.createVehicle(brand: 'Hyundai', model: 'Tucson', currentMileage: 70000);
      await (db.update(db.vehicles)..where((v) => v.id.equals(vehicleId)))
          .write(const VehiclesCompanion(syncStatus: Value('synced'), version: Value(1)));
      // Simulate "synchronize" fully: a real push would also have cleared
      // this vehicle's own outbox trace (markSynced) - without doing that
      // here too, the pre-existing create row would still be sitting there
      // and this test would no longer be isolating what softDelete itself
      // enqueues.
      await outbox.markSynced('vehicle', vehicleId);

      await vehicles.softDelete(vehicleId);
      await db.close();

      db = AppDatabase(NativeDatabase(dbFile));
      final reloadedVehicles = VehicleRepository(db, AuditRepository(db), ReminderRepository(db));

      final vehicle = await reloadedVehicles.getOne(vehicleId);
      expect(vehicle.isDeleted, isTrue);
      expect(vehicle.syncStatus, 'pendingSync');

      final visible = await reloadedVehicles.watchAll().first;
      expect(visible.any((v) => v.id == vehicleId), isFalse);

      final outboxRows = await (db.select(db.syncOutbox)
            ..where((o) => o.entityType.equals('vehicle') & o.entityId.equals(vehicleId)))
          .get();
      expect(outboxRows, hasLength(1));
      expect(outboxRows.single.operation, 'delete');
      // Note: that this tombstone can never be resurrected by a later
      // cloud PULL once it does reach Supabase is guaranteed by the
      // pre-existing OCC version compare-and-swap (newerRemoteRows only
      // ever applies a remote row whose version is strictly greater than
      // what this device already has - see occ_sync_test.dart), not by
      // anything new in this pass; this test covers what IS new here:
      // the delete intent itself surviving a real app restart.
    });
  });
}
