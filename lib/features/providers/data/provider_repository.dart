import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/database/database.dart';
import '../../../core/database/providers.dart' as core_db;
import '../../../core/utils/id_generator.dart';
import '../../account/data/account_repository.dart';
import '../domain/provider_matching.dart';

/// Single referential of professionals reused by every module instead of
/// retyping a garage/station name each time (Principe 3). Purely local -
/// no cloud sync of its own - so unlike Vehicles.ownerId, [ServiceProvider]
/// rows carry their creator's account id directly from the moment they're
/// created (see [createProvider]), never populated by a later pull.
class ProviderRepository {
  ProviderRepository(this._db);
  final AppDatabase _db;

  /// [currentUserId] keeps two different accounts that have used the same
  /// physical device from ever seeing each other's private contacts - a
  /// provider is visible if it was never tied to an account (created
  /// offline/no cloud account) or belongs to exactly this one. See
  /// [handleAccountSwitch] for what happens to unowned rows on a genuine
  /// account switch.
  Stream<List<ServiceProvider>> watchAll({bool includeArchived = false, String? currentUserId}) {
    final query = _db.select(_db.serviceProviders)
      ..orderBy([(p) => OrderingTerm.asc(p.name)]);
    if (!includeArchived) {
      query.where((p) => p.isArchived.equals(false));
    }
    if (currentUserId != null) {
      query.where((p) => p.ownerId.isNull() | p.ownerId.equals(currentUserId));
    }
    return query.watch();
  }

  Future<ServiceProvider?> getById(String id) {
    return (_db.select(_db.serviceProviders)..where((p) => p.id.equals(id)))
        .getSingleOrNull();
  }

  Future<List<ServiceProvider>> search(String term, {String? currentUserId}) {
    final query = _db.select(_db.serviceProviders)
      ..where((p) => p.name.like('%$term%') & p.isArchived.equals(false))
      ..orderBy([(p) => OrderingTerm.asc(p.name)])
      ..limit(20);
    if (currentUserId != null) {
      query.where((p) => p.ownerId.isNull() | p.ownerId.equals(currentUserId));
    }
    return query.get();
  }

  /// Looks for an existing provider that's very likely the same one typed
  /// differently ("Garage Audi Casablanca" / "Audi Casablanca" / "Audi
  /// Casa") so a new operation never spawns a near-duplicate referential
  /// entry. Never matches across accounts - see [currentUserId].
  Future<ServiceProvider?> findLikelyDuplicate(String name, {String? currentUserId}) async {
    final query = _db.select(_db.serviceProviders)..where((p) => p.isArchived.equals(false));
    if (currentUserId != null) {
      query.where((p) => p.ownerId.isNull() | p.ownerId.equals(currentUserId));
    }
    final all = await query.get();
    for (final p in all) {
      if (isLikelyDuplicate(name, p.name)) return p;
    }
    return null;
  }

  Future<String> createProvider({
    required String name,
    String? type,
    String? city,
    String? phone,
    String? email,
    String? currentUserId,
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
            ownerId: Value(currentUserId),
            createdAt: now,
            updatedAt: now,
          ),
        );
    return id;
  }

  /// Account-switch safety net, same pattern as
  /// VehicleRepository.handleAccountSwitch: a provider still missing an
  /// owner locally (created before this device ever had a cloud account)
  /// can only belong to [previousOwnerId], never to whoever just signed
  /// in. Nothing is ever deleted.
  Future<void> handleAccountSwitch(String previousOwnerId) async {
    await (_db.update(_db.serviceProviders)..where((p) => p.ownerId.isNull()))
        .write(ServiceProvidersCompanion(ownerId: Value(previousOwnerId)));
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
  ref.watch(authStateChangesProvider);
  final currentUserId = ref.watch(accountRepositoryProvider).currentUser?.id;
  return ref.watch(providerRepositoryProvider).watchAll(currentUserId: currentUserId);
});
