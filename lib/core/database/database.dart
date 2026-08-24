import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'tables.dart';

export 'tables.dart';

part 'database.g.dart';

@DriftDatabase(
  tables: [
    LocalProfiles,
    Vehicles,
    MileageEntries,
    ServiceProviders,
    Documents,
    DocumentVersions,
    DocumentAttachments,
    MaintenanceEntries,
    MaintenanceParts,
    Expenses,
    FuelEntries,
    TimelineEvents,
    AuditEvents,
    OperationFrequencyPreferences,
    Reminders,
    SyncConflicts,
    AppNotifications,
  ],
)
class AppDatabase extends _$AppDatabase {
  AppDatabase([QueryExecutor? executor]) : super(executor ?? _openConnection());

  @override
  int get schemaVersion => 10;

  @override
  MigrationStrategy get migration => MigrationStrategy(
        onCreate: (m) => m.createAll(),
        onUpgrade: (m, from, to) async {
          if (from < 2) {
            await m.addColumn(vehicles, vehicles.ownerId);
          }
          if (from < 3) {
            await m.addColumn(vehicles, vehicles.myRole);
          }
          if (from < 4) {
            await m.addColumn(serviceProviders, serviceProviders.ownerId);
            await m.addColumn(documents, documents.ownerId);
          }
          if (from < 5) {
            await m.addColumn(localProfiles, localProfiles.ownerId);
          }
          if (from < 6) {
            // Phase 4: multi-table collaboration - every synced table gets
            // an optimistic-concurrency version counter plus who
            // created/last touched it, and two brand new local-only tables
            // (SyncConflicts, AppNotifications) back the conflict-
            // resolution UI and the notification center.
            await m.addColumn(vehicles, vehicles.version);
            await m.addColumn(vehicles, vehicles.createdBy);
            await m.addColumn(vehicles, vehicles.updatedBy);
            await m.addColumn(maintenanceEntries, maintenanceEntries.syncStatus);
            await m.addColumn(maintenanceEntries, maintenanceEntries.version);
            await m.addColumn(maintenanceEntries, maintenanceEntries.createdBy);
            await m.addColumn(maintenanceEntries, maintenanceEntries.updatedBy);
            await m.addColumn(expenses, expenses.syncStatus);
            await m.addColumn(expenses, expenses.version);
            await m.addColumn(expenses, expenses.createdBy);
            await m.addColumn(expenses, expenses.updatedBy);
            await m.addColumn(fuelEntries, fuelEntries.syncStatus);
            await m.addColumn(fuelEntries, fuelEntries.version);
            await m.addColumn(fuelEntries, fuelEntries.createdBy);
            await m.addColumn(fuelEntries, fuelEntries.updatedBy);
            await m.addColumn(documents, documents.syncStatus);
            await m.addColumn(documents, documents.version);
            await m.addColumn(documents, documents.updatedBy);
            await m.addColumn(documentVersions, documentVersions.updatedAt);
            await m.addColumn(documentVersions, documentVersions.syncStatus);
            await m.addColumn(documentVersions, documentVersions.version);
            await m.addColumn(documentVersions, documentVersions.createdBy);
            await m.addColumn(documentVersions, documentVersions.updatedBy);
            await m.addColumn(reminders, reminders.syncStatus);
            await m.addColumn(reminders, reminders.version);
            await m.addColumn(reminders, reminders.createdBy);
            await m.addColumn(reminders, reminders.updatedBy);
            await m.addColumn(mileageEntries, mileageEntries.syncStatus);
            await m.addColumn(mileageEntries, mileageEntries.createdBy);
            await m.addColumn(
                operationFrequencyPreferences, operationFrequencyPreferences.syncStatus);
            await m.addColumn(
                operationFrequencyPreferences, operationFrequencyPreferences.version);
            await m.addColumn(
                operationFrequencyPreferences, operationFrequencyPreferences.createdBy);
            await m.addColumn(
                operationFrequencyPreferences, operationFrequencyPreferences.updatedBy);
            await m.createTable(syncConflicts);
            await m.createTable(appNotifications);
          }
          if (from < 7) {
            // "Acquisition" (date d'acquisition + prix d'achat) is removed
            // from the vehicle sheet entirely - the valuation engine
            // (Revendre) now always uses its own reference price instead of
            // a real purchase price, by explicit choice: accepting a less
            // precise estimate over keeping a UI section nobody should see
            // again.
            await m.dropColumn(vehicles, 'acquisition_date');
            await m.dropColumn(vehicles, 'purchase_price');
          }
          if (from < 8) {
            // Per-vehicle home-dashboard card colour ("carte identité du
            // véhicule", design-review pass) - existing rows are backfilled
            // transparently by VehicleRepository.backfillMissingCardColors,
            // called once at app startup.
            await m.addColumn(vehicles, vehicles.cardColorKey);
          }
          if (from < 9) {
            // Prestataires: real categorized types (concessionnaire, garage
            // agréé, centre mécanique, assurance, station-service, autre) -
            // corrections pass. Existing rows simply have no category
            // (nullable) rather than a guessed one.
            await m.addColumn(serviceProviders, serviceProviders.category);
          }
          if (from < 10) {
            // Finition / niveau d'équipement - structured field for the
            // resale valuation engine (mission 2026). Existing rows simply
            // have none (nullable) rather than a guessed level.
            await m.addColumn(vehicles, vehicles.finishLevel);
          }
        },
      );

  static QueryExecutor _openConnection() {
    return LazyDatabase(() async {
      final dir = await getApplicationDocumentsDirectory();
      final file = File(p.join(dir.path, 'autocarnet.sqlite'));
      return NativeDatabase.createInBackground(file);
    });
  }
}
