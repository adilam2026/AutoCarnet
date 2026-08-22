import 'package:drift/drift.dart' show Value;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../database/database.dart';
import '../database/providers.dart';
import '../utils/connectivity.dart';
import 'conflict_repository.dart';
import 'occ_sync.dart';
import 'vehicle_sync_mapping.dart';

/// Keeps the local `vehicles` table and the cloud `vehicles` table in sync
/// for the signed-in account - fully automatic, no "Synchroniser" button.
/// Offline-first is never compromised: every local write happens and is
/// visible immediately regardless of connectivity or sign-in state; this
/// service only ever pushes/pulls opportunistically on top of that, and a
/// failed pass is silently retried on the next trigger rather than
/// surfacing as an error.
///
/// Conflicts are never resolved by whoever pushes last (see occ_sync.dart):
/// a version mismatch is recorded via [ConflictRepository] and the local
/// edit is left exactly as typed, `syncStatus` staying `pendingSync` so it
/// is retried automatically once the owner resolves it (ConflictResolution
/// screen) rather than needing a fresh edit.
class VehicleSyncService {
  VehicleSyncService(this._db, this._client, this._conflicts);
  final AppDatabase _db;
  final SupabaseClient _client;
  final ConflictRepository _conflicts;

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
    final myUserId = _client.auth.currentUser!.id;
    final pending = await (_db.select(_db.vehicles)
          ..where((v) => v.syncStatus.equals('pendingSync')))
        .get();
    if (pending.isEmpty) return;

    final result = await pushWithOcc(
      client: _client,
      table: 'vehicles',
      rows: [
        for (final v in pending)
          PendingOccRow(
            id: v.id,
            expectedVersion: v.version,
            remoteRow: {
              ...vehicleToRemoteRow(v),
              'updated_by': myUserId,
              if (v.version == 0) 'created_by': myUserId,
            },
          ),
      ],
    );

    for (final v in pending) {
      final newVersion = result.newVersionByPushedId[v.id];
      if (newVersion != null) {
        await (_db.update(_db.vehicles)..where((t) => t.id.equals(v.id))).write(
          VehiclesCompanion(
            syncStatus: const Value('synced'),
            version: Value(newVersion),
            updatedBy: Value(myUserId),
            createdBy: v.createdBy == null ? Value(myUserId) : const Value.absent(),
          ),
        );
      } else if (result.conflictedIds.contains(v.id)) {
        final remoteRows =
            await _client.from('vehicles').select().eq('id', v.id).limit(1);
        if (remoteRows.isEmpty) continue;
        await _conflicts.record(
          table: 'vehicles',
          recordId: v.id,
          vehicleId: v.id,
          localSnapshot: vehicleToRemoteRow(v),
          remoteSnapshot: remoteRows.first,
          remoteUpdatedBy: remoteRows.first['updated_by'] as String?,
        );
      }
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

    final conflictedIds = await _conflicts.unresolvedIdsFor('vehicles');
    final localVersionById = {
      for (final v in await _db.select(_db.vehicles).get()) v.id: v.version,
    };
    final newer = newerRemoteRows(
      remoteRows: rows,
      localVersionById: localVersionById,
      skipIds: conflictedIds,
    );

    for (final row in newer) {
      final id = row['id'] as String;
      final ownerId = row['user_id'] as String?;
      final myRole = (ownerId != null && ownerId != myUserId) ? myRoleByVehicleId[id] : null;
      var companion = vehicleFromRemoteRow(row);
      if (myRole != null) companion = companion.copyWith(myRole: Value(myRole));
      await _db.into(_db.vehicles).insertOnConflictUpdate(companion);
    }

    // A permission change alone doesn't bump `version`, so it needs its
    // own check even for a vehicle whose row itself didn't just change.
    for (final row in rows) {
      final id = row['id'] as String;
      final ownerId = row['user_id'] as String?;
      if (ownerId == null || ownerId == myUserId) continue;
      final myRole = myRoleByVehicleId[id];
      final local =
          await (_db.select(_db.vehicles)..where((v) => v.id.equals(id))).getSingleOrNull();
      if (local != null && myRole != local.myRole) {
        await (_db.update(_db.vehicles)..where((v) => v.id.equals(id)))
            .write(VehiclesCompanion(myRole: Value(myRole)));
      }
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
  return VehicleSyncService(
    ref.watch(appDatabaseProvider),
    Supabase.instance.client,
    ref.watch(conflictRepositoryProvider),
  );
});
