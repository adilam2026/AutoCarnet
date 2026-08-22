import 'dart:convert';

import 'package:drift/drift.dart' show Value;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../database/database.dart';
import '../database/providers.dart';
import 'conflict_repository.dart';
import 'document_sync_mapping.dart';
import 'expense_sync_mapping.dart';
import 'frequency_pref_sync_mapping.dart';
import 'fuel_sync_mapping.dart';
import 'maintenance_sync_mapping.dart';
import 'reminder_sync_mapping.dart';
import 'vehicle_sync_mapping.dart';

/// Applies the owner's decision on a [SyncConflict] - the one and only
/// place a conflict actually goes away. Never picks a winner on its own;
/// by the time either method here runs, a human has already chosen.
class ConflictResolutionService {
  ConflictResolutionService(this._db, this._conflicts);
  final AppDatabase _db;
  final ConflictRepository _conflicts;

  /// Discards this device's local edit and adopts the server's current
  /// row - exactly what a normal pull would have done had there been no
  /// conflict.
  Future<void> keepServerVersion(SyncConflict conflict) async {
    final remote =
        jsonDecode(conflict.remoteSnapshotJson) as Map<String, dynamic>;
    switch (conflict.syncedTableName) {
      case 'vehicles':
        await _db
            .into(_db.vehicles)
            .insertOnConflictUpdate(vehicleFromRemoteRow(remote));
      case 'maintenance_entries':
        await _db
            .into(_db.maintenanceEntries)
            .insertOnConflictUpdate(maintenanceEntryFromRemoteRow(remote));
      case 'expenses':
        await _db
            .into(_db.expenses)
            .insertOnConflictUpdate(expenseFromRemoteRow(remote));
      case 'fuel_entries':
        await _db
            .into(_db.fuelEntries)
            .insertOnConflictUpdate(fuelEntryFromRemoteRow(remote));
      case 'documents':
        await _db
            .into(_db.documents)
            .insertOnConflictUpdate(documentFromRemoteRow(remote));
      case 'document_versions':
        await _db
            .into(_db.documentVersions)
            .insertOnConflictUpdate(documentVersionFromRemoteRow(remote));
      case 'reminders':
        await _db
            .into(_db.reminders)
            .insertOnConflictUpdate(reminderFromRemoteRow(remote));
      case 'operation_frequency_preferences':
        await _db
            .into(_db.operationFrequencyPreferences)
            .insertOnConflictUpdate(frequencyPrefFromRemoteRow(remote));
    }
    await _conflicts.markResolved(conflict.id);
  }

  /// Keeps this device's own edit: re-arms it as `pendingSync` with its
  /// `version` bumped to match what the server holds right now, so the
  /// very next sync pass' compare-and-swap push targets the correct base
  /// and succeeds - no separate "force push" path needed.
  Future<void> keepLocalVersion(SyncConflict conflict) async {
    final remote =
        jsonDecode(conflict.remoteSnapshotJson) as Map<String, dynamic>;
    final serverVersion = remote['version'] as int? ?? 0;
    switch (conflict.syncedTableName) {
      case 'vehicles':
        await (_db.update(
          _db.vehicles,
        )..where((t) => t.id.equals(conflict.recordId))).write(
          VehiclesCompanion(
            syncStatus: const Value('pendingSync'),
            version: Value(serverVersion),
          ),
        );
      case 'maintenance_entries':
        await (_db.update(
          _db.maintenanceEntries,
        )..where((t) => t.id.equals(conflict.recordId))).write(
          MaintenanceEntriesCompanion(
            syncStatus: const Value('pendingSync'),
            version: Value(serverVersion),
          ),
        );
      case 'expenses':
        await (_db.update(
          _db.expenses,
        )..where((t) => t.id.equals(conflict.recordId))).write(
          ExpensesCompanion(
            syncStatus: const Value('pendingSync'),
            version: Value(serverVersion),
          ),
        );
      case 'fuel_entries':
        await (_db.update(
          _db.fuelEntries,
        )..where((t) => t.id.equals(conflict.recordId))).write(
          FuelEntriesCompanion(
            syncStatus: const Value('pendingSync'),
            version: Value(serverVersion),
          ),
        );
      case 'documents':
        await (_db.update(
          _db.documents,
        )..where((t) => t.id.equals(conflict.recordId))).write(
          DocumentsCompanion(
            syncStatus: const Value('pendingSync'),
            version: Value(serverVersion),
          ),
        );
      case 'document_versions':
        await (_db.update(
          _db.documentVersions,
        )..where((t) => t.id.equals(conflict.recordId))).write(
          DocumentVersionsCompanion(
            syncStatus: const Value('pendingSync'),
            version: Value(serverVersion),
          ),
        );
      case 'reminders':
        await (_db.update(
          _db.reminders,
        )..where((t) => t.id.equals(conflict.recordId))).write(
          RemindersCompanion(
            syncStatus: const Value('pendingSync'),
            version: Value(serverVersion),
          ),
        );
      case 'operation_frequency_preferences':
        await (_db.update(
          _db.operationFrequencyPreferences,
        )..where((t) => t.id.equals(conflict.recordId))).write(
          OperationFrequencyPreferencesCompanion(
            syncStatus: const Value('pendingSync'),
            version: Value(serverVersion),
          ),
        );
    }
    await _conflicts.markResolved(conflict.id);
  }
}

final conflictResolutionServiceProvider = Provider<ConflictResolutionService>((
  ref,
) {
  return ConflictResolutionService(
    ref.watch(appDatabaseProvider),
    ref.watch(conflictRepositoryProvider),
  );
});
