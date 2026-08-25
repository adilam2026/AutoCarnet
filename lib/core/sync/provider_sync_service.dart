import 'dart:async';

import 'package:drift/drift.dart' show Value;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../database/database.dart';
import '../database/providers.dart';
import '../utils/connectivity.dart';
import 'conflict_repository.dart';
import 'occ_sync.dart';
import 'provider_sync_mapping.dart';
import 'sync_outbox_repository.dart';

/// Keeps the local `service_providers` table and the cloud
/// `public.service_providers` table in sync for the signed-in account.
///
/// Sync-hardening pass (mission 2026, after the GLC data-loss report): a
/// prestataire used to be "purely local by design" - same class of risk
/// that lost the GLC (an uninstall before the very first sync pass erases
/// it with nothing to recover). Simpler than VehicleSyncService: a
/// prestataire is never shared with a collaborator (no vehicle_members-
/// style role/revocation to reconcile), it only ever belongs to the
/// account that created it.
class ProviderSyncService {
  ProviderSyncService(this._db, this._clientFn, this._conflicts, [this._outbox]);
  final AppDatabase _db;
  // A closure, not a resolved value: merely constructing this service (e.g.
  // a widget test that watches an unrelated provider which transitively
  // reaches this one) must never touch Supabase.instance before it's
  // actually needed - only syncNow() calling _client below does that, and
  // only in the real app where Supabase.initialize() has already run.
  final SupabaseClient Function() _clientFn;
  SupabaseClient get _client => _clientFn();
  final ConflictRepository _conflicts;
  // Optional (sync-hardening pass) - see VehicleSyncService's identical
  // field for the full rationale.
  final SyncOutboxRepository? _outbox;

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
      unawaited(_outbox?.recordError('providers: $e'));
    } finally {
      _syncing = false;
    }
  }

  Future<void> _push() async {
    final myUserId = _client.auth.currentUser!.id;
    final pending = await (_db.select(_db.serviceProviders)
          ..where((p) => p.syncStatus.equals('pendingSync')))
        .get();
    if (pending.isEmpty) return;

    final OccPushResult result;
    try {
      result = await pushWithOcc(
        client: _client,
        table: 'service_providers',
        rows: [
          for (final p in pending)
            PendingOccRow(
              id: p.id,
              expectedVersion: p.version,
              remoteRow: {
                ...providerToRemoteRow(p),
                'updated_by': myUserId,
                if (p.version == 0) 'created_by': myUserId,
              },
            ),
        ],
      );
    } catch (e) {
      for (final provider in pending) {
        unawaited(_outbox?.markFailed('provider', provider.id, e.toString()));
      }
      rethrow;
    }

    for (final p in pending) {
      final newVersion = result.newVersionByPushedId[p.id];
      if (newVersion != null) {
        await (_db.update(_db.serviceProviders)..where((t) => t.id.equals(p.id))).write(
          ServiceProvidersCompanion(
            syncStatus: const Value('synced'),
            version: Value(newVersion),
            updatedBy: Value(myUserId),
            createdBy: p.createdBy == null ? Value(myUserId) : const Value.absent(),
          ),
        );
        unawaited(_outbox?.markSynced('provider', p.id));
      } else if (result.conflictedIds.contains(p.id)) {
        final remoteRows =
            await _client.from('service_providers').select().eq('id', p.id).limit(1);
        if (remoteRows.isEmpty) continue;
        await _conflicts.record(
          table: 'service_providers',
          recordId: p.id,
          vehicleId: null,
          localSnapshot: providerToRemoteRow(p),
          remoteSnapshot: remoteRows.first,
          remoteUpdatedBy: remoteRows.first['updated_by'] as String?,
        );
        unawaited(_outbox?.clearForConflict('provider', p.id));
      }
    }
  }

  Future<void> _pull() async {
    final rows = await _client.from('service_providers').select();

    final conflictedIds = await _conflicts.unresolvedIdsFor('service_providers');
    final localVersionById = {
      for (final p in await _db.select(_db.serviceProviders).get()) p.id: p.version,
    };
    final newer = newerRemoteRows(
      remoteRows: rows,
      localVersionById: localVersionById,
      skipIds: conflictedIds,
    );

    for (final row in newer) {
      await _db.into(_db.serviceProviders).insertOnConflictUpdate(providerFromRemoteRow(row));
    }
  }
}

final providerSyncServiceProvider = Provider<ProviderSyncService>((ref) {
  return ProviderSyncService(
    ref.watch(appDatabaseProvider),
    () => Supabase.instance.client,
    ref.watch(conflictRepositoryProvider),
    ref.watch(syncOutboxRepositoryProvider),
  );
});
