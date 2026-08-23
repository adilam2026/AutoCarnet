import 'dart:async';

import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/database/database.dart';
import '../../../core/database/providers.dart';
import '../../../core/sync/vehicle_sync_service.dart';
import '../../../core/utils/id_generator.dart';
import '../../../core/utils/mileage_result.dart';
import '../../account/data/account_repository.dart';
import '../../audit/data/audit_repository.dart';
import '../../reminders/data/reminder_repository.dart';
import '../domain/vehicle_card_color.dart';

class VehicleRepository {
  VehicleRepository(this._db, this._audit, this._reminders, [this._sync]);
  final AppDatabase _db;
  final AuditRepository _audit;
  final ReminderRepository _reminders;
  // Optional: absent in unit tests (no Supabase session to sync to). When
  // present, every local write nudges a fire-and-forget cloud sync pass -
  // never awaited, so a slow/offline network can never delay a local save.
  final VehicleSyncService? _sync;

  void _nudgeSync() {
    unawaited(_sync?.syncNow());
  }

  /// [currentUserId] scopes the list to the signed-in account: a vehicle is
  /// visible if it's unowned locally (never synced - offline-created, or no
  /// cloud account at all), owned by this account, or shared with it
  /// (cached [Vehicle.myRole] set - only ever trustworthy because
  /// [handleAccountSwitch] clears it on every account change, see there).
  /// This is what keeps two different accounts that have used the same
  /// physical device from ever seeing each other's vehicles mixed
  /// together - without deleting anything: a previous account's vehicles
  /// simply stay invisible (never re-appearing for a different account)
  /// until that same account signs back in. Pass null only when there is
  /// no signed-in account at all (offline-only device), where every
  /// locally-created vehicle is visible by definition.
  Stream<List<Vehicle>> watchAll({String? currentUserId}) {
    final query = _db.select(_db.vehicles)..where((v) => v.isDeleted.equals(false));
    if (currentUserId != null) {
      query.where(
        (v) => v.ownerId.isNull() | v.ownerId.equals(currentUserId) | v.myRole.isNotNull(),
      );
    }
    query.orderBy([(v) => OrderingTerm.desc(v.updatedAt)]);
    return query.watch();
  }

  /// Account-switch safety net, called once from
  /// AppGate._onAccountAuthenticated when a *different* account than last
  /// time just signed in on this device. Two things can be stale from the
  /// previous account's perspective, and neither is ever deleted:
  /// - a vehicle still missing an owner locally (created offline, never
  ///   synced before the switch) can only belong to [previousOwnerId] -
  ///   tagged explicitly so [watchAll] correctly excludes it from the new
  ///   account's view, and the previous account sees it again if it signs
  ///   back in here;
  /// - [Vehicle.myRole] ("shared with me, and at what level") was cached
  ///   for the *previous* account's memberships specifically - it carries
  ///   no account id of its own, so it can never be trusted for a
  ///   different account without first being cleared. The very next sync
  ///   pass repopulates it correctly for whoever is signed in now (or
  ///   drops the row entirely if the new account has no access at all -
  ///   see VehicleSyncService's revocation pass).
  Future<void> handleAccountSwitch(String previousOwnerId) async {
    await (_db.update(_db.vehicles)..where((v) => v.ownerId.isNull()))
        .write(VehiclesCompanion(ownerId: Value(previousOwnerId)));
    await (_db.update(_db.vehicles)..where((v) => v.myRole.isNotNull()))
        .write(const VehiclesCompanion(myRole: Value(null)));
  }

  /// Nullable on purpose (`watchSingleOrNull`, not `watchSingle`): right
  /// after accepting a share invite, the vehicle exists on the cloud but
  /// hasn't necessarily reached this device's local mirror yet (the next
  /// sync pass does that - see VehicleSyncService._pull). A screen watching
  /// this stream during that window must see a normal "not here yet" data
  /// state it can react to (e.g. show a syncing view and retry), never a
  /// crash - `watchSingle()` throws `StateError('Expected exactly one
  /// element, but got 0')` the moment the underlying query has zero rows,
  /// which is exactly what happened here.
  Stream<Vehicle?> watchOne(String id) {
    final query = _db.select(_db.vehicles)..where((v) => v.id.equals(id));
    return query.watchSingleOrNull();
  }

  Future<Vehicle> getOne(String id) {
    final query = _db.select(_db.vehicles)..where((v) => v.id.equals(id));
    return query.getSingle();
  }

  /// Whether this vehicle has ever reached this device's local database -
  /// false right after joining a shared vehicle on another device, until
  /// the next sync pull. Callers that just accepted a share invite must
  /// check this before navigating to the vehicle's own screens, which
  /// otherwise call [watchOne]/[getOne] and crash on zero local rows.
  Future<bool> existsLocally(String id) async {
    final query = _db.select(_db.vehicles)..where((v) => v.id.equals(id));
    return await query.getSingleOrNull() != null;
  }

