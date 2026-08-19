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
    final myUserId = _client.auth.currentUser!.id;
    final rows = await _client.from('vehicles').select();
    // One query for every vehicle shared with me and my role on each -
    // vehicles.select() itself never carries role (that lives in
    // vehicle_members), and this also doubles as the source of truth for
    // detecting a revoked/downgraded access below.
    final membershipRows =
        await _client.from('vehicle_members').select('vehicle_id, role').eq('user_id', myUserId);
    final myRoleByVehicleId = {
      for (final m in membershipRows) m['vehicle_id'] as String: m['role'] as String,
    };

    for (final row in rows) {
      final id = row['id'] as String;
      final ownerId = row['user_id'] as String?;
      final myRole = (ownerId != null && ownerId != myUserId) ? myRoleByVehicleId[id] : null;
      final local =
          await (_db.select(_db.vehicles)..where((v) => v.id.equals(id))).getSingleOrNull();
      final remoteUpdatedAt = DateTime.parse(row['updated_at'] as String);
      // Last-write-wins on updatedAt - a row edited locally (including one
      // just pushed above, or one changed offline before this pull ran)
      // must never be clobbered by a same-age-or-older remote copy.
      if (local != null && !remoteUpdatedAt.isAfter(local.updatedAt.toUtc())) {
        // A permission change alone doesn't bump updated_at, so it needs
        // its own check even when the rest of the row is left untouched.
        if (myRole != local.myRole) {
          await (_db.update(_db.vehicles)..where((v) => v.id.equals(id)))
              .write(VehiclesCompanion(myRole: Value(myRole)));
        }
        continue;
      }
      var companion = vehicleFromRemoteRow(row);
      if (myRole != null) companion = companion.copyWith(myRole: Value(myRole));
      await _db.into(_db.vehicles).insertOnConflictUpdate(companion);
    }

    // Revocation: a vehicle shared with me whose membership row has
    // disappeared (owner revoked access) is removed from this device's
    // local mirror - it's simply no longer reachable, and it was never
    // this device's data to keep offline. The vehicle itself, and every
    // contribution this account made to it, stay intact on the server for
    // the owner and any remaining collaborators.
    final allLocal = await _db.select(_db.vehicles).get();
    for (final v in allLocal) {
      final sharedWithMe = v.ownerId != null && v.ownerId != myUserId;
      if (sharedWithMe && !myRoleByVehicleId.containsKey(v.id)) {
        await (_db.delete(_db.vehicles)..where((t) => t.id.equals(v.id))).go();
      }
    }
  }
}

final vehicleSyncServiceProvider = Provider<VehicleSyncService>((ref) {
  return VehicleSyncService(ref.watch(appDatabaseProvider), Supabase.instance.client);
});
