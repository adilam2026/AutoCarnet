import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/database/database.dart';
import '../../../core/database/providers.dart' as core_db;
import '../../../core/utils/id_generator.dart';

/// Single referential of professionals reused by every module instead of
/// retyping a garage/station name each time (Principe 3).
class ProviderRepository {
  ProviderRepository(this._db);
  final AppDatabase _db;

  Stream<List<ServiceProvider>> watchAll({bool includeArchived = false}) {
    final query = _db.select(_db.serviceProviders)
      ..orderBy([(p) => OrderingTerm.asc(p.name)]);
    if (!includeArchived) {
      query.where((p) => p.isArchived.equals(false));
    }
    return query.watch();
  }

  Future<List<ServiceProvider>> search(String term) {
    final query = _db.select(_db.serviceProviders)
      ..where((p) => p.name.like('%$term%') & p.isArchived.equals(false))
      ..orderBy([(p) => OrderingTerm.asc(p.name)])
      ..limit(20);
    return query.get();
  }

  Future<String> createProvider({
    required String name,
    String? type,
    String? city,
    String? phone,
    String? email,
  }) async {
    final id = newId();
    final now = DateTime.now();
    await _db.into(_db.serviceProviders).insert(
          ServiceProvidersCompanion.insert(
            id: id,
            name: name,
            type: Value(type),
            city: Value(city),
            phone: Value(phone),
            email: Value(email),
            createdAt: now,
            updatedAt: now,
          ),
        );
    return id;
  }

  Future<void> archive(String id) {
    return (_db.update(_db.serviceProviders)..where((p) => p.id.equals(id)))
        .write(
      ServiceProvidersCompanion(
        isArchived: const Value(true),
        updatedAt: Value(DateTime.now()),
      ),
    );
  }
}

final providerRepositoryProvider = Provider<ProviderRepository>((ref) {
  return ProviderRepository(ref.watch(core_db.appDatabaseProvider));
});

final providersListProvider = StreamProvider<List<ServiceProvider>>((ref) {
  return ref.watch(providerRepositoryProvider).watchAll();
});
