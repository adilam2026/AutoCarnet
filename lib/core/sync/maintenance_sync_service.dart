import 'package:drift/drift.dart' show Value;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../features/timeline/data/timeline_repository.dart';
import '../database/database.dart';
import '../database/providers.dart';
import '../utils/connectivity.dart';
import 'conflict_repository.dart';
import 'maintenance_sync_mapping.dart';
import 'occ_sync.dart';

/// Same optimistic-concurrency shape as [VehicleSyncService], for
/// `maintenance_entries` (+ its `maintenance_parts` children, which always
/// ride along with the parent since the app replaces a whole entry's parts
/// list on every edit rather than editing one part in place).
///
/// A pulled entry never re-triggers [ReminderRepository.upsertForSource] or
/// [VehicleRepository.recordOperationMileage]: reminders and mileage
/// entries are each synced independently by their own service, so
/// reapplying those side effects here would double them up. The one side
/// effect a pull DOES still need is the timeline entry - timeline_events
/// itself is deliberately never synced (see the migration's header), so
/// without this a collaborator's own device would never show the addition
/// in "Historique".
class MaintenanceSyncService {
  MaintenanceSyncService(this._db, this._client, this._conflicts, this._timeline);
  final AppDatabase _db;
  final SupabaseClient _client;
  final ConflictRepository _conflicts;
  final TimelineRepository _timeline;

  static const _table = 'maintenance_entries';
  bool _syncing = false;

  Future<void> syncNow() async {
    if (_syncing) return;
    if (_client.auth.currentSession == null) return;
    if (!await hasConnectivity()) return;
    _syncing = true;
    try {
      await _push();
      await _pull();
    } catch (_) {
      // Best-effort - a failed pass is silently retried on the next trigger.
    } finally {
      _syncing = false;
    }
  }

  Future<void> _push() async {
    final myUserId = _client.auth.currentUser!.id;
    final pending = await (_db.select(_db.maintenanceEntries)
          ..where((e) => e.syncStatus.equals('pendingSync')))
        .get();
    if (pending.isEmpty) return;

    final result = await pushWithOcc(
      client: _client,
      table: _table,
      rows: [
        for (final e in pending)
          PendingOccRow(
            id: e.id,
            expectedVersion: e.version,
            remoteRow: {
              ...maintenanceEntryToRemoteRow(e),
              'updated_by': myUserId,
              if (e.version == 0) 'created_by': myUserId,
            },
          ),
      ],
    );

    for (final e in pending) {
      final newVersion = result.newVersionByPushedId[e.id];
      if (newVersion != null) {
        await (_db.update(_db.maintenanceEntries)..where((t) => t.id.equals(e.id))).write(
          MaintenanceEntriesCompanion(
            syncStatus: const Value('synced'),
            version: Value(newVersion),
            updatedBy: Value(myUserId),
            createdBy: e.createdBy == null ? Value(myUserId) : const Value.absent(),
          ),
        );
        await _pushParts(e.id);
      } else if (result.conflictedIds.contains(e.id)) {
        final remoteRows = await _client.from(_table).select().eq('id', e.id).limit(1);
        if (remoteRows.isEmpty) continue;
        await _conflicts.record(
          table: _table,
          recordId: e.id,
          vehicleId: e.vehicleId,
          localSnapshot: maintenanceEntryToRemoteRow(e),
          remoteSnapshot: remoteRows.first,
          remoteUpdatedBy: remoteRows.first['updated_by'] as String?,
        );
      }
    }
  }

  /// Parts carry no version of their own (see class doc) - a successful
  /// parent push always replaces the remote parts wholesale with this
  /// device's current local list, exactly mirroring what
  /// MaintenanceRepository.updateEntry already does locally.
  Future<void> _pushParts(String entryId) async {
    final parts = await (_db.select(_db.maintenanceParts)
          ..where((p) => p.maintenanceEntryId.equals(entryId)))
        .get();
    await _client.from('maintenance_parts').delete().eq('maintenance_entry_id', entryId);
    if (parts.isNotEmpty) {
      await _client
          .from('maintenance_parts')
          .insert([for (final p in parts) maintenancePartToRemoteRow(p)]);
    }
  }

  Future<void> _pull() async {
    final rows = await _client.from(_table).select();
    final conflictedIds = await _conflicts.unresolvedIdsFor(_table);
    final localVersionById = {
      for (final e in await _db.select(_db.maintenanceEntries).get()) e.id: e.version,
    };
    final newer = newerRemoteRows(
      remoteRows: rows,
      localVersionById: localVersionById,
      skipIds: conflictedIds,
    );

    for (final row in newer) {
      final id = row['id'] as String;
      await _db.into(_db.maintenanceEntries).insertOnConflictUpdate(
            maintenanceEntryFromRemoteRow(row),
          );
      await _pullParts(id);

      if (row['is_deleted'] as bool? ?? false) {
        await _timeline.removeForEntity('maintenance', id);
      } else {
        await _timeline.logEvent(
          vehicleId: row['vehicle_id'] as String,
          moduleOrigin: 'maintenance',
          eventType: 'maintenance_added',
          title: row['category'] as String,
          description: row['comments'] as String?,
          linkedEntityId: id,
          linkedEntityType: 'maintenance',
          occurredAt: DateTime.parse(row['date'] as String).toLocal(),
        );
      }
    }
  }

  Future<void> _pullParts(String entryId) async {
    final remoteParts =
        await _client.from('maintenance_parts').select().eq('maintenance_entry_id', entryId);
    await (_db.delete(_db.maintenanceParts)
          ..where((p) => p.maintenanceEntryId.equals(entryId)))
        .go();
    for (final row in remoteParts) {
      await _db.into(_db.maintenanceParts).insertOnConflictUpdate(
            maintenancePartFromRemoteRow(row),
          );
    }
  }
}

final maintenanceSyncServiceProvider = Provider<MaintenanceSyncService>((ref) {
  return MaintenanceSyncService(
    ref.watch(appDatabaseProvider),
    Supabase.instance.client,
    ref.watch(conflictRepositoryProvider),
    ref.watch(timelineRepositoryProvider),
  );
});