  /// Quick creation (Principe 2): only brand, model and current mileage are
  /// required, everything else can be completed later.
  Future<String> createVehicle({
    required String brand,
    required String model,
    required double currentMileage,
    String? trim,
    int? year,
    String? vin,
    String? plate,
    String? motorization,
    String? fuelType,
    String? transmission,
    String? color,
    String? photoPath,
    String? comments,
  }) async {
    final id = newId();
    final now = DateTime.now();
    final cardColor = await _nextCardColor();
    await _db.into(_db.vehicles).insert(
          VehiclesCompanion.insert(
            id: id,
            brand: brand,
            model: model,
            currentMileage: currentMileage,
            trim: Value(trim),
            year: Value(year),
            vin: Value(vin),
            plate: Value(plate),
            motorization: Value(motorization),
            fuelType: Value(fuelType),
            transmission: Value(transmission),
            color: Value(color),
            cardColorKey: Value(cardColor.storageKey),
            photoPath: Value(photoPath),
            comments: Value(comments),
            createdAt: now,
            updatedAt: now,
          ),
        );
    await _db.into(_db.mileageEntries).insert(
          MileageEntriesCompanion.insert(
            id: newId(),
            vehicleId: id,
            value: currentMileage,
            recordedAt: now,
            source: 'manual',
            createdAt: now,
          ),
        );
    await _audit.log(
      vehicleId: id,
      entityType: 'vehicle',
      entityId: id,
      action: 'created',
      summary: '$brand $model ajouté au carnet',
      occurredAt: now,
    );
    _nudgeSync();
    return id;
  }

  /// Picks the next card colour for a vehicle being created right now:
  /// least-used among every non-deleted vehicle already on this device, so
  /// a growing garage stays visually distinct as long as the palette allows
  /// it (spec: never a random draw, never re-picked later).
  Future<VehicleCardColor> _nextCardColor() async {
    final existing = await (_db.select(_db.vehicles)..where((v) => v.isDeleted.equals(false)))
        .get();
    return VehicleCardColor.nextFor(existing.map((v) => v.cardColorKey));
  }

  /// Manual personalisation from the fiche véhicule ("Couleur de la
  /// carte") - unlike [_nextCardColor], this never tries to avoid a colour
  /// already used by another vehicle: once the user picks one, it's
  /// entirely their choice (spec: two vehicles may deliberately share a
  /// colour).
  Future<void> updateVehicleCardColor(String vehicleId, VehicleCardColor color) async {
    await (_db.update(_db.vehicles)..where((v) => v.id.equals(vehicleId))).write(
      VehiclesCompanion(
        cardColorKey: Value(color.storageKey),
        updatedAt: Value(DateTime.now()),
        syncStatus: const Value('pendingSync'),
      ),
    );
    _nudgeSync();
  }

  /// One-time, idempotent migration for vehicles created before per-vehicle
  /// card colours existed (schema v8): assigns each a colour transparently,
  /// oldest first, using the same least-used-first logic as new vehicles -
  /// touches only [cardColorKey], never re-creates a vehicle or changes any
  /// other field. Safe to call on every app start (a no-op once every
  /// vehicle already has one) - see AppGate._evaluate.
  Future<void> backfillMissingCardColors() async {
    final all =
        await (_db.select(_db.vehicles)..where((v) => v.isDeleted.equals(false))).get();
    final missing = all.where((v) => v.cardColorKey == null).toList()
      ..sort((a, b) => a.createdAt.compareTo(b.createdAt));
    if (missing.isEmpty) return;
    final assignedKeys = [
      for (final v in all)
        if (v.cardColorKey != null) v.cardColorKey,
    ];
    for (final vehicle in missing) {
      final color = VehicleCardColor.nextFor(assignedKeys);
      assignedKeys.add(color.storageKey);
      await (_db.update(_db.vehicles)..where((v) => v.id.equals(vehicle.id)))
          .write(VehiclesCompanion(cardColorKey: Value(color.storageKey)));
    }
  }

  Future<void> updateVehicle(Vehicle vehicle, {String? changeSummary}) async {
    await (_db.update(_db.vehicles)..where((v) => v.id.equals(vehicle.id))).write(
      vehicle.toCompanion(true).copyWith(
            updatedAt: Value(DateTime.now()),
            syncStatus: const Value('pendingSync'),
          ),
    );
    await _audit.log(
      vehicleId: vehicle.id,
      entityType: 'vehicle',
      entityId: vehicle.id,
      action: 'updated',
      summary: changeSummary ?? 'Fiche véhicule modifiée',
    );
    _nudgeSync();
  }

