import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../database/database.dart';
import '../database/providers.dart';
import '../notifications/notification_repository.dart';
import 'conflict_repository.dart';
import 'document_sync_service.dart';
import 'expense_sync_service.dart';
import 'frequency_pref_sync_service.dart';
import 'fuel_sync_service.dart';
import 'maintenance_sync_service.dart';
import 'mileage_sync_service.dart';
import 'provider_sync_service.dart';
import 'reminder_sync_service.dart';
import 'vehicle_sync_service.dart';

/// Keeps the cloud in near-real-time sync with the local database once the
/// app is unlocked, without ever requiring a manual "Synchroniser" tap:
/// - an immediate pass on start (covers changes made offline since last run)
/// - a periodic safety-net pass (covers anything a realtime event missed)
/// - a Supabase Realtime subscription that reacts within a second or two
///   whenever another device/collaborator changes a shared vehicle or any
///   of its data (entretien, carburant, dépenses, documents, rappels,
///   kilométrage, fréquences)
///
/// Every table syncs in the same fixed order every pass - vehicles first,
/// since every other table's row references a vehicle_id that must already
/// exist locally for its own pull to make sense - then each business table.
///
/// Started once from [AppGate] when the gate reaches `_GateStep.unlocked`,
/// stopped when the widget owning it is disposed (app closed) - it is not
/// tied to sign-in/sign-out, since every *SyncService.syncNow already
/// no-ops without a session.
class SyncCoordinator {
  SyncCoordinator({
    required this._db,
    required this._clientFn,
    required this.vehicles,
    required this.maintenance,
    required this.expenses,
    required this.fuel,
    required this.documents,
    required this.reminders,
    required this.mileage,
    required this.frequencyPrefs,
    required this.providers,
    required this.notifications,
    required this.conflicts,
  });

  final AppDatabase _db;
  // A closure, not a resolved value - see e.g. ProviderSyncService's
  // identical field for why (merely constructing this coordinator - which
  // happens the moment ANY repository provider watches it - must never
  // touch Supabase.instance before start()/syncAll() actually needs it).
  final SupabaseClient Function() _clientFn;
  SupabaseClient get _client => _clientFn();
  final VehicleSyncService vehicles;
  final MaintenanceSyncService maintenance;
  final ExpenseSyncService expenses;
  final FuelSyncService fuel;
  final DocumentSyncService documents;
  final ReminderSyncService reminders;
  final MileageSyncService mileage;
  final FrequencyPrefSyncService frequencyPrefs;
  final ProviderSyncService providers;
  final NotificationRepository notifications;
  final ConflictRepository conflicts;

  // Conflict ids already notified about, so a conflict sitting unresolved
  // across many sync passes only ever produces one notification, not one
  // every 30 seconds.
  final Set<String> _notifiedConflictIds = {};

  Timer? _timer;
  final List<RealtimeChannel> _channels = [];
  bool _started = false;
  StreamSubscription<List<ConnectivityResult>>? _connectivitySub;
  bool _hadConnectivity = true;

  // Short enough that a collaborator's change reliably shows up well before
  // anyone would think to ask "did that actually save?", long enough to
  // never feel like polling.
  static const _pollInterval = Duration(seconds: 30);

  static const _collaborativeTables = [
    'maintenance_entries',
    'expenses',
    'fuel_entries',
    'documents',
    'reminders',
    'mileage_entries',
    'operation_frequency_preferences',
  ];

  Future<void> syncAll() async {
    // Order matters: a child row's vehicle_id must already exist locally
    // (or the child sync's own upsert would just be pointless) before its
    // own pull runs.
    await vehicles.syncNow();
    await maintenance.syncNow();
    await expenses.syncNow();
    await fuel.syncNow();
    await documents.syncNow();
    await reminders.syncNow();
    await mileage.syncNow();
    await frequencyPrefs.syncNow();
    await providers.syncNow();
    await _notifyNewConflicts();
  }

  /// A version-mismatch push is recorded by ConflictRepository from deep
  /// inside each *SyncService, which has no notion of "notify the user" -
  /// centralizing that here (rather than threading NotificationRepository
  /// into all eight services) keeps "what happened" and "tell the user"
  /// as two separate concerns.
  Future<void> _notifyNewConflicts() async {
    final myUserId = _client.auth.currentUser?.id;
    if (myUserId == null) return;
    final unresolved = await (_db.select(
      _db.syncConflicts,
    )..where((c) => c.resolved.equals(false))).get();
    for (final conflict in unresolved) {
      if (_notifiedConflictIds.contains(conflict.id)) continue;
      _notifiedConflictIds.add(conflict.id);
      await notifications.add(
        accountId: myUserId,
        type: AppNotificationType.syncConflict,
        title: 'Modification simultanée détectée',
        body:
            'Une donnée a été modifiée à la fois ici et par un autre '
            'collaborateur - choisissez quelle version garder.',
        vehicleId: conflict.vehicleId,
      );
    }
  }

