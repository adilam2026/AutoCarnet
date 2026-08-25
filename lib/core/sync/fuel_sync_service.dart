import 'dart:async';

import 'package:drift/drift.dart' show Value;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../features/timeline/data/timeline_repository.dart';
import '../database/database.dart';
import '../database/providers.dart';
import '../utils/connectivity.dart';
import 'conflict_repository.dart';
import 'fuel_sync_mapping.dart';
import 'occ_sync.dart';
import 'sync_outbox_repository.dart';

/// Same optimistic-concurrency shape as [VehicleSyncService], for
/// `fuel_entries`. A pull still needs to reconstruct the timeline entry
/// (see MaintenanceSyncService's class doc for why) but never touches
/// mileage_entries or expenses - each syncs independently and would
/// otherwise be double-applied.
class FuelSyncService {
  FuelSyncService(this._db, this._clientFn, this._conflicts, this._timeline, [this._outbox]);
  final AppDatabase _db;
  // A closure, not a resolved value - see ProviderSyncService's identical
  // field for why (merely constructing this service must never touch
  // Supabase.instance before syncNow() actually needs it).
  final SupabaseClient Function() _clientFn;
  SupabaseClient get _client => _clientFn();
  final ConflictRepository _conflicts;
  final TimelineRepository _timeline;
  // Optional (sync-hardening pass) - see VehicleSyncService's identical
  // field for the full rationale.
  final SyncOutboxRepository? _outbox;

  static const _table = 'fuel_entries';
  bool _syncing = false;

  Future<void> syncNow() async {
    if (_syncing) return;
    if (_client.auth.currentSession == null) return;
    if (!await hasConnectivity()) return;
    _syncing = true;
    try {
      await _push();
      await _pull();
      unawaited(_outbox?.recordSuccess());
    } catch (e) {
      unawaited(_outbox?.recordError('fuel: $e'));
    } finally {
      _syncing = false;
    }
  }

  Future<void> _push() async {
    final myUserId = _client.auth.currentUser!.id;
    final pending = await (_db.select(_db.fuelEntries)
          ..where((f) => f.syncStatus.equals('pendingSync')))
        .get();
    if (pending.isEmpty) return;

    final OccPushResult result;
    try {
      result = await pushWithOcc(
        client: _client,
        table: _table,
        rows: [
          for (final f in pending)
            PendingOccRow(
              id: f.id,
              expectedVersion: f.version,
              remoteRow: {
                ...fuelEntryToRemoteRow(f),
                'updated_by': myUserId,
                if (f.version == 0) 'created_by': myUserId,
              },
            ),
        ],
      );
    } catch (e) {
      for (final entry in pending) {
        unawaited(_outbox?.markFailed('fuel', entry.id, e.toString()));
      }
      rethrow;
    }

    for (final f in pending) {
      final newVersion = result.newVersionByPushedId[f.id];
      if (newVersion != null) {
        await (_db.update(_db.fuelEntries)..where((t) => t.id.equals(f.id))).write(
          FuelEntriesCompanion(
            syncStatus: const Value('synced'),
            version: Value(newVersion),
            updatedBy: Value(myUserId),
            createdBy: f.createdBy == null ? Value(myUserId) : const Value.absent(),
          ),
        );
        unawaited(_outbox?.markSynced('fuel', f.id));
      } else if (result.conflictedIds.contains(f.id)) {
        final remoteRows = await _client.from(_table).select().eq('id', f.id).limit(1);
        if (remoteRows.isEmpty) continue;
        await _conflicts.record(
          table: _table,
          recordId: f.id,
          vehicleId: f.vehicleId,
          localSnapshot: fuelEntryToRemoteRow(f),
          remoteSnapshot: remoteRows.first,
          remoteUpdatedBy: remoteRows.first['updated_by'] as String?,
        );
        unawaited(_outbox?.clearForConflict('fuel', f.id));
      }
    }
  }

  Future<void> _pull() async {
    final rows = await _client.from(_table).select();
    final conflictedIds = await _conflicts.unresolvedIdsFor(_table);
    final localVersionById = {
      for (final f in await _db.select(_db.fuelEntries).get()) f.id: f.version,
    };
    final newer = newerRemoteRows(
      remoteRows: rows,
      localVersionById: localVersionById,
      skipIds: conflictedIds,
    );

    for (final row in newer) {
      final id = row['id'] as String;
      await _db.into(_db.fuelEntries).insertOnConflictUpdate(fuelEntryFromRemoteRow(row));

      if (row['is_deleted'] as bool? ?? false) {
        await _timeline.removeForEntity('fuel', id);
      } else {
        final isFullTank = row['is_full_tank'] as bool? ?? true;
        final liters = (row['quantity_liters'] as num).toDouble();
        await _timeline.logEvent(
          vehicleId: row['vehicle_id'] as String,
          moduleOrigin: 'fuel',
          eventType: 'fuel_added',
          title: 'Plein ${isFullTank ? 'complet' : 'partiel'} — '
              '${liters.toStringAsFixed(1)} L',
          linkedEntityId: id,
          linkedEntityType: 'fuel',
          occurredAt: DateTime.parse(row['date'] as String).toLocal(),
        );
      }
    }
  }
}

final fuelSyncServiceProvider = Provider<FuelSyncService>((ref) {
  return FuelSyncService(
    ref.watch(appDatabaseProvider),
    () => Supabase.instance.client,
    ref.watch(conflictRepositoryProvider),
    ref.watch(timelineRepositoryProvider),
    ref.watch(syncOutboxRepositoryProvider),
  );
});
