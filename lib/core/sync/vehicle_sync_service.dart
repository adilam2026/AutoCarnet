import 'package:drift/drift.dart' show Value;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../database/database.dart';
import '../database/providers.dart';
import '../utils/connectivity.dart';
import 'vehicle_sync_mapping.dart';

/// Keeps the local `vehicles` table and the cloud `vehicles` table in sync
/// for the signed-in account - fully automatic, no "Synchroniser" button.
/// Offline-first is never compromised: every local write happens and is
/// visible immediately regardless of connectivity or sign-in state; this
/// service only ever pushes/pulls opportunistically on top of that, and a
/// failed pass is silently retried on the next trigger rather than
/// surfacing as an error.
class VehicleSyncService {
  VehicleSyncService(this._db, this._client);
  final AppDatabase _db;
  final SupabaseClient _client;

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
      // Best-effort - see class doc.
    } finally {
      _syncing = false;
    }
  }

  Future<void> _push() async {
    final pending = await (_db.select(_db.vehicles)
          ..where((v) => v.syncStatus.equals('pendingSync')))
        .get();
    for (final v in pending) {
      await _client.from('vehicles').upsert(vehicleToRemoteRow(v));
      await (_db.update(_db.vehicles)..where((t) => t.id.equals(v.id)))
          .write(const VehiclesCompanion(syncStatus: Value('synced')));
    }
  }

  Future<void> _pull() async {
    final rows = await _client.from('vehicles').select();
    for (final row in rows) {
      final id = row['id'] as String;
      final local =
          await (_db.select(_db.vehicles)..where((v) => v.id.equals(id))).getSingleOrNull();
      final remoteUpdatedAt = DateTime.parse(row['updated_at'] as String);
      // Last-write-wins on updatedAt - a row edited locally (including one
      // just pushed above, or one changed offline before this pull ran)
      // must never be clobbered by a same-age-or-older remote copy.
      if (local != null && !remoteUpdatedAt.isAfter(local.updatedAt.toUtc())) {
        continue;
      }
      await _db.into(_db.vehicles).insertOnConflictUpdate(vehicleFromRemoteRow(row));
    }
  }
}

final vehicleSyncServiceProvider = Provider<VehicleSyncService>((ref) {
  return VehicleSyncService(ref.watch(appDatabaseProvider), Supabase.instance.client);
});
