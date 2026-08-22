import 'package:drift/drift.dart' show Value;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../database/database.dart';
import '../database/providers.dart';
import '../utils/connectivity.dart';
import 'conflict_repository.dart';
import 'expense_sync_mapping.dart';
import 'occ_sync.dart';

/// Same optimistic-concurrency shape as [VehicleSyncService], for
/// `expenses`. Expenses never produce a timeline entry (see
/// ExpenseRepository - only maintenance/fuel/documents do), so a pull here
/// is just the raw row, nothing else.
class ExpenseSyncService {
  ExpenseSyncService(this._db, this._client, this._conflicts);
  final AppDatabase _db;
  final SupabaseClient _client;
  final ConflictRepository _conflicts;

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
    } catch (_) {
      // Best-effort - a failed pass is silently retried on the next trigger.
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

    final result = await pushWithOcc(
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
    Supabase.instance.client,
    ref.watch(conflictRepositoryProvider),
  );
});
