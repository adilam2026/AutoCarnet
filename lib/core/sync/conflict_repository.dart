import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../database/database.dart';
import '../database/providers.dart';
import '../utils/id_generator.dart';

/// Records and resolves the version-mismatch conflicts [pushWithOcc] can
/// hit (see occ_sync.dart) - the one and only place a synced record's local
/// edit is ever set aside instead of applied, so it can never be silently
/// discarded.
class ConflictRepository {
  ConflictRepository(this._db);
  final AppDatabase _db;

  Future<void> record({
    required String table,
    required String recordId,
    String? vehicleId,
    required Map<String, dynamic> localSnapshot,
    required Map<String, dynamic> remoteSnapshot,
    String? remoteUpdatedBy,
  }) async {
    final existing = await (_db.select(_db.syncConflicts)
          ..where((c) =>
              c.syncedTableName.equals(table) &
              c.recordId.equals(recordId) &
              c.resolved.equals(false)))
        .getSingleOrNull();
    if (existing != null) {
      // Already flagged and still unresolved - refresh the remote snapshot
      // in case it moved again, but never spawn a second entry for the
      // same record.
      await (_db.update(_db.syncConflicts)..where((c) => c.id.equals(existing.id)))
          .write(SyncConflictsCompanion(
        remoteSnapshotJson: Value(jsonEncode(remoteSnapshot)),
        remoteUpdatedBy: Value(remoteUpdatedBy),
      ));
      return;
    }
    await _db.into(_db.syncConflicts).insert(
          SyncConflictsCompanion.insert(
            id: newId(),
            syncedTableName: table,
            recordId: recordId,
            vehicleId: Value(vehicleId),
            localSnapshotJson: jsonEncode(localSnapshot),
            remoteSnapshotJson: jsonEncode(remoteSnapshot),
            remoteUpdatedBy: Value(remoteUpdatedBy),
            detectedAt: DateTime.now(),
          ),
        );
  }

  Stream<List<SyncConflict>> watchUnresolved() {
    final query = _db.select(_db.syncConflicts)
      ..where((c) => c.resolved.equals(false))
      ..orderBy([(c) => OrderingTerm.desc(c.detectedAt)]);
    return query.watch();
  }

  Future<Set<String>> unresolvedIdsFor(String table) async {
    final rows = await (_db.select(_db.syncConflicts)
          ..where((c) => c.syncedTableName.equals(table) & c.resolved.equals(false)))
        .get();
    return rows.map((r) => r.recordId).toSet();
  }

  Future<void> markResolved(String id) {
    return (_db.update(_db.syncConflicts)..where((c) => c.id.equals(id)))
        .write(const SyncConflictsCompanion(resolved: Value(true)));
  }
}

final conflictRepositoryProvider = Provider<ConflictRepository>((ref) {
  return ConflictRepository(ref.watch(appDatabaseProvider));
});

final unresolvedConflictsProvider = StreamProvider<List<SyncConflict>>((ref) {
  return ref.watch(conflictRepositoryProvider).watchUnresolved();
});
