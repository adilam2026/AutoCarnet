import 'dart:async';

import 'package:drift/drift.dart' show Value;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../database/database.dart';
import '../database/providers.dart';
import '../utils/connectivity.dart';
import 'mileage_sync_mapping.dart';
import 'sync_outbox_repository.dart';

/// `mileage_entries` is append-only (RG-VEH-005/006/007: a reading is
/// versioned, never overwritten in place - see the table's own class doc),
/// so unlike every other synced table there is no optimistic-concurrency
/// compare-and-swap here: two devices recording different values are two
/// different facts, not a conflict, and a row already pushed is simply
/// never touched again.
class MileageSyncService {
  MileageSyncService(this._db, this._clientFn, [this._outbox]);
  final AppDatabase _db;
  // A closure, not a resolved value - see ProviderSyncService's identical
  // field for why (merely constructing this service must never touch
  // Supabase.instance before syncNow() actually needs it).
  final SupabaseClient Function() _clientFn;
  SupabaseClient get _client => _clientFn();
  // Optional (sync-hardening pass) - see VehicleSyncService's identical
  // field for the full rationale.
  final SyncOutboxRepository? _outbox;

  static const _table = 'mileage_entries';
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
      unawaited(_outbox?.recordError('mileage: $e'));
    } finally {
      _syncing = false;
    }
  }

  Future<void> _push() async {
    final myUserId = _client.auth.currentUser!.id;
    final pending = await (_db.select(_db.mileageEntries)
          ..where((m) => m.syncStatus.equals('pendingSync')))
        .get();
    if (pending.isEmpty) return;
    try {
      await _client.from(_table).upsert([
        for (final m in pending) {...mileageEntryToRemoteRow(m), 'created_by': myUserId},
      ]);
    } catch (e) {
      for (final m in pending) {
        unawaited(_outbox?.markFailed('mileage', m.id, e.toString()));
      }
      rethrow;
    }
    for (final m in pending) {
      await (_db.update(_db.mileageEntries)..where((t) => t.id.equals(m.id)))
          .write(const MileageEntriesCompanion(syncStatus: Value('synced')));
      unawaited(_outbox?.markSynced('mileage', m.id));
    }
  }

  Future<void> _pull() async {
    final rows = await _client.from(_table).select();
    final localIds = {
      for (final m in await _db.select(_db.mileageEntries).get()) m.id,
    };
    for (final row in rows) {
      final id = row['id'] as String;
      if (localIds.contains(id)) continue;
      await _db.into(_db.mileageEntries).insertOnConflictUpdate(mileageEntryFromRemoteRow(row));
    }
  }
}

final mileageSyncServiceProvider = Provider<MileageSyncService>((ref) {
  return MileageSyncService(
    ref.watch(appDatabaseProvider),
    () => Supabase.instance.client,
    ref.watch(syncOutboxRepositoryProvider),
  );
});
