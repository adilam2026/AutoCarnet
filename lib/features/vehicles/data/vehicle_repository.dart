import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/database/database.dart';
import '../../../core/database/providers.dart';
import '../../../core/utils/id_generator.dart';
import '../../../core/utils/mileage_result.dart';
import '../../audit/data/audit_repository.dart';
import '../../reminders/data/reminder_repository.dart';

class VehicleRepository {
  VehicleRepository(this._db, this._audit, this._reminders);
  final AppDatabase _db;
  final AuditRepository _audit;
  final ReminderRepository _reminders;

  Stream<List<Vehicle>> watchAll() {
    final query = _db.select(_db.vehicles)
      ..where((v) => v.isDeleted.equals(false))
      ..orderBy([(v) => OrderingTerm.desc(v.updatedAt)]);
    return query.watch();
  }

  Stream<Vehicle> watchOne(String id) {
    final query = _db.select(_db.vehicles)..where((v) => v.id.equals(id));
    return query.watchSingle();
  }

  Future<Vehicle> getOne(String id) {
    final query = _db.select(_db.vehicles)..where((v) => v.id.equals(id));
    return query.getSingle();
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
    DateTime? acquisitionDate,
    double? purchasePrice,
    String? comments,
  }) async {
    final id = newId();
    final now = DateTime.now();
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
            photoPath: Value(photoPath),
            acquisitionDate: Value(acquisitionDate),
            purchasePrice: Value(purchasePrice),
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
    return id;
  }

  Future<void> updateVehicle(Vehicle vehicle, {String? changeSummary}) async {
    await (_db.update(_db.vehicles)..where((v) => v.id.equals(vehicle.id)))
        .write(vehicle.toCompanion(true).copyWith(updatedAt: Value(DateTime.now())));
    await _audit.log(
      vehicleId: vehicle.id,
      entityType: 'vehicle',
      entityId: vehicle.id,
      action: 'updated',
      summary: changeSummary ?? 'Fiche véhicule modifiée',
    );
  }

  Future<void> setStatus(String vehicleId, VehicleStatus status) async {
    await (_db.update(_db.vehicles)..where((v) => v.id.equals(vehicleId)))
        .write(VehiclesCompanion(
      status: Value(status),
      updatedAt: Value(DateTime.now()),
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
    ));
    await _audit.log(
      vehicleId: vehicleId,
      entityType: 'vehicle',
      entityId: vehicleId,
      action: 'mileage_corrected',
      summary: 'Kilométrage mis à jour : ${newValue.toStringAsFixed(0)} km',
    );
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
      ));
    }
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
    // reaching 100% (photoPath: photo capture is a later phase).
    final fields = <Object?>[
      v.trim,
      v.year,
      v.vin,
      v.plate,
      v.motorization,
      v.fuelType,
      v.transmission,
      v.color,
      v.acquisitionDate,
      v.purchasePrice,
      v.firstRegistrationDate,
      v.condition,
      v.comments,
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
  );
});

final vehiclesListProvider = StreamProvider<List<Vehicle>>((ref) {
  return ref.watch(vehicleRepositoryProvider).watchAll();
});

final vehicleByIdProvider = StreamProvider.family<Vehicle, String>((ref, id) {
  return ref.watch(vehicleRepositoryProvider).watchOne(id);
});

final vehicleMileageHistoryProvider =
    StreamProvider.family<List<MileageEntry>, String>((ref, vehicleId) {
  return ref.watch(vehicleRepositoryProvider).watchMileageHistory(vehicleId);
});
