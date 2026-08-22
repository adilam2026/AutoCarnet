import 'dart:convert';

import 'package:autocarnet/core/database/database.dart';
import 'package:autocarnet/core/notifications/notification_repository.dart';
import 'package:autocarnet/core/sync/conflict_repository.dart';
import 'package:autocarnet/core/sync/conflict_resolution_service.dart';
import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('ConflictResolutionService', () {
    late AppDatabase db;
    late ConflictRepository conflicts;
    late ConflictResolutionService resolution;

    setUp(() {
      db = AppDatabase(NativeDatabase.memory());
      conflicts = ConflictRepository(db);
      resolution = ConflictResolutionService(db, conflicts);
    });
    tearDown(() => db.close());

    Future<String> seedConflictedVehicle() async {
      final now = DateTime.utc(2026, 1, 1);
      await db.into(db.vehicles).insert(VehiclesCompanion.insert(
            id: 'v1',
            brand: 'Renault',
            model: 'Clio',
            currentMileage: 50000,
            createdAt: now,
            updatedAt: now,
            syncStatus: const Value('conflict'),
            version: const Value(3),
          ));
      final localSnapshot = {'brand': 'Renault', 'model': 'Clio', 'current_mileage': 50000.0};
      final remoteSnapshot = {
        'id': 'v1',
        'brand': 'Renault',
        'model': 'Clio Sport',
        'current_mileage': 51000.0,
        'created_at': now.toIso8601String(),
        'updated_at': now.toIso8601String(),
        'version': 4,
        'user_id': 'other-user',
      };
      await conflicts.record(
        table: 'vehicles',
        recordId: 'v1',
        vehicleId: 'v1',
        localSnapshot: localSnapshot,
        remoteSnapshot: remoteSnapshot,
        remoteUpdatedBy: 'other-user',
      );
      final rows = await conflicts.unresolvedIdsFor('vehicles');
      expect(rows, contains('v1'));
      return 'v1';
    }

    test('keepServerVersion overwrites the local row with the remote snapshot', () async {
      await seedConflictedVehicle();
      final unresolved = await db.select(db.syncConflicts).get();
      final conflict = unresolved.single;

      await resolution.keepServerVersion(conflict);

      final vehicle = await (db.select(db.vehicles)..where((v) => v.id.equals('v1'))).getSingle();
      expect(vehicle.model, 'Clio Sport');
      expect(vehicle.currentMileage, 51000.0);
      expect(vehicle.version, 4);
      expect(vehicle.syncStatus, 'synced');

      final stillUnresolved = await conflicts.unresolvedIdsFor('vehicles');
      expect(stillUnresolved, isEmpty);
    });

    test('keepLocalVersion re-arms the local row for push at the server version', () async {
      await seedConflictedVehicle();
      final unresolved = await db.select(db.syncConflicts).get();
      final conflict = unresolved.single;

      await resolution.keepLocalVersion(conflict);

      final vehicle = await (db.select(db.vehicles)..where((v) => v.id.equals('v1'))).getSingle();
      // The owner's own fields are untouched - only the sync bookkeeping
      // changes, so the next push carries the local edit forward.
      expect(vehicle.model, 'Clio');
      expect(vehicle.currentMileage, 50000.0);
      expect(vehicle.version, 4);
      expect(vehicle.syncStatus, 'pendingSync');

      final stillUnresolved = await conflicts.unresolvedIdsFor('vehicles');
      expect(stillUnresolved, isEmpty);
    });
  });

  group('NotificationRepository', () {
    late AppDatabase db;
    late NotificationRepository notifications;

    setUp(() {
      db = AppDatabase(NativeDatabase.memory());
      notifications = NotificationRepository(db);
    });
    tearDown(() => db.close());

    test('a new notification is unread until explicitly marked', () async {
      await notifications.add(
        accountId: 'me',
        type: AppNotificationType.remoteEdit,
        title: 'Un entretien a été modifié',
        vehicleId: 'v1',
      );

      final unreadCount = await notifications.watchUnreadCountFor('me').first;
      expect(unreadCount, 1);

      final all = await notifications.watchAllFor('me').first;
      await notifications.markRead(all.single.id);

      final unreadAfter = await notifications.watchUnreadCountFor('me').first;
      expect(unreadAfter, 0);
    });

    test('markAllRead clears every unread notification for the account, not another one\'s',
        () async {
      await notifications.add(accountId: 'me', type: AppNotificationType.remoteEdit, title: 'A');
      await notifications.add(accountId: 'me', type: AppNotificationType.remoteEdit, title: 'B');
      await notifications.add(
          accountId: 'someone-else', type: AppNotificationType.remoteEdit, title: 'C');

      await notifications.markAllRead('me');

      expect(await notifications.watchUnreadCountFor('me').first, 0);
      expect(await notifications.watchUnreadCountFor('someone-else').first, 1);
    });
  });

  group('ConflictRepository', () {
    test('recording the same still-unresolved conflict twice refreshes it instead of duplicating',
        () async {
      final db = AppDatabase(NativeDatabase.memory());
      addTearDown(db.close);
      final conflicts = ConflictRepository(db);

      await conflicts.record(
        table: 'expenses',
        recordId: 'e1',
        vehicleId: 'v1',
        localSnapshot: {'amount': 100},
        remoteSnapshot: {'amount': 200, 'version': 2},
        remoteUpdatedBy: 'user-a',
      );
      await conflicts.record(
        table: 'expenses',
        recordId: 'e1',
        vehicleId: 'v1',
        localSnapshot: {'amount': 100},
        remoteSnapshot: {'amount': 250, 'version': 3},
        remoteUpdatedBy: 'user-b',
      );

      final rows = await db.select(db.syncConflicts).get();
      expect(rows, hasLength(1));
      final remote = jsonDecode(rows.single.remoteSnapshotJson) as Map<String, dynamic>;
      expect(remote['amount'], 250);
      expect(rows.single.remoteUpdatedBy, 'user-b');
    });
  });
}
