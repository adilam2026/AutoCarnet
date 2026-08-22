import 'package:drift/drift.dart' show Value;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../features/timeline/data/timeline_repository.dart';
import '../database/database.dart';
import '../database/providers.dart';
import '../utils/connectivity.dart';
import 'conflict_repository.dart';
import 'document_sync_mapping.dart';
import 'occ_sync.dart';

/// Same optimistic-concurrency shape as [VehicleSyncService], for
/// `documents` + `document_versions`. A personal driver document
/// (`vehicleId == null`) still pushes/pulls like any other row - RLS is
/// what actually keeps it private to whoever created it (see the
/// migration) - it just never produces a timeline entry, mirroring
/// DocumentRepository.createDocument's own `if (vehicleId != null)` guard.
class DocumentSyncService {
  DocumentSyncService(this._db, this._client, this._conflicts, this._timeline);
  final AppDatabase _db;
  final SupabaseClient _client;
  final ConflictRepository _conflicts;
  final TimelineRepository _timeline;

  bool _syncing = false;

  Future<void> syncNow() async {
    if (_syncing) return;
    if (_client.auth.currentSession == null) return;
    if (!await hasConnectivity()) return;
    _syncing = true;
    try {
      await _pushDocuments();
      await _pushVersions();
      await _pullDocuments();
      await _pullVersions();
    } catch (_) {
      // Best-effort - a failed pass is silently retried on the next trigger.
    } finally {
      _syncing = false;
    }
  }

  Future<void> _pushDocuments() async {
    final myUserId = _client.auth.currentUser!.id;
    final pending = await (_db.select(_db.documents)
          ..where((d) => d.syncStatus.equals('pendingSync')))
        .get();
    if (pending.isEmpty) return;

    final result = await pushWithOcc(
      client: _client,
      table: 'documents',
      rows: [
        for (final d in pending)
          PendingOccRow(
            id: d.id,
            expectedVersion: d.version,
            remoteRow: {
              ...documentToRemoteRow(d),
              'updated_by': myUserId,
              if (d.version == 0) 'created_by': d.ownerId ?? myUserId,
            },
          ),
      ],
    );

    for (final d in pending) {
      final newVersion = result.newVersionByPushedId[d.id];
      if (newVersion != null) {
        await (_db.update(_db.documents)..where((t) => t.id.equals(d.id))).write(
          DocumentsCompanion(
            syncStatus: const Value('synced'),
            version: Value(newVersion),
            updatedBy: Value(myUserId),
          ),
        );
      } else if (result.conflictedIds.contains(d.id)) {
        final remoteRows = await _client.from('documents').select().eq('id', d.id).limit(1);
        if (remoteRows.isEmpty) continue;
        await _conflicts.record(
          table: 'documents',
          recordId: d.id,
          vehicleId: d.vehicleId,
          localSnapshot: documentToRemoteRow(d),
          remoteSnapshot: remoteRows.first,
          remoteUpdatedBy: remoteRows.first['updated_by'] as String?,
        );
      }
    }
  }

  Future<void> _pushVersions() async {
    final myUserId = _client.auth.currentUser!.id;
    final pending = await (_db.select(_db.documentVersions)
          ..where((v) => v.syncStatus.equals('pendingSync')))
        .get();
    if (pending.isEmpty) return;

    final result = await pushWithOcc(
      client: _client,
      table: 'document_versions',
      rows: [
        for (final v in pending)
          PendingOccRow(
            id: v.id,
            expectedVersion: v.version,
            remoteRow: {
              ...documentVersionToRemoteRow(v),
              'updated_by': myUserId,
              if (v.version == 0) 'created_by': myUserId,
            },
          ),
      ],
    );

    for (final v in pending) {
      final newVersion = result.newVersionByPushedId[v.id];
      if (newVersion != null) {
        await (_db.update(_db.documentVersions)..where((t) => t.id.equals(v.id))).write(
          DocumentVersionsCompanion(
            syncStatus: const Value('synced'),
            version: Value(newVersion),
            updatedBy: Value(myUserId),
            createdBy: v.createdBy == null ? Value(myUserId) : const Value.absent(),
          ),
        );
      } else if (result.conflictedIds.contains(v.id)) {
        final remoteRows =
            await _client.from('document_versions').select().eq('id', v.id).limit(1);
        if (remoteRows.isEmpty) continue;
        final parentDoc = await (_db.select(_db.documents)
              ..where((d) => d.id.equals(v.documentId)))
            .getSingleOrNull();
        await _conflicts.record(
          table: 'document_versions',
          recordId: v.id,
          vehicleId: parentDoc?.vehicleId,
          localSnapshot: documentVersionToRemoteRow(v),
          remoteSnapshot: remoteRows.first,
          remoteUpdatedBy: remoteRows.first['updated_by'] as String?,
        );
      }
    }
  }

  Future<void> _pullDocuments() async {
    final rows = await _client.from('documents').select();
    final conflictedIds = await _conflicts.unresolvedIdsFor('documents');
    final localById = {
      for (final d in await _db.select(_db.documents).get()) d.id: d,
    };
    final newer = newerRemoteRows(
      remoteRows: rows,
      localVersionById: {for (final e in localById.entries) e.key: e.value.version},
      skipIds: conflictedIds,
    );

    for (final row in newer) {
      final id = row['id'] as String;
      final vehicleId = row['vehicle_id'] as String?;
      final isDeleted = row['is_deleted'] as bool? ?? false;
      final newVersionId = row['current_version_id'] as String?;
      final previous = localById[id];
      final isNew = previous == null;
      final versionChanged = previous != null && previous.currentVersionId != newVersionId;

      await _db.into(_db.documents).insertOnConflictUpdate(documentFromRemoteRow(row));

      if (vehicleId == null || isDeleted) continue;
      if (isNew) {
        await _timeline.logEvent(
          vehicleId: vehicleId,
          moduleOrigin: 'documents',
          eventType: 'document_added',
          title: '${row['type']} ajouté',
          linkedEntityId: id,
          linkedEntityType: 'document',
          occurredAt: DateTime.parse(row['created_at'] as String).toLocal(),
        );
      } else if (versionChanged) {
        await _timeline.logEvent(
          vehicleId: vehicleId,
          moduleOrigin: 'documents',
          eventType: 'document_renewed',
          title: '${row['type']} renouvelé',
          linkedEntityId: id,
          linkedEntityType: 'document',
          occurredAt: DateTime.parse(row['updated_at'] as String).toLocal(),
        );
      }
    }
  }

  Future<void> _pullVersions() async {
    final rows = await _client.from('document_versions').select();
    final conflictedIds = await _conflicts.unresolvedIdsFor('document_versions');
    final localVersionById = {
      for (final v in await _db.select(_db.documentVersions).get()) v.id: v.version,
    };
    final newer = newerRemoteRows(
      remoteRows: rows,
      localVersionById: localVersionById,
      skipIds: conflictedIds,
    );
    for (final row in newer) {
      await _db.into(_db.documentVersions).insertOnConflictUpdate(
            documentVersionFromRemoteRow(row),
          );
    }
  }
}

final documentSyncServiceProvider = Provider<DocumentSyncService>((ref) {
  return DocumentSyncService(
    ref.watch(appDatabaseProvider),
    Supabase.instance.client,
    ref.watch(conflictRepositoryProvider),
    ref.watch(timelineRepositoryProvider),
  );
});
