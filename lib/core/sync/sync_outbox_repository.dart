import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../database/database.dart';
import '../database/providers.dart';
import '../utils/id_generator.dart';

/// The technical sync queue (mission 2026, "défaut de la stratégie de
/// synchronisation" pass, after a vehicle created offline was lost to an
/// uninstall before it ever reached the cloud).
///
/// IMPORTANT - this is a diagnostic/retry LEDGER, not the actual transport:
/// the real "what needs pushing" source of truth stays each entity table's
/// own `syncStatus`/`version` columns, exactly as before (see
/// VehicleSyncService's OCC push) - changing that proven, already-tested
/// mechanism for every table at once would be a much larger and riskier
/// rewrite than the actual problem calls for. What this repository adds on
/// top is the one thing that genuinely didn't exist: a durable, queryable
/// record of every pending operation with a real retry_count/
/// last_attempt_at/last_error trail, so the app can answer "combien de
/// modifications en attente ?" / "dernière synchronisation réussie ?" /
/// "dernière erreur ?" without scanning nine different tables, and so a
/// repeatedly-failing push leaves a visible trail instead of retrying
/// forever in total silence.
///
/// One row per (entityType, entityId) - [enqueue] upserts in place, it
/// never appends a second row for the same entity, so retrying the same
/// operation many times (mission TEST 6) can never duplicate the outbox
/// itself the way it must never duplicate the remote row either.
/// The engine's own precise answer to "where does this one row actually
/// stand?" (mission point 3) - never inferred by the UI from raw
/// syncStatus strings, always resolved through [SyncOutboxRepository.
/// stateFor].
enum EntitySyncState {
  /// Written locally, enqueued, but no push attempt has completed or is
  /// running yet (offline, or simply not this coordinator pass's turn).
  queued,

  /// A push attempt for this exact row is in flight right now.
  syncing,

  /// Confirmed by Supabase - the row's own `syncStatus` column says
  /// `synced` and its outbox trace (if any lingered) is gone.
  synced,

  /// At least one push attempt failed - still queued, still retried
  /// automatically on the next pass, never silently dropped.
  failed,
}

class SyncOutboxRepository {
  SyncOutboxRepository(this._db);
  final AppDatabase _db;

  static const singletonMetaId = 'singleton';

  /// Called at the exact moment a repository marks a row `pendingSync` -
  /// i.e. step 2 of the mission's own numbered flow ("une opération de
  /// synchronisation est immédiatement mise en file d'attente"), which is
  /// deliberately a separate moment from step 3 (a *SyncService actually
  /// attempting the push) - this must survive even if no *SyncService ever
  /// gets to run before the app closes.
  Future<void> enqueue({
    required String entityType,
    required String entityId,
    required String operation,
    String? payload,
  }) async {
    final existing = await (_db.select(_db.syncOutbox)
          ..where((o) => o.entityType.equals(entityType) & o.entityId.equals(entityId)))
        .getSingleOrNull();
    final now = DateTime.now();
    if (existing != null) {
      await (_db.update(_db.syncOutbox)..where((o) => o.id.equals(existing.id))).write(
        SyncOutboxCompanion(
          operation: Value(operation),
          payload: Value(payload),
          syncStatus: const Value('pending'),
        ),
      );
      return;
    }
    await _db.into(_db.syncOutbox).insert(
          SyncOutboxCompanion.insert(
            id: newId(),
            entityType: entityType,
            entityId: entityId,
            operation: operation,
            payload: Value(payload),
            createdAt: now,
          ),
        );
  }

  Future<void> markSyncing(String entityType, String entityId) {
    return (_db.update(_db.syncOutbox)
          ..where((o) => o.entityType.equals(entityType) & o.entityId.equals(entityId)))
        .write(SyncOutboxCompanion(
      syncStatus: const Value('syncing'),
      lastAttemptAt: Value(DateTime.now()),
    ));
  }

  /// Only ever called after Supabase has actually confirmed the write
  /// (mission: "ne supprime l'entrée... qu'après confirmation réelle") -
  /// removed rather than kept around as a "synced" tombstone, since a
  /// flushed outbox message has nothing left to say.
  Future<void> markSynced(String entityType, String entityId) {
    return (_db.delete(_db.syncOutbox)
          ..where((o) => o.entityType.equals(entityType) & o.entityId.equals(entityId)))
        .go();
  }

