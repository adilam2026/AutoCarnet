import 'package:autocarnet/core/database/database.dart';
import 'package:autocarnet/features/documents/data/document_repository.dart';
import 'package:autocarnet/features/maintenance/data/maintenance_repository.dart';
import 'package:autocarnet/features/reminders/data/reminder_repository.dart';
import 'package:autocarnet/features/resale/domain/resale_estimation.dart';
import 'package:autocarnet/features/resale/domain/resale_health.dart';
import 'package:autocarnet/features/resale/domain/resale_readiness.dart';
import 'package:autocarnet/features/timeline/data/timeline_repository.dart';
import 'package:autocarnet/features/vehicles/data/vehicle_repository.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late AppDatabase db;
  late VehicleRepository vehicles;
  late ReminderRepository reminders;
  late MaintenanceRepository maintenance;
  late DocumentRepository documents;
  late String vehicleId;

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    final timeline = TimelineRepository(db);
    reminders = ReminderRepository(db);
    vehicles = VehicleRepository(db, timeline, reminders);
    maintenance = MaintenanceRepository(db, timeline, reminders, vehicles);
    documents = DocumentRepository(db, timeline, reminders);
    vehicleId = await vehicles.createVehicle(
      brand: 'Renault',
      model: 'Clio',
      currentMileage: 50000,
    );
  });

  tearDown(() => db.close());

  group('computeResaleHealthScore', () {
    test('a brand new vehicle with no history scores below 100 and explains why', () async {
      final health = computeResaleHealthScore(
        activeReminders: const [],
        maintenanceEntries: const [],
        documents: const [],
        completeness: 0.2,
      );
      expect(health.score, lessThan(100));
      expect(health.factors, isNotEmpty);
      expect(
        health.factors.any((f) => f.impact == HealthImpact.negative),
        isTrue,
      );
    });

    test('an overdue reminder drags the score down more than an upcoming one', () async {
      final overdue = computeResaleHealthScore(
        activeReminders: [
          Reminder(
            id: 'r1',
            vehicleId: vehicleId,
            sourceType: 'document',
            sourceId: 'doc-1',
            title: 'Assurance',
            dueDate: DateTime.now().subtract(const Duration(days: 5)),
            dueMileage: null,
            priority: 'normal',
            status: ReminderStatus.active,
            snoozedUntil: null,
            createdAt: DateTime.now(),
            updatedAt: DateTime.now(),
          ),
        ],
        maintenanceEntries: const [],
        documents: const [],
        completeness: 0.5,
      );
      final upcoming = computeResaleHealthScore(
        activeReminders: [
          Reminder(
            id: 'r2',
            vehicleId: vehicleId,
            sourceType: 'document',
            sourceId: 'doc-2',
            title: 'Assurance',
            dueDate: DateTime.now().add(const Duration(days: 200)),
            dueMileage: null,
            priority: 'normal',
            status: ReminderStatus.active,
            snoozedUntil: null,
            createdAt: DateTime.now(),
            updatedAt: DateTime.now(),
          ),
        ],
        maintenanceEntries: const [],
        documents: const [],
        completeness: 0.5,
      );
      expect(overdue.score, lessThan(upcoming.score));
    });

    test('recent maintenance and up-to-date documents raise the score using real repository data', () async {
      await maintenance.createEntry(
        vehicleId: vehicleId,
        category: 'Vidange',
        date: DateTime.now().subtract(const Duration(days: 30)),
        mileage: 50000,
      );
      await documents.createDocument(
        vehicleId: vehicleId,
        type: 'Assurance',
        expiryDate: DateTime.now().add(const Duration(days: 300)),
      );
      final maintenanceEntries = await maintenance.watchForVehicle(vehicleId).first;
      final docs = await documents.watchForVehicle(vehicleId).first;

      final health = computeResaleHealthScore(
        activeReminders: const [],
        maintenanceEntries: maintenanceEntries,
        documents: docs,
        completeness: 0.9,
      );
      expect(
        health.factors.any((f) => f.impact == HealthImpact.positive),
        isTrue,
      );
    });
  });

  group('computeResaleReadiness', () {
    test('flags every unmet item and generates a matching recommendation', () async {
      final readiness = computeResaleReadiness(
        completeness: 0.1,
        maintenanceEntries: const [],
        documents: const [],
        activeReminders: const [],
        mileageHistory: const [],
      );
      // No active reminders trivially satisfies "no overdue reminder", so
      // that single item is expected to be ok - every other item (fed by
      // data that's actually missing) must not be.
      final notOk = readiness.items.where((i) => i.label != 'Échéances traitées');
      expect(notOk.every((i) => !i.ok), isTrue);
      expect(readiness.recommendations.length, notOk.length);
    });

    test('a well-documented vehicle has no outstanding recommendations', () async {
      await maintenance.createEntry(
        vehicleId: vehicleId,
        category: 'Vidange',
        date: DateTime.now(),
        mileage: 50000,
      );
      await documents.createDocument(
        vehicleId: vehicleId,
        type: 'Assurance',
        expiryDate: DateTime.now().add(const Duration(days: 300)),
      );
      await vehicles.recordManualMileage(vehicleId, 50500);
      final maintenanceEntries = await maintenance.watchForVehicle(vehicleId).first;
      final docs = await documents.watchForVehicle(vehicleId).first;
      final mileageHistory = await vehicles.watchMileageHistory(vehicleId).first;

      final readiness = computeResaleReadiness(
        completeness: 0.9,
        maintenanceEntries: maintenanceEntries,
        documents: docs,
        activeReminders: const [],
        mileageHistory: mileageHistory,
      );
      expect(readiness.recommendations, isEmpty);
    });
  });

  group('NoMarketSourceResaleEstimator', () {
    test('never fabricates a price - always reports the estimate as unavailable', () {
      const estimator = NoMarketSourceResaleEstimator();
      final health = computeResaleHealthScore(
        activeReminders: const [],
        maintenanceEntries: const [],
        documents: const [],
        completeness: 1,
      );
      final estimate = estimator.estimate(
        ResaleEstimationInput(
          brand: 'Renault',
          model: 'Clio',
          year: 2020,
          currentMileage: 60000,
          health: health,
        ),
      );
      expect(estimate.isAvailable, isFalse);
      expect(estimate.amountsByTier, isEmpty);
      expect(estimate.message, isNotEmpty);
    });
  });
}