  Future<void> setStatus(String vehicleId, VehicleStatus status) async {
    await (_db.update(_db.vehicles)..where((v) => v.id.equals(vehicleId)))
        .write(VehiclesCompanion(
      status: Value(status),
      updatedAt: Value(DateTime.now()),
      syncStatus: const Value('pendingSync'),
    ));
    await _audit.log(
      vehicleId: vehicleId,
      entityType: 'vehicle',
      entityId: vehicleId,
      action: 'status_changed',
      summary: 'Statut changé : ${_statusLabel(status)}',
    );
    // RG-ALR-007: a vehicle that is no longer active stops generating
    // future reminders.
    if (status != VehicleStatus.active) {
      await _reminders.disableAllForVehicle(vehicleId);
    }
    _nudgeSync();
  }

  /// Removes a vehicle added by mistake - unlike [setStatus] (archived/
  /// sold/destroyed), which keeps the vehicle and its full history
  /// reachable, this hides it everywhere. A soft delete, never a hard SQL
  /// delete, so nothing referencing it (documents, expenses, timeline...)
  /// loses its foreign key.
  Future<void> softDelete(String vehicleId) async {
    await (_db.update(_db.vehicles)..where((v) => v.id.equals(vehicleId)))
        .write(VehiclesCompanion(
      isDeleted: const Value(true),
      updatedAt: Value(DateTime.now()),
      syncStatus: const Value('pendingSync'),
    ));
    await _reminders.disableAllForVehicle(vehicleId);
    _nudgeSync();
  }

  String _statusLabel(VehicleStatus s) => switch (s) {
        VehicleStatus.active => 'Actif',
        VehicleStatus.archived => 'Archivé',
        VehicleStatus.sold => 'Vendu',
        VehicleStatus.destroyed => 'Détruit',
      };

  Stream<List<MileageEntry>> watchMileageHistory(String vehicleId) {
    final query = _db.select(_db.mileageEntries)
      ..where((m) => m.vehicleId.equals(vehicleId))
      ..orderBy([(m) => OrderingTerm.desc(m.recordedAt)]);
    return query.watch();
  }

  /// RG-VEH-005: checks whether lowering the mileage would contradict
  /// operations already recorded at a higher mileage.
  Future<MileageCheckResult> checkMileageChange(
    String vehicleId,
    double newValue,
  ) async {
    final vehicle = await getOne(vehicleId);
    if (newValue >= vehicle.currentMileage) {
      return const MileageOk();
    }
    final higherOps = await (_db.select(_db.mileageEntries)
          ..where((m) =>
              m.vehicleId.equals(vehicleId) &
              m.value.isBiggerThanValue(newValue) &
              m.source.equals('manual').not()))
        .get();
    if (higherOps.isNotEmpty) {
      return MileageBlocked(
        higherOps
            .map((e) => '${_sourceLabel(e.source)} — ${e.value.toStringAsFixed(0)} km')
            .toList(),
      );
    }
    return MileageNeedsConfirmation(
      currentMileage: vehicle.currentMileage,
      newMileage: newValue,
    );
  }

  String _sourceLabel(String source) => switch (source) {
        'maintenance' => 'Entretien',
        'fuel' => 'Plein de carburant',
        'document' => 'Document',
        _ => source,
      };

  /// Records a manual mileage update. Callers must have resolved any
  /// [MileageBlocked] / [MileageNeedsConfirmation] beforehand.
  Future<void> recordManualMileage(
    String vehicleId,
    double newValue, {
    String? note,
  }) async {
    final now = DateTime.now();
    await _db.into(_db.mileageEntries).insert(
          MileageEntriesCompanion.insert(
            id: newId(),
            vehicleId: vehicleId,
            value: newValue,
            recordedAt: now,
            source: 'manual',
            note: Value(note),
            createdAt: now,
          ),
        );
    await (_db.update(_db.vehicles)..where((v) => v.id.equals(vehicleId)))
        .write(VehiclesCompanion(
      currentMileage: Value(newValue),
      updatedAt: Value(now),
      syncStatus: const Value('pendingSync'),
    ));
    await _audit.log(
      vehicleId: vehicleId,
      entityType: 'vehicle',
      entityId: vehicleId,
      action: 'mileage_corrected',
      summary: 'Kilométrage mis à jour : ${newValue.toStringAsFixed(0)} km',
    );
    _nudgeSync();
  }

