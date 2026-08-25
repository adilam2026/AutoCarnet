import 'dart:async';

import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/database/database.dart';
import '../../../core/database/providers.dart' as core_db;
import '../../../core/sync/sync_coordinator.dart';
import '../../../core/sync/sync_outbox_repository.dart';
import '../../../core/utils/id_generator.dart';
import '../../account/data/account_repository.dart';
import '../domain/provider_matching.dart';

/// Single referential of professionals reused by every module instead of
/// retyping a garage/station name each time (Principe 3). [ServiceProvider]
/// rows carry their creator's account id directly from the moment they're
/// created (see [createProvider]), never populated by a later pull - same
/// as before. Real cloud sync (mission 2026, sync-hardening pass): this
/// référentiel used to be "purely local by design", exactly the same class
/// of risk that lost the GLC vehicle (an uninstall before the very first
/// sync pass erases it with nothing to recover) - see ProviderSyncService.
class ProviderRepository {
  ProviderRepository(this._db, [this._sync, this._outbox]);
  final AppDatabase _db;
  // Optional (sync-hardening pass) - see VehicleRepository's identical
  // fields for the full rationale.
  final SyncCoordinator? _sync;
  final SyncOutboxRepository? _outbox;

  void _nudgeSync() {
    unawaited(_sync?.syncAll());
  }

  // Awaited, unlike _nudgeSync - see VehicleRepository's identical helper
  // for why (a local SQLite write, not a network call).
  Future<void> _enqueueOutbox(String providerId, String operation) {
    return _outbox?.enqueue(entityType: 'provider', entityId: providerId, operation: operation) ??
        Future.value();
  }

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

  /// [category] narrows results to that single category when given (e.g.
  /// the fuel form only wants stations, the insurance document only wants
  /// insurers) - a provider with no category at all (legacy row, or one
  /// created before this filter existed) is never hidden by it, since an
  /// unclassified provider might still be exactly what the user is
  /// looking for.
  Future<List<ServiceProvider>> search(
    String term, {
    String? currentUserId,
    ServiceProviderCategory? category,
  }) {
    final query = _db.select(_db.serviceProviders)
      ..where((p) => p.name.like('%$term%') & p.isArchived.equals(false))
      ..orderBy([(p) => OrderingTerm.asc(p.name)])
      ..limit(20);
    if (currentUserId != null) {
      query.where((p) => p.ownerId.isNull() | p.ownerId.equals(currentUserId));
    }
    if (category != null) {
      query.where((p) => p.category.equals(category.name) | p.category.isNull());
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
    ServiceProviderCategory? category,
    String? address,
    String? city,
    String? phone,
    String? comments,
    String? currentUserId,
  }) async {
    final id = newId();
    final now = DateTime.now();
    await _db.transaction(() async {
      await _db.into(_db.serviceProviders).insert(
            ServiceProvidersCompanion.insert(
              id: id,
              name: name,
              category: Value(category),
              address: Value(address),
              city: Value(city),
              phone: Value(phone),
              comments: Value(comments),
              ownerId: Value(currentUserId),
              createdAt: now,
              updatedAt: now,
            ),
          );
      await _enqueueOutbox(id, 'create');
    });
    _nudgeSync();
    return id;
  }

  /// Full edit of an existing prestataire (mission point 2: "modifier un
  /// prestataire") - only [name] is required, matching [createProvider];
  /// every other field can be cleared by passing an explicit empty/null
  /// value through its [Value] wrapper.
  Future<void> updateProvider({
    required String id,
    required String name,
    Value<ServiceProviderCategory?> category = const Value.absent(),
    Value<String?> address = const Value.absent(),
    Value<String?> city = const Value.absent(),
    Value<String?> phone = const Value.absent(),
    Value<String?> comments = const Value.absent(),
  }) async {
    await _db.transaction(() async {
      await (_db.update(_db.serviceProviders)..where((p) => p.id.equals(id))).write(
        ServiceProvidersCompanion(
          name: Value(name),
          category: category,
          address: address,
          city: city,
          phone: phone,
          comments: comments,
          updatedAt: Value(DateTime.now()),
          // Sync-hardening pass: without this, editing an already-synced
          // prestataire would silently never reach the cloud again.
          syncStatus: const Value('pendingSync'),
        ),
      );
      await _enqueueOutbox(id, 'update');
    });
    _nudgeSync();
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

  Future<void> archive(String id) async {
    await _db.transaction(() async {
      await (_db.update(_db.serviceProviders)..where((p) => p.id.equals(id)))
          .write(
        ServiceProvidersCompanion(
          isArchived: const Value(true),
          updatedAt: Value(DateTime.now()),
          syncStatus: const Value('pendingSync'),
        ),
      );
      await _enqueueOutbox(id, 'update');
    });
    _nudgeSync();
  }

  /// The Prestataires screen's "Supprimer" action - a soft delete (same
  /// pattern as VehicleRepository.softDelete), never a hard SQL delete: a
  /// maintenance entry, expense or document that already references this
  /// provider must keep working, it just stops being offered as a
  /// suggestion for new entries and disappears from the Prestataires list.
  Future<void> deleteProvider(String id) => archive(id);
}

final providerRepositoryProvider = Provider<ProviderRepository>((ref) {
  return ProviderRepository(
    ref.watch(core_db.appDatabaseProvider),
    ref.watch(syncCoordinatorProvider),
    ref.watch(syncOutboxRepositoryProvider),
  );
});

final providersListProvider = StreamProvider<List<ServiceProvider>>((ref) {
  ref.watch(authStateChangesProvider);
  final currentUserId = ref.watch(accountRepositoryProvider).currentUser?.id;
  return ref.watch(providerRepositoryProvider).watchAll(currentUserId: currentUserId);
});
