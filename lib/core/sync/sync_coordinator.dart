import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../database/database.dart';
import '../database/providers.dart';
import '../notifications/notification_repository.dart';
import 'document_sync_service.dart';
import 'expense_sync_service.dart';
import 'frequency_pref_sync_service.dart';
import 'fuel_sync_service.dart';
import 'maintenance_sync_service.dart';
import 'mileage_sync_service.dart';
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
    required this._client,
    required this.vehicles,
    required this.maintenance,
    required this.expenses,
    required this.fuel,
    required this.documents,
    required this.reminders,
    required this.mileage,
    required this.frequencyPrefs,
    required this.notifications,
  });

  final AppDatabase _db;
  final SupabaseClient _client;
  final VehicleSyncService vehicles;
  final MaintenanceSyncService maintenance;
  final ExpenseSyncService expenses;
  final FuelSyncService fuel;
  final DocumentSyncService documents;
  final ReminderSyncService reminders;
  final MileageSyncService mileage;
  final FrequencyPrefSyncService frequencyPrefs;
  final NotificationRepository notifications;

  Timer? _timer;
  final List<RealtimeChannel> _channels = [];
  bool _started = false;

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
  }

  void start() {
    if (_started) return;
    _started = true;
    unawaited(syncAll());
    _timer = Timer.periodic(_pollInterval, (_) => syncAll());

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
    final actorId = row['updated_by'] as String? ?? row['created_by'] as String?;
    if (actorId == null || actorId == myUserId) return;

    final vehicleId = row['vehicle_id'] as String?;
    if (vehicleId == null) return;
    final vehicle =
        await (_db.select(_db.vehicles)..where((v) => v.id.equals(vehicleId))).getSingleOrNull();
    final vehicleLabel =
        vehicle != null ? '${vehicle.brand} ${vehicle.model}' : 'un véhicule partagé';
    final isDeleted = row['is_deleted'] as bool? ?? false;

    await notifications.add(
      accountId: myUserId,
      type: isDeleted ? AppNotificationType.remoteDelete : AppNotificationType.remoteEdit,
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
    client: Supabase.instance.client,
    vehicles: ref.watch(vehicleSyncServiceProvider),
    maintenance: ref.watch(maintenanceSyncServiceProvider),
    expenses: ref.watch(expenseSyncServiceProvider),
    fuel: ref.watch(fuelSyncServiceProvider),
    documents: ref.watch(documentSyncServiceProvider),
    reminders: ref.watch(reminderSyncServiceProvider),
    mileage: ref.watch(mileageSyncServiceProvider),
    frequencyPrefs: ref.watch(frequencyPrefSyncServiceProvider),
    notifications: ref.watch(notificationRepositoryProvider),
  );
  ref.onDispose(coordinator.stop);
  return coordinator;
});