  /// Called by other modules (maintenance, fuel...) when they log an
  /// operation at a given mileage. Only ever raises the vehicle's current
  /// mileage automatically - lowering it always goes through
  /// [checkMileageChange] + [recordManualMileage] so it can never silently
  /// break history (RG-VEH-005).
  Future<void> recordOperationMileage({
    required String vehicleId,
    required double value,
    required String source,
    required String sourceId,
  }) async {
    final now = DateTime.now();
    await _db.into(_db.mileageEntries).insert(
          MileageEntriesCompanion.insert(
            id: newId(),
            vehicleId: vehicleId,
            value: value,
            recordedAt: now,
            source: source,
            sourceId: Value(sourceId),
            createdAt: now,
          ),
        );
    final vehicle = await getOne(vehicleId);
    if (value > vehicle.currentMileage) {
      await (_db.update(_db.vehicles)..where((v) => v.id.equals(vehicleId)))
          .write(VehiclesCompanion(
        currentMileage: Value(value),
        updatedAt: Value(now),
        syncStatus: const Value('pendingSync'),
      ));
    }
    _nudgeSync();
  }

  /// Corrects the mileage value already recorded for a given operation
  /// (editing a maintenance/fuel entry after the fact) instead of adding a
  /// new history row - there is still exactly one mileage entry per
  /// operation. The vehicle's current mileage is recomputed as the max of
  /// all entries so a downward correction can never leave a stale, too-high
  /// current mileage behind.
  Future<void> updateOperationMileage({
    required String vehicleId,
    required String source,
    required String sourceId,
    required double newValue,
  }) async {
    final now = DateTime.now();
    final existing = await (_db.select(_db.mileageEntries)
          ..where((m) => m.source.equals(source) & m.sourceId.equals(sourceId)))
        .getSingleOrNull();
    if (existing != null) {
      await (_db.update(_db.mileageEntries)..where((m) => m.id.equals(existing.id)))
          .write(MileageEntriesCompanion(
        value: Value(newValue),
        recordedAt: Value(now),
      ));
    } else {
      await _db.into(_db.mileageEntries).insert(
            MileageEntriesCompanion.insert(
              id: newId(),
              vehicleId: vehicleId,
              value: newValue,
              recordedAt: now,
              source: source,
              sourceId: Value(sourceId),
              createdAt: now,
            ),
          );
    }
    final all = await (_db.select(_db.mileageEntries)
          ..where((m) => m.vehicleId.equals(vehicleId)))
        .get();
    if (all.isNotEmpty) {
      final maxValue = all.map((m) => m.value).reduce((a, b) => a > b ? a : b);
      await (_db.update(_db.vehicles)..where((v) => v.id.equals(vehicleId)))
          .write(VehiclesCompanion(
        currentMileage: Value(maxValue),
        updatedAt: Value(now),
      ));
    }
  }

  /// Completeness score (RG-VEH-004): purely about how filled-in the sheet
  /// is, independent of the health score.
  double completeness(Vehicle v) {
    // Only counts fields actually reachable from VehicleEditScreen - a
    // field the UI can never fill in must never keep completeness from
    // reaching 100% (photoPath: photo capture is a later phase). Comments
    // is a free note, not structuring data, so it's deliberately excluded
    // too: a sheet with every real field filled in is 100% complete
    // whether or not the owner ever wrote a comment.
    final fields = <Object?>[
      v.trim,
      v.year,
      v.plate,
      v.motorization,
      v.fuelType,
      v.transmission,
      v.color,
      v.firstRegistrationDate,
      v.condition,
    ];
    final filled = fields.where((f) => f != null && f != '').length;
    return filled / fields.length;
  }
}

final vehicleRepositoryProvider = Provider<VehicleRepository>((ref) {
  return VehicleRepository(
    ref.watch(appDatabaseProvider),
    ref.watch(auditRepositoryProvider),
    ref.watch(reminderRepositoryProvider),
    ref.watch(vehicleSyncServiceProvider),
  );
});

final vehiclesListProvider = StreamProvider<List<Vehicle>>((ref) {
  // Rebuilds this stream whenever the signed-in account changes (sign in,
  // sign out, account switch) - see VehicleRepository.watchAll's doc:
  // without re-scoping on every auth change, a vehicle list built for one
  // account could keep showing after a different one signs in.
  ref.watch(authStateChangesProvider);
  final currentUserId = ref.watch(accountRepositoryProvider).currentUser?.id;
  return ref.watch(vehicleRepositoryProvider).watchAll(currentUserId: currentUserId);
});

final vehicleByIdProvider = StreamProvider.family<Vehicle?, String>((ref, id) {
  return ref.watch(vehicleRepositoryProvider).watchOne(id);
});

final vehicleMileageHistoryProvider =
    StreamProvider.family<List<MileageEntry>, String>((ref, vehicleId) {
  return ref.watch(vehicleRepositoryProvider).watchMileageHistory(vehicleId);
});
