import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/database/database.dart';
import '../../../core/database/providers.dart';
import '../../../core/utils/id_generator.dart';

/// AutoCarnet is offline-first (Principe 9): a single local profile is
/// enough to use the app fully. It can later be linked to a cloud account
/// without changing how every other module reads/writes data.
class LocalProfileRepository {
  LocalProfileRepository(this._db);
  final AppDatabase _db;

  Stream<LocalProfile?> watch() {
    return _db.select(_db.localProfiles).watch().map(
          (rows) => rows.isEmpty ? null : rows.first,
        );
  }

  Future<LocalProfile?> getOrNull() {
    return _db.select(_db.localProfiles).getSingleOrNull();
  }

  Future<void> create({
    required String displayName,
    String currency = 'MAD',
    String distanceUnit = 'km',
  }) {
    return _db.into(_db.localProfiles).insert(
          LocalProfilesCompanion.insert(
            id: newId(),
            displayName: displayName,
            currency: Value(currency),
            distanceUnit: Value(distanceUnit),
            createdAt: DateTime.now(),
          ),
        );
  }

  Future<void> updatePreferences(
    String id, {
    String? displayName,
    String? currency,
    String? distanceUnit,
  }) {
    return (_db.update(_db.localProfiles)..where((p) => p.id.equals(id))).write(
      LocalProfilesCompanion(
        displayName:
            displayName != null ? Value(displayName) : const Value.absent(),
        currency: currency != null ? Value(currency) : const Value.absent(),
        distanceUnit:
            distanceUnit != null ? Value(distanceUnit) : const Value.absent(),
      ),
    );
  }
}

final localProfileRepositoryProvider = Provider<LocalProfileRepository>((ref) {
  return LocalProfileRepository(ref.watch(appDatabaseProvider));
});

final localProfileProvider = StreamProvider<LocalProfile?>((ref) {
  return ref.watch(localProfileRepositoryProvider).watch();
});