  Future<void> markFailed(String entityType, String entityId, String error) async {
    final existing = await (_db.select(_db.syncOutbox)
          ..where((o) => o.entityType.equals(entityType) & o.entityId.equals(entityId)))
        .getSingleOrNull();
    final now = DateTime.now();
    if (existing == null) {
      // The push attempted something the outbox never saw enqueued (e.g. a
      // row written before this pass existed) - record it anyway rather
      // than losing the failure entirely.
      await _db.into(_db.syncOutbox).insert(
            SyncOutboxCompanion.insert(
              id: newId(),
              entityType: entityType,
              entityId: entityId,
              operation: 'update',
              createdAt: now,
              retryCount: const Value(1),
              lastAttemptAt: Value(now),
              lastError: Value(error),
              syncStatus: const Value('failed'),
            ),
          );
      return;
    }
    await (_db.update(_db.syncOutbox)..where((o) => o.id.equals(existing.id))).write(
      SyncOutboxCompanion(
        retryCount: Value(existing.retryCount + 1),
        lastAttemptAt: Value(now),
        lastError: Value(error),
        syncStatus: const Value('failed'),
      ),
    );
  }

  /// A conflict isn't a transport failure (it's recorded via
  /// ConflictRepository, with its own dedicated resolution UI) - clearing
  /// it from the outbox avoids double-reporting the same event as both "X
  /// pending changes" and "a conflict needs resolving".
  Future<void> clearForConflict(String entityType, String entityId) => markSynced(entityType, entityId);

  Stream<int> watchPendingCount() {
    final count = _db.syncOutbox.id.count();
    final query = _db.selectOnly(_db.syncOutbox)..addColumns([count]);
    return query.map((row) => row.read(count) ?? 0).watchSingle();
  }

  Future<int> pendingCount() async {
    final count = _db.syncOutbox.id.count();
    final query = _db.selectOnly(_db.syncOutbox)..addColumns([count]);
    final row = await query.getSingle();
    return row.read(count) ?? 0;
  }

  Future<List<SyncOutboxData>> failing() {
    return (_db.select(_db.syncOutbox)..where((o) => o.syncStatus.equals('failed'))).get();
  }

  /// The one authoritative answer to "où en est CETTE ligne exactement ?"
  /// (mission point 3, post-Volkswagen-vehicle-loss report: never just a
  /// binary "saved or not", never just an aggregate app-wide count) -
  /// correlates the entity's own table's `syncStatus` column with its
  /// outbox trace, since neither alone tells the full story: a table row
  /// can say `pendingSync` while the outbox row underneath it is actively
  /// `syncing`, sitting `failed` after a retry, or simply still `pending`
  /// (queued, never even attempted yet - e.g. offline, or created a moment
  /// ago and the coordinator hasn't ticked). Never exposed as user-facing
  /// UI by itself - see [SyncStatus] for the app-wide indicator - but the
  /// engine can always answer this precisely for any one row.
  Future<EntitySyncState> stateFor({
    required String entityType,
    required String entityId,
    required String localSyncStatus,
  }) async {
    if (localSyncStatus == 'synced') return EntitySyncState.synced;
    final row = await (_db.select(_db.syncOutbox)
          ..where((o) => o.entityType.equals(entityType) & o.entityId.equals(entityId)))
        .getSingleOrNull();
    // The local row itself says "not yet synced" but there's no matching
    // outbox trace at all - a state that should never happen given every
    // synced write enqueues its own outbox entry in the same atomic
    // transaction (see e.g. VehicleRepository.createVehicle), but treating
    // it as "queued" rather than crashing keeps this purely diagnostic API
    // from ever becoming a new way to break the caller.
    if (row == null) return EntitySyncState.queued;
    return switch (row.syncStatus) {
      'syncing' => EntitySyncState.syncing,
      'failed' => EntitySyncState.failed,
      _ => EntitySyncState.queued,
    };
  }

  Stream<int> watchFailedCount() {
    final count = _db.syncOutbox.id.count();
    final query = _db.selectOnly(_db.syncOutbox)
      ..addColumns([count])
      ..where(_db.syncOutbox.syncStatus.equals('failed'));
    return query.map((row) => row.read(count) ?? 0).watchSingle();
  }

  /// The most recent moment ANY outbox entry was actually attempted
  /// (success or failure) - mission point 6 ("dernière tentative"),
  /// distinct from [SyncMeta.lastSuccessAt]/[lastErrorAt] which only ever
  /// move on a full coordinator pass, not on every individual push.
  Stream<DateTime?> watchLastAttemptAt() {
    final maxAttempt = _db.syncOutbox.lastAttemptAt.max();
    final query = _db.selectOnly(_db.syncOutbox)..addColumns([maxAttempt]);
    return query.map((row) => row.read(maxAttempt)).watchSingle();
  }

  Future<void> recordSuccess() async {
    await _upsertMeta(SyncMetaCompanion(
      lastSuccessAt: Value(DateTime.now()),
    ));
  }

  Future<void> recordError(String message) async {
    await _upsertMeta(SyncMetaCompanion(
      lastErrorAt: Value(DateTime.now()),
      lastErrorMessage: Value(message),
    ));
  }

