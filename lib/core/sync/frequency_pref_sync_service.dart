import 'dart:async';

import 'package:drift/drift.dart' show Value;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../database/database.dart';
import '../database/providers.dart';
import '../utils/connectivity.dart';
import 'conflict_repository.dart';
import 'frequency_pref_sync_mapping.dart';
import 'occ_sync.dart';
import 'sync_outbox_repository.dart';

/// Same optimistic-concurrency shape as [VehicleSyncService], for
/// `operation_frequency_preferences`.
class FrequencyPrefSyncService {
  FrequencyPrefSyncService(this._db, this._clientFn, this._conflicts, [this._outbox]);
  final AppDatabase _db;
  // A closure, not a resolved value - see ProviderSyncService's identical
  // field for why (merely constructing this service must never touch
  // Supabase.instance before syncNow() actually needs it).
  final SupabaseClient Function() _clientFn;
  SupabaseClient get _client => _clientFn();
  final ConflictRepository _conflicts;
  // Optional (sync-hardening pass) - see VehicleSyncService's identical
  // field for the full rationale.
  final SyncOutboxRepository? _outbox;

  static const _table = 'operation_frequency_preferences';
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
      unawaited(_outbox?.recordError('frequency prefs: $e'));
    } finally {
      _syncing = false;
    }
  }

  Future<void> _push() async {
    final myUserId = _client.auth.currentUser!.id;
    final pending = await (_db.select(_db.operationFrequencyPreferences)
          ..where((p) => p.syncStatus.equals('pendingSync')))
        .get();
    if (pending.isEmpty) return;

    final OccPushResult result;
    try {
      result = await pushWithOcc(
        client: _client,
        table: _table,
        rows: [
          for (final p in pending)
            PendingOccRow(
              id: p.id,
              expectedVersion: p.version,
              remoteRow: {
                ...frequencyPrefToRemoteRow(p),
                'updated_by': myUserId,
                if (p.version == 0) 'created_by': myUserId,
              },
            ),
        ],
      );
    } catch (e) {
      for (final pref in pending) {
        unawaited(_outbox?.markFailed('frequency_pref', pref.id, e.toString()));
      }
      rethrow;
    }

    for (final p in pending) {
      final newVersion = result.newVersionByPushedId[p.id];
      if (newVersion != null) {
        await (_db.update(_db.operationFrequencyPreferences)..where((t) => t.id.equals(p.id)))
            .write(OperationFrequencyPreferencesCompanion(
          syncStatus: const Value('synced'),
          version: Value(newVersion),
          updatedBy: Value(myUserId),
          createdBy: p.createdBy == null ? Value(myUserId) : const Value.absent(),
        ));
        unawaited(_outbox?.markSynced('frequency_pref', p.id));
      } else if (result.conflictedIds.contains(p.id)) {
        final remoteRows = await _client.from(_table).select().eq('id', p.id).limit(1);
        if (remoteRows.isEmpty) continue;
        await _conflicts.record(
          table: _table,
          recordId: p.id,
          vehicleId: p.vehicleId,
          localSnapshot: frequencyPrefToRemoteRow(p),
          remoteSnapshot: remoteRows.first,
          remoteUpdatedBy: remoteRows.first['updated_by'] as String?,
        );
        unawaited(_outbox?.clearForConflict('frequency_pref', p.id));
      }
    }
  }

  Future<void> _pull() async {
    final rows = await _client.from(_table).select();
    final conflictedIds = await _conflicts.unresolvedIdsFor(_table);
    final localVersionById = {
      for (final p in await _db.select(_db.operationFrequencyPreferences).get())
        p.id: p.version,
    };
    final newer = newerRemoteRows(
      remoteRows: rows,
      localVersionById: localVersionById,
      skipIds: conflictedIds,
    );
    for (final row in newer) {
      await _db.into(_db.operationFrequencyPreferences).insertOnConflictUpdate(
            frequencyPrefFromRemoteRow(row),
          );
    }
  }
}

final frequencyPrefSyncServiceProvider = Provider<FrequencyPrefSyncService>((ref) {
  return FrequencyPrefSyncService(
    ref.watch(appDatabaseProvider),
    () => Supabase.instance.client,
    ref.watch(conflictRepositoryProvider),
    ref.watch(syncOutboxRepositoryProvider),
  );
});
