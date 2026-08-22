import 'package:supabase_flutter/supabase_flutter.dart';

/// One locally-pending row queued for push, described purely in terms of
/// the remote table's own columns - kept table-agnostic so every synced
/// repository can reuse the same push/pull logic instead of hand-rolling
/// its own compare-and-swap.
class PendingOccRow {
  const PendingOccRow({
    required this.id,
    required this.expectedVersion,
    required this.remoteRow,
  });

  final String id;

  /// The local `version` column - 0 means this row has never been
  /// confirmed synced (a brand new local row), anything else is the last
  /// version this device knows the server holds.
  final int expectedVersion;

  /// Every remote column this row should carry, EXCEPT `version` itself
  /// (this function always sets that) - already snake_case, ready to send
  /// as-is to PostgREST.
  final Map<String, dynamic> remoteRow;
}

class OccPushResult {
  const OccPushResult({required this.conflictedIds, required this.newVersionByPushedId});

  /// Ids whose compare-and-swap update matched zero rows - someone else's
  /// push already advanced the version past what this device knew. The
  /// local edit is never discarded here: the caller is expected to record
  /// it as a [SyncConflicts] row instead of retrying blindly.
  final Set<String> conflictedIds;

  /// The new version now confirmed on the server for every row that DID
  /// push successfully (insert or compare-and-swap update alike).
  final Map<String, int> newVersionByPushedId;
}

/// Pushes a batch of pending rows to [table] using optimistic concurrency:
/// a never-synced row (`expectedVersion == 0`) is a plain insert; any other
/// row is only updated `where version = expectedVersion`, so a version
/// already advanced by another device/collaborator is detected as a real
/// conflict instead of one write silently clobbering the other (see
/// lib/core/database/tables.dart's SyncConflicts doc).
Future<OccPushResult> pushWithOcc({
  required SupabaseClient client,
  required String table,
  required List<PendingOccRow> rows,
}) async {
  final conflicted = <String>{};
  final newVersions = <String, int>{};
  for (final row in rows) {
    if (row.expectedVersion <= 0) {
      final payload = {...row.remoteRow, 'version': 1};
      await client.from(table).insert(payload);
      newVersions[row.id] = 1;
      continue;
    }
    final newVersion = row.expectedVersion + 1;
    final payload = {...row.remoteRow, 'version': newVersion};
    final result = await client
        .from(table)
        .update(payload)
        .eq('id', row.id)
        .eq('version', row.expectedVersion)
        .select('id');
    if ((result as List).isEmpty) {
      conflicted.add(row.id);
    } else {
      newVersions[row.id] = newVersion;
    }
  }
  return OccPushResult(conflictedIds: conflicted, newVersionByPushedId: newVersions);
}

/// Pure (no network) comparison: which remote rows are strictly newer than
/// what this device already has, or don't exist locally at all yet -
/// trivially unit-testable, same philosophy as vehicle_sync_mapping.dart.
/// [skipIds] excludes rows this device already has an unresolved
/// [SyncConflicts] entry for - those must never be silently overwritten by
/// a later pull before the owner has picked which copy wins.
List<Map<String, dynamic>> newerRemoteRows({
  required List<Map<String, dynamic>> remoteRows,
  required Map<String, int> localVersionById,
  Set<String> skipIds = const {},
}) {
  return remoteRows.where((row) {
    final id = row['id'] as String;
    if (skipIds.contains(id)) return false;
    final localVersion = localVersionById[id];
    final remoteVersion = row['version'] as int;
    return localVersion == null || remoteVersion > localVersion;
  }).toList();
}
