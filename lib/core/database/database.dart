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
  ],
)
class AppDatabase extends _$AppDatabase {
  AppDatabase([QueryExecutor? executor]) : super(executor ?? _openConnection());

  @override
  int get schemaVersion => 3;

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
