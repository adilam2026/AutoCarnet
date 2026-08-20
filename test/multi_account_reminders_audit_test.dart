import 'package:autocarnet/core/database/database.dart';
import 'package:autocarnet/features/audit/data/audit_repository.dart';
import 'package:autocarnet/features/reminders/data/reminder_repository.dart';
import 'package:autocarnet/features/vehicles/data/vehicle_repository.dart';
import 'package:drift/drift.dart' hide isNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

/// Reminders and audit events are always scoped to a vehicle - the same
/// cross-account leak that affected the vehicle list itself
/// (multi_account_isolation_test.dart) affected these two feeds just as
/// directly: a reminder or an audit entry for a vehicle a different
/// account owns must never surface just because the row is still sitting
/// in this device's local cache.
void main() {
  late AppDatabase db;
  late VehicleRepository vehicles;
  late ReminderRepository reminders;
  late AuditRepository audit;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    vehicles = VehicleRepository(db, AuditRepository(db), ReminderRepository(db));
    reminders = ReminderRepository(db);
    audit = AuditRepository(db);
  });

  tearDown(() => db.close());

  Future<String> createOwnedVehicle(String ownerId) async {
    final id = await vehicles.createVehicle(brand: 'Renault', model: 'Clio', currentMileage: 1000);
    await (db.update(db.vehicles)..where((v) => v.id.equals(id)))
        .write(VehiclesCompanion(ownerId: Value(ownerId)));
    return id;
  }

  test('a reminder on user A\'s vehicle never appears in user B\'s feed', () async {
    final aVehicle = await createOwnedVehicle('user-A');
    await reminders.upsertForSource(
      vehicleId: aVehicle,
      sourceType: 'document',
      sourceId: 'doc-1',
      title: 'Assurance à renouveler',
      dueDate: DateTime.now().add(const Duration(days: 10)),
    );

    final forA = await reminders.watchAllActive(currentUserId: 'user-A').first;
    final forB = await reminders.watchAllActive(currentUserId: 'user-B').first;

    expect(forA, isNotEmpty);
    expect(forB, isEmpty);
  });

  test('watchAll (all statuses) is scoped the same way as watchAllActive', () async {
    final aVehicle = await createOwnedVehicle('user-A');
    await reminders.upsertForSource(
      vehicleId: aVehicle,
      sourceType: 'document',
      sourceId: 'doc-1',
      title: 'Assurance à renouveler',
      dueDate: DateTime.now().add(const Duration(days: 10)),
    );

    final forB = await reminders.watchAll(currentUserId: 'user-B').first;

    expect(forB, isEmpty);
  });

  test('an audit event on user A\'s vehicle never appears in user B\'s feed', () async {
    final aVehicle = await createOwnedVehicle('user-A');
    await audit.log(
      vehicleId: aVehicle,
      entityType: 'vehicle',
      entityId: aVehicle,
      action: 'created',
      summary: 'Véhicule créé',
    );

    final forA = await audit.watchAll(currentUserId: 'user-A').first;
    final forB = await audit.watchAll(currentUserId: 'user-B').first;

    expect(forA, isNotEmpty);
    expect(forB, isEmpty);
  });

  test('an audit event with no vehicleId at all is always visible, account or not', () async {
    await audit.log(entityType: 'account', action: 'created', summary: 'Compte créé');

    final forA = await audit.watchAll(currentUserId: 'user-A').first;
    final unfiltered = await audit.watchAll().first;

    expect(forA, isNotEmpty);
    expect(unfiltered, isNotEmpty);
  });
}