  Future<SyncMetaData?> watchMetaOnce() {
    return (_db.select(_db.syncMeta)..where((m) => m.id.equals(singletonMetaId)))
        .getSingleOrNull();
  }

  Stream<SyncMetaData?> watchMeta() {
    return (_db.select(_db.syncMeta)..where((m) => m.id.equals(singletonMetaId)))
        .watchSingleOrNull();
  }

  Future<void> _upsertMeta(SyncMetaCompanion patch) async {
    final existing = await (_db.select(_db.syncMeta)
          ..where((m) => m.id.equals(singletonMetaId)))
        .getSingleOrNull();
    if (existing == null) {
      await _db.into(_db.syncMeta).insert(
            SyncMetaCompanion.insert(id: singletonMetaId).copyWith(
              lastSuccessAt: patch.lastSuccessAt,
              lastErrorAt: patch.lastErrorAt,
              lastErrorMessage: patch.lastErrorMessage,
            ),
          );
      return;
    }
    await (_db.update(_db.syncMeta)..where((m) => m.id.equals(singletonMetaId))).write(patch);
  }
}

final syncOutboxRepositoryProvider = Provider<SyncOutboxRepository>((ref) {
  return SyncOutboxRepository(ref.watch(appDatabaseProvider));
});

/// The technical sync-status indicator (mission: "l'application doit
/// pouvoir savoir ceci en interne" - not necessarily always shown, but
/// always answerable): how many local changes are still waiting to reach
/// the cloud, when the last full pass actually succeeded, and what the
/// last error was, if any. A UI can surface this as a badge ("3
/// modifications en attente") or leave it purely internal - this provider
/// makes no assumption either way.
class SyncStatus {
  const SyncStatus({
    required this.pendingCount,
    required this.failedCount,
    this.lastSuccessAt,
    this.lastErrorAt,
    this.lastErrorMessage,
    this.lastAttemptAt,
  });

  final int pendingCount;
  // Mission point 6 ("nombre d'échecs") - a subset of pendingCount: every
  // failed row is still pending (still sitting in the outbox, still
  // retried), this just tells how many of those pending rows have already
  // failed at least once, as opposed to never having been attempted yet.
  final int failedCount;
  final DateTime? lastSuccessAt;
  final DateTime? lastErrorAt;
  final String? lastErrorMessage;
  // Mission point 6 ("date/heure de la dernière tentative") - the most
  // recent individual push attempt across every outbox entry, success or
  // failure, not just the last full coordinator pass.
  final DateTime? lastAttemptAt;

  /// The last error is only still relevant if nothing has succeeded since
  /// - a transient failure followed by a successful retry shouldn't keep
  /// showing a stale error banner.
  bool get hasUnresolvedError =>
      lastErrorAt != null &&
      (lastSuccessAt == null || lastErrorAt!.isAfter(lastSuccessAt!));
}

final _syncPendingCountProvider = StreamProvider<int>((ref) {
  return ref.watch(syncOutboxRepositoryProvider).watchPendingCount();
});

final _syncFailedCountProvider = StreamProvider<int>((ref) {
  return ref.watch(syncOutboxRepositoryProvider).watchFailedCount();
});

final _syncLastAttemptAtProvider = StreamProvider<DateTime?>((ref) {
  return ref.watch(syncOutboxRepositoryProvider).watchLastAttemptAt();
});

final _syncMetaProvider = StreamProvider<SyncMetaData?>((ref) {
  return ref.watch(syncOutboxRepositoryProvider).watchMeta();
});

final syncStatusProvider = Provider<SyncStatus>((ref) {
  final pending = ref.watch(_syncPendingCountProvider).valueOrNull ?? 0;
  final failed = ref.watch(_syncFailedCountProvider).valueOrNull ?? 0;
  final lastAttemptAt = ref.watch(_syncLastAttemptAtProvider).valueOrNull;
  final meta = ref.watch(_syncMetaProvider).valueOrNull;
  return SyncStatus(
    pendingCount: pending,
    failedCount: failed,
    lastSuccessAt: meta?.lastSuccessAt,
    lastErrorAt: meta?.lastErrorAt,
    lastErrorMessage: meta?.lastErrorMessage,
    lastAttemptAt: lastAttemptAt,
  );
});

/// `create` for a never-synced row (version 0), `delete` for a soft-deleted
/// one, `update` otherwise - matches exactly what each *SyncService's own
/// push already infers from `version`/`isDeleted` (mission: soft-delete IS
/// the tombstone, nothing new needed there), just given an explicit name
/// for the outbox's own `operation` column.
String syncOutboxOperationFor({required int version, required bool isDeleted}) {
  if (isDeleted) return 'delete';
  if (version <= 0) return 'create';
  return 'update';
}
