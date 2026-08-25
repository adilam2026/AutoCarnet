import 'dart:async';

import 'package:drift/drift.dart' show Value;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../database/database.dart';
import '../database/providers.dart';
import '../utils/connectivity.dart';
import 'conflict_repository.dart';
import 'expense_sync_mapping.dart';
import 'occ_sync.dart';
import 'sync_outbox_repository.dart';

/// Same optimistic-concurrency shape as [VehicleSyncService], for
/// `expenses`. Expenses never produce a timeline entry (see
/// ExpenseRepository - only maintenance/fuel/documents do), so a pull here
/// is just the raw row, nothing else.
class ExpenseSyncService {
  ExpenseSyncService(this._db, this._clientFn, this._conflicts, [this._outbox]);
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

  static const _table = 'expenses';
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
      unawaited(_outbox?.recordError('expenses: $e'));
    } finally {
      _syncing = false;
    }
  }

  Future<void> _push() async {
    final myUserId = _client.auth.currentUser!.id;
    final pending = await (_db.select(_db.expenses)
          ..where((e) => e.syncStatus.equals('pendingSync')))
        .get();
    if (pending.isEmpty) return;

    final OccPushResult result;
    try {
      result = await pushWithOcc(
        client: _client,
        table: _table,
        rows: [
          for (final e in pending)
            PendingOccRow(
              id: e.id,
              expectedVersion: e.version,
              remoteRow: {
                ...expenseToRemoteRow(e),
                'updated_by': myUserId,
                if (e.version == 0) 'created_by': myUserId,
              },
            ),
        ],
      );
    } catch (e) {
      for (final expense in pending) {
        unawaited(_outbox?.markFailed('expense', expense.id, e.toString()));
      }
      rethrow;
    }

    for (final e in pending) {
      final newVersion = result.newVersionByPushedId[e.id];
      if (newVersion != null) {
        await (_db.update(_db.expenses)..where((t) => t.id.equals(e.id))).write(
          ExpensesCompanion(
            syncStatus: const Value('synced'),
            version: Value(newVersion),
            updatedBy: Value(myUserId),
            createdBy: e.createdBy == null ? Value(myUserId) : const Value.absent(),
          ),
        );
        unawaited(_outbox?.markSynced('expense', e.id));
      } else if (result.conflictedIds.contains(e.id)) {
        final remoteRows = await _client.from(_table).select().eq('id', e.id).limit(1);
        if (remoteRows.isEmpty) continue;
        await _conflicts.record(
          table: _table,
          recordId: e.id,
          vehicleId: e.vehicleId,
          localSnapshot: expenseToRemoteRow(e),
          remoteSnapshot: remoteRows.first,
          remoteUpdatedBy: remoteRows.first['updated_by'] as String?,
        );
        unawaited(_outbox?.clearForConflict('expense', e.id));
      }
    }
  }

  Future<void> _pull() async {
    final rows = await _client.from(_table).select();
    final conflictedIds = await _conflicts.unresolvedIdsFor(_table);
    final localVersionById = {
      for (final e in await _db.select(_db.expenses).get()) e.id: e.version,
    };
    final newer = newerRemoteRows(
      remoteRows: rows,
      localVersionById: localVersionById,
      skipIds: conflictedIds,
    );
    for (final row in newer) {
      await _db.into(_db.expenses).insertOnConflictUpdate(expenseFromRemoteRow(row));
    }
  }
}

final expenseSyncServiceProvider = Provider<ExpenseSyncService>((ref) {
  return ExpenseSyncService(
    ref.watch(appDatabaseProvider),
    () => Supabase.instance.client,
    ref.watch(conflictRepositoryProvider),
    ref.watch(syncOutboxRepositoryProvider),
  );
});
