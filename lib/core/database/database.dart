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
  int get schemaVersion => 1;

  static QueryExecutor _openConnection() {
    return LazyDatabase(() async {
      final dir = await getApplicationDocumentsDirectory();
      final file = File(p.join(dir.path, 'autocarnet.sqlite'));
      return NativeDatabase.createInBackground(file);
    });
  }
}
