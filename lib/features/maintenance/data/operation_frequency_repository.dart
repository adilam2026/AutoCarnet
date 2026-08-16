import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/database/database.dart';
import '../../../core/database/providers.dart';
import '../../../core/utils/id_generator.dart';

/// A frequency the owner has explicitly confirmed for a given vehicle and
/// operation category - always takes priority over AutoCarnet's built-in
/// default (OperationRecurrenceRules), and is never written to without an
/// explicit save action from the owner (RG: "ne jamais modifier
/// automatiquement une fréquence configurée sans son accord").
class OperationFrequencyRepository {
  OperationFrequencyRepository(this._db);
  final AppDatabase _db;

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
      ));
    } else {
      await _db.into(_db.operationFrequencyPreferences).insert(
            OperationFrequencyPreferencesCompanion.insert(
              id: newId(),
              vehicleId: vehicleId,
              category: category,
              frequencyKm: Value(frequencyKm),
              frequencyMonths: Value(frequencyMonths),
              updatedAt: now,
            ),
          );
    }
  }
}

final operationFrequencyRepositoryProvider =
    Provider<OperationFrequencyRepository>((ref) {
  return OperationFrequencyRepository(ref.watch(appDatabaseProvider));
});
