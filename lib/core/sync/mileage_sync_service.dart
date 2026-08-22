import 'package:drift/drift.dart' show Value;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../database/database.dart';
import '../database/providers.dart';
import '../utils/connectivity.dart';
import 'mileage_sync_mapping.dart';

/// `mileage_entries` is append-only (RG-VEH-005/006/007: a reading is
/// versioned, never overwritten in place - see the table's own class doc),
/// so unlike every other synced table there is no optimistic-concurrency
/// compare-and-swap here: two devices recording different values are two
/// different facts, not a conflict, and a row already pushed is simply
/// never touched again.
class MileageSyncService {
  MileageSyncService(this._db, this._client);
  final AppDatabase _db;
  final SupabaseClient _client;

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
    } catch (_) {
      // Best-effort - a failed pass is silently retried on the next trigger.
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
    await _client.from(_table).upsert([
      for (final m in pending) {...mileageEntryToRemoteRow(m), 'created_by': myUserId},
    ]);
    for (final m in pending) {
      await (_db.update(_db.mileageEntries)..where((t) => t.id.equals(m.id)))
          .write(const MileageEntriesCompanion(syncStatus: Value('synced')));
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
  return MileageSyncService(ref.watch(appDatabaseProvider), Supabase.instance.client);
});
