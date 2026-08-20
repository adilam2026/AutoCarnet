import 'package:autocarnet/core/database/database.dart';
import 'package:autocarnet/features/audit/data/audit_repository.dart';
import 'package:autocarnet/features/reminders/data/reminder_repository.dart';
import 'package:autocarnet/features/vehicles/data/vehicle_repository.dart';
import 'package:drift/drift.dart' hide isNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

/// Regression coverage for a real anomaly found during the session/logout
/// audit: watchAll() never filtered by account at all, so if two
/// different Supabase accounts ever used the same physical device, the
/// second account's vehicle list would show the first account's vehicles
/// mixed in - a real data leak, not filtered anywhere, client or server
/// (RLS only ever protected the *cloud* copy, never this device's local
/// cache). Nothing here is ever deleted - see handleAccountSwitch.
void main() {
  late AppDatabase db;
  late VehicleRepository repo;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    repo = VehicleRepository(db, AuditRepository(db), ReminderRepository(db));
  });

  tearDown(() => db.close());

  Future<String> createOwned(String ownerId, {String brand = 'Renault'}) async {
    final id = await repo.createVehicle(brand: brand, model: 'Clio', currentMileage: 10000);
    await (db.update(db.vehicles)..where((v) => v.id.equals(id)))
        .write(VehiclesCompanion(ownerId: Value(ownerId)));
    return id;
  }

  test('a vehicle never synced (ownerId null) is visible to any signed-in account', () async {
    final id = await repo.createVehicle(brand: 'Peugeot', model: '208', currentMileage: 5000);

    final forA = await repo.watchAll(currentUserId: 'user-A').first;
    final forB = await repo.watchAll(currentUserId: 'user-B').first;

    expect(forA.map((v) => v.id), contains(id));
    expect(forB.map((v) => v.id), contains(id));
  });

  test('user B never sees a vehicle owned by user A, and vice versa', () async {
    final aId = await createOwned('user-A', brand: 'Audi');
    final bId = await createOwned('user-B', brand: 'BMW');

    final forA = await repo.watchAll(currentUserId: 'user-A').first;
    final forB = await repo.watchAll(currentUserId: 'user-B').first;

    expect(forA.map((v) => v.id), contains(aId));
    expect(forA.map((v) => v.id), isNot(contains(bId)));
    expect(forB.map((v) => v.id), contains(bId));
    expect(forB.map((v) => v.id), isNot(contains(aId)));
  });

  test('with no signed-in account at all (offline-only device), every local vehicle is visible',
      () async {
    final aId = await createOwned('user-A');
    final unsyncedId =
        await repo.createVehicle(brand: 'Fiat', model: 'Panda', currentMileage: 1000);

    final unfiltered = await repo.watchAll().first;

    expect(unfiltered.map((v) => v.id), containsAll([aId, unsyncedId]));
  });

  test(
      'handleAccountSwitch tags only null-owner vehicles, never touches already-owned ones',
      () async {
    final ownedByA = await createOwned('user-A');
    final unsyncedId =
        await repo.createVehicle(brand: 'Dacia', model: 'Duster', currentMileage: 2000);

    await repo.handleAccountSwitch('user-A');

    final ownedRow = await repo.getOne(ownedByA);
    final reattributed = await repo.getOne(unsyncedId);
    expect(ownedRow.ownerId, 'user-A');
    expect(reattributed.ownerId, 'user-A');
  });

  test(
      'the account-switch scenario end to end: an unsynced vehicle created while account A was '
      'using the device is reattributed to A and disappears from B\'s list, without being deleted',
      () async {
    final unsyncedId =
        await repo.createVehicle(brand: 'Toyota', model: 'Yaris', currentMileage: 3000);

    // Simulates AppGate._onAccountAuthenticated detecting that a
    // *different* account (B) just signed in on a device last used by A.
    await repo.handleAccountSwitch('user-A');

    final forB = await repo.watchAll(currentUserId: 'user-B').first;
    final forA = await repo.watchAll(currentUserId: 'user-A').first;

    expect(forB.map((v) => v.id), isNot(contains(unsyncedId)));
    expect(forA.map((v) => v.id), contains(unsyncedId));
    // Never deleted - still readable directly.
    expect((await repo.getOne(unsyncedId)).id, unsyncedId);
  });

  test(
      'a vehicle shared with the current account (owned by someone else, myRole cached) is '
      'still visible - the owner filter alone must never hide legitimately shared vehicles',
      () async {
    final sharedId = await createOwned('owner-X');
    await (db.update(db.vehicles)..where((v) => v.id.equals(sharedId)))
        .write(const VehiclesCompanion(myRole: Value('editor')));

    final forB = await repo.watchAll(currentUserId: 'user-B').first;

    expect(forB.map((v) => v.id), contains(sharedId));
  });

  test(
      'handleAccountSwitch clears every cached myRole - it belongs to the previous account\'s '
      'memberships, never the new one\'s, until the next sync repopulates it', () async {
    final sharedWithA = await createOwned('owner-X');
    await (db.update(db.vehicles)..where((v) => v.id.equals(sharedWithA)))
        .write(const VehiclesCompanion(myRole: Value('viewer')));

    await repo.handleAccountSwitch('user-A');

    final forB = await repo.watchAll(currentUserId: 'user-B').first;
    expect(forB.map((v) => v.id), isNot(contains(sharedWithA)));
    expect((await repo.getOne(sharedWithA)).myRole, isNull);
  });
}
