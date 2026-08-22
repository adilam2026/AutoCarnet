import 'package:drift/drift.dart' show Value;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../database/database.dart';
import '../database/providers.dart';
import '../utils/connectivity.dart';
import 'conflict_repository.dart';
import 'occ_sync.dart';
import 'reminder_sync_mapping.dart';

/// Same optimistic-concurrency shape as [VehicleSyncService], for
/// `reminders`. This is what actually makes a maintenance/document pull
/// on another device show the right due-date, since MaintenanceSyncService
/// and DocumentSyncService deliberately never regenerate a reminder
/// themselves (see their class docs) - whichever device ran
/// upsertForSource/disableForSource already pushed the resulting row here.
class ReminderSyncService {
  ReminderSyncService(this._db, this._client, this._conflicts);
  final AppDatabase _db;
  final SupabaseClient _client;
  final ConflictRepository _conflicts;

  static const _table = 'reminders';
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
    final pending = await (_db.select(_db.reminders)
          ..where((r) => r.syncStatus.equals('pendingSync')))
        .get();
    if (pending.isEmpty) return;

    final result = await pushWithOcc(
      client: _client,
      table: _table,
      rows: [
        for (final r in pending)
          PendingOccRow(
            id: r.id,
            expectedVersion: r.version,
            remoteRow: {
              ...reminderToRemoteRow(r),
              'updated_by': myUserId,
              if (r.version == 0) 'created_by': myUserId,
            },
          ),
      ],
    );

    for (final r in pending) {
      final newVersion = result.newVersionByPushedId[r.id];
      if (newVersion != null) {
        await (_db.update(_db.reminders)..where((t) => t.id.equals(r.id))).write(
          RemindersCompanion(
            syncStatus: const Value('synced'),
            version: Value(newVersion),
            updatedBy: Value(myUserId),
            createdBy: r.createdBy == null ? Value(myUserId) : const Value.absent(),
          ),
        );
      } else if (result.conflictedIds.contains(r.id)) {
        final remoteRows = await _client.from(_table).select().eq('id', r.id).limit(1);
        if (remoteRows.isEmpty) continue;
        await _conflicts.record(
          table: _table,
          recordId: r.id,
          vehicleId: r.vehicleId,
          localSnapshot: reminderToRemoteRow(r),
          remoteSnapshot: remoteRows.first,
          remoteUpdatedBy: remoteRows.first['updated_by'] as String?,
        );
      }
    }
  }

  Future<void> _pull() async {
    final rows = await _client.from(_table).select();
    final conflictedIds = await _conflicts.unresolvedIdsFor(_table);
    final localVersionById = {
      for (final r in await _db.select(_db.reminders).get()) r.id: r.version,
    };
    final newer = newerRemoteRows(
      remoteRows: rows,
      localVersionById: localVersionById,
      skipIds: conflictedIds,
    );
    for (final row in newer) {
      await _db.into(_db.reminders).insertOnConflictUpdate(reminderFromRemoteRow(row));
    }
  }
}

final reminderSyncServiceProvider = Provider<ReminderSyncService>((ref) {
  return ReminderSyncService(
    ref.watch(appDatabaseProvider),
    Supabase.instance.client,
    ref.watch(conflictRepositoryProvider),
  );
});
