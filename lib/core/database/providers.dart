import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'database.dart';

/// Single instance of the local (offline-first) database, shared by every
/// module's repository. Never construct AppDatabase() anywhere else.
final appDatabaseProvider = Provider<AppDatabase>((ref) {
  final db = AppDatabase();
  ref.onDispose(db.close);
  return db;
});