  void start() {
    if (_started) return;
    _started = true;
    unawaited(syncAll());
    _timer = Timer.periodic(_pollInterval, (_) => syncAll());

    // Mission: "dès que la connexion revient, l'application relance
    // automatiquement la file d'attente" - the 30s timer alone already
    // gets there eventually, but a device that just regained signal after
    // being offline shouldn't have to wait up to 30s for its pending
    // queue to drain; react to the none -> some transition immediately
    // instead. Guarded so a device oscillating between two "connected"
    // radio types (wifi -> mobile data) doesn't refire on every hop.
    _connectivitySub = Connectivity().onConnectivityChanged.listen((results) {
      final hasConnectivity = !results.contains(ConnectivityResult.none);
      if (hasConnectivity && !_hadConnectivity) {
        unawaited(syncAll());
      }
      _hadConnectivity = hasConnectivity;
    });

    final vehiclesChannel = _client
        .channel('vehicles-sync')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'vehicles',
          callback: (_) => syncAll(),
        )
        .onPostgresChanges(
          // Access being granted, revoked, or its role changed for a
          // shared vehicle - reacting to this (not just to `vehicles`
          // itself) is what makes revocation and permission downgrades
          // take effect within a second or two instead of waiting for the
          // next periodic pass.
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'vehicle_members',
          callback: (_) => syncAll(),
        )
        .subscribe();
    _channels.add(vehiclesChannel);

    // Prestataires aren't vehicle-scoped (no vehicle_id, never shared with a
    // collaborator) - a plain resync trigger is enough, no _maybeNotify
    // vehicle lookup applies here.
    final providersChannel = _client
        .channel('service_providers-sync')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'service_providers',
          callback: (_) => syncAll(),
        )
        .subscribe();
    _channels.add(providersChannel);

    for (final table in _collaborativeTables) {
      final channel = _client
          .channel('$table-sync')
          .onPostgresChanges(
            event: PostgresChangeEvent.all,
            schema: 'public',
            table: table,
            callback: (payload) {
              unawaited(_maybeNotify(table, payload));
              syncAll();
            },
          )
          .subscribe();
      _channels.add(channel);
    }
  }

  /// Turns a collaborator's realtime change into a notification - never for
  /// this device's own echo of its own push, and never for a delete event
  /// (this app only ever soft-deletes via an UPDATE, so a real DELETE
  /// realtime payload only ever carries a primary key, nothing worth
  /// reporting on).
  Future<void> _maybeNotify(String table, PostgresChangePayload payload) async {
    final myUserId = _client.auth.currentUser?.id;
    if (myUserId == null) return;
    final row = payload.newRecord;
    if (row.isEmpty) return;
    final actorId =
        row['updated_by'] as String? ?? row['created_by'] as String?;
    if (actorId == null || actorId == myUserId) return;

    final vehicleId = row['vehicle_id'] as String?;
    if (vehicleId == null) return;
    final vehicle = await (_db.select(
      _db.vehicles,
    )..where((v) => v.id.equals(vehicleId))).getSingleOrNull();
    final vehicleLabel = vehicle != null
        ? '${vehicle.brand} ${vehicle.model}'
        : 'un véhicule partagé';
    final isDeleted = row['is_deleted'] as bool? ?? false;

    await notifications.add(
      accountId: myUserId,
      type: isDeleted
          ? AppNotificationType.remoteDelete
          : AppNotificationType.remoteEdit,
      title: _titleFor(table, isDeleted),
      body: vehicleLabel,
      vehicleId: vehicleId,
    );
  }

  String _titleFor(String table, bool isDeleted) {
    final module = switch (table) {
      'maintenance_entries' => 'un entretien',
      'expenses' => 'une dépense',
      'fuel_entries' => 'un plein',
      'documents' => 'un document',
      'reminders' => 'un rappel',
      'mileage_entries' => 'le kilométrage',
      'operation_frequency_preferences' => 'une fréquence d\'entretien',
      _ => 'une donnée',
    };
    return isDeleted ? '$module a été supprimé' : '$module a été modifié';
  }

  void stop() {
    _timer?.cancel();
    _timer = null;
    unawaited(_connectivitySub?.cancel());
    _connectivitySub = null;
    for (final channel in _channels) {
      unawaited(_client.removeChannel(channel));
    }
    _channels.clear();
    _started = false;
  }
}

final syncCoordinatorProvider = Provider<SyncCoordinator>((ref) {
  final coordinator = SyncCoordinator(
    db: ref.watch(appDatabaseProvider),
    clientFn: () => Supabase.instance.client,
    vehicles: ref.watch(vehicleSyncServiceProvider),
    maintenance: ref.watch(maintenanceSyncServiceProvider),
    expenses: ref.watch(expenseSyncServiceProvider),
    fuel: ref.watch(fuelSyncServiceProvider),
    documents: ref.watch(documentSyncServiceProvider),
    reminders: ref.watch(reminderSyncServiceProvider),
    mileage: ref.watch(mileageSyncServiceProvider),
    frequencyPrefs: ref.watch(frequencyPrefSyncServiceProvider),
    providers: ref.watch(providerSyncServiceProvider),
    notifications: ref.watch(notificationRepositoryProvider),
    conflicts: ref.watch(conflictRepositoryProvider),
  );
  ref.onDispose(coordinator.stop);
  return coordinator;
});
