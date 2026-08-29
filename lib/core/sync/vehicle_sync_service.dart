import 'dart:async';
import 'dart:developer' as developer;

import 'package:drift/drift.dart' show Value;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../database/database.dart';
import '../database/providers.dart';
import '../utils/connectivity.dart';
import 'conflict_repository.dart';
import 'occ_sync.dart';
import 'sync_outbox_repository.dart';
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
  VehicleSyncService(this._db, this._clientFn, this._conflicts, [this._outbox]);
  final AppDatabase _db;
  // A closure, not a resolved value - see ProviderSyncService's identical
  // field for why (merely constructing this service must never touch
  // Supabase.instance before syncNow() actually needs it).
  final SupabaseClient Function() _clientFn;
  SupabaseClient get _client => _clientFn();
  final ConflictRepository _conflicts;
  // Optional (sync-hardening pass, after the GLC data-loss report): records
  // this push's outcome in the outbox ledger - retry_count/last_error per
  // row, and the global last success/error for the technical sync
  // indicator (mission: "dernière synchronisation réussie / dernière
  // erreur"). Absent in tests that construct this service directly.
  final SyncOutboxRepository? _outbox;

  bool _syncing = false;

  void _log(String stage, String message) {
    developer.log('SYNC_VEHICLE $stage - $message', name: 'VehicleSyncService');
  }

  /// Mission 2026, real-device incident report (a vehicle created while
  /// genuinely signed in never reached Supabase, with zero visible error):
  /// every gate this method can silently return on, and every step of the
  /// actual push, is now logged - so if this happens again on a real
  /// device, `adb logcat | grep SYNC_VEHICLE` gives a definitive answer
  /// instead of another round of hypotheses.
  Future<void> syncNow() async {
    _log('01', 'syncNow() called');
    if (_syncing) {
      _log('02', 'skipped - a pass is already in flight');
      return;
    }
    if (_client.auth.currentSession == null) {
      _log('03', 'skipped - no Supabase session (not signed in, or the '
          'session died/expired without a fresh login since)');
      return;
    }
    final hasNet = await hasConnectivity();
    _log('04', 'connectivity check: $hasNet');
    if (!hasNet) {
      _log('05', 'skipped - no radio connectivity');
      return;
    }
    _syncing = true;
    try {
      _log('06', 'push starting');
      await _push();
      _log('07', 'push done - pull starting');
      await _pull();
      _log('08', 'pull done - recording success');
      unawaited(_outbox?.recordSuccess());
    } catch (e) {
      _log('09', 'pass FAILED: $e');
      unawaited(_outbox?.recordError('vehicles: $e'));
    } finally {
      _syncing = false;
    }
  }

  Future<void> _push() async {
    final myUserId = _client.auth.currentUser!.id;
    final pending = await (_db.select(_db.vehicles)
          ..where((v) => v.syncStatus.equals('pendingSync')))
        .get();
    _log('06a', '${pending.length} pending vehicle(s) to push: '
        '${pending.map((v) => v.id).toList()}');
    if (pending.isEmpty) return;

    final OccPushResult result;
    try {
      result = await pushWithOcc(
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
      _log('06b', 'pushWithOcc succeeded - '
          'newVersionByPushedId=${result.newVersionByPushedId} '
          'conflictedIds=${result.conflictedIds}');
    } catch (e) {
      _log('06c', 'pushWithOcc THREW for ${pending.map((v) => v.id).toList()}: $e');
      for (final v in pending) {
        unawaited(_outbox?.markFailed('vehicle', v.id, e.toString()));
      }
      rethrow;
    }

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
        unawaited(_outbox?.markSynced('vehicle', v.id));
        _log('06d', 'vehicle ${v.id} confirmed synced (version=$newVersion)');
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
        unawaited(_outbox?.clearForConflict('vehicle', v.id));
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
    () => Supabase.instance.client,
    ref.watch(conflictRepositoryProvider),
    ref.watch(syncOutboxRepositoryProvider),
  );
});
