import 'dart:async';

import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/database/database.dart';
import '../../../core/database/providers.dart';
import '../../../core/sync/sync_coordinator.dart';
import '../../../core/sync/sync_outbox_repository.dart';
import '../../../core/utils/id_generator.dart';

/// A frequency the owner has explicitly confirmed for a given vehicle and
/// operation category - always takes priority over AutoCarnet's built-in
/// default (OperationRecurrenceRules), and is never written to without an
/// explicit save action from the owner (RG: "ne jamais modifier
/// automatiquement une fréquence configurée sans son accord").
class OperationFrequencyRepository {
  OperationFrequencyRepository(this._db, [this._sync, this._outbox]);
  final AppDatabase _db;
  // Optional (sync-hardening pass, after the GLC data-loss report) - see
  // VehicleRepository's identical fields for the full rationale.
  final SyncCoordinator? _sync;
  final SyncOutboxRepository? _outbox;

  void _nudgeSync() {
    unawaited(_sync?.syncAll());
  }

  // Awaited, unlike _nudgeSync - see VehicleRepository's identical helper
  // for why (a local SQLite write, not a network call).
  Future<void> _enqueueOutbox(String id, String operation) {
    return _outbox?.enqueue(entityType: 'frequency_pref', entityId: id, operation: operation) ??
        Future.value();
  }

  Future<OperationFrequencyPreference?> getFor(String vehicleId, String category) {
    return (_db.select(_db.operationFrequencyPreferences)
          ..where((p) => p.vehicleId.equals(vehicleId) & p.category.equals(category)))
        .getSingleOrNull();
  }

  Future<void> setFor(
    String vehicleId,
    String category, {
    double? frequencyKm,
    int? frequencyMonths,
  }) async {
    final existing = await getFor(vehicleId, category);
    final now = DateTime.now();
    if (existing != null) {
      await (_db.update(_db.operationFrequencyPreferences)
            ..where((p) => p.id.equals(existing.id)))
          .write(OperationFrequencyPreferencesCompanion(
        frequencyKm: Value(frequencyKm),
        frequencyMonths: Value(frequencyMonths),
        updatedAt: Value(now),
        // Sync-hardening pass: without this, an already-synced preference
        // change would silently never re-reach the cloud.
        syncStatus: const Value('pendingSync'),
      ));
      await _enqueueOutbox(existing.id, 'update');
    } else {
      final id = newId();
      await _db.into(_db.operationFrequencyPreferences).insert(
            OperationFrequencyPreferencesCompanion.insert(
              id: id,
              vehicleId: vehicleId,
              category: category,
              frequencyKm: Value(frequencyKm),
              frequencyMonths: Value(frequencyMonths),
              updatedAt: now,
            ),
          );
      await _enqueueOutbox(id, 'create');
    }
    _nudgeSync();
  }
}

final operationFrequencyRepositoryProvider =
    Provider<OperationFrequencyRepository>((ref) {
  return OperationFrequencyRepository(
    ref.watch(appDatabaseProvider),
    ref.watch(syncCoordinatorProvider),
    ref.watch(syncOutboxRepositoryProvider),
  );
});
