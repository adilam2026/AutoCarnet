import 'package:autocarnet/core/database/database.dart';
import 'package:autocarnet/features/vehicles/domain/vehicle_ownership.dart';
import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('isVehicleOwnedByCurrentUser', () {
    late AppDatabase db;
    setUp(() => db = AppDatabase(NativeDatabase.memory()));
    tearDown(() => db.close());

    Future<Vehicle> insertVehicle(String? ownerId, {String? myRole}) async {
      final now = DateTime.now();
      const id = 'veh-1';
      await db.into(db.vehicles).insert(
            VehiclesCompanion.insert(
              id: id,
              brand: 'Renault',
              model: 'Clio',
              currentMileage: 1000,
              createdAt: now,
              updatedAt: now,
              ownerId: Value(ownerId),
              myRole: Value(myRole),
            ),
          );
      return (db.select(db.vehicles)..where((v) => v.id.equals(id))).getSingle();
    }

    test('a never-synced local vehicle (ownerId null) is always owned, even signed out', () async {
      final v = await insertVehicle(null);
      expect(isVehicleOwnedByCurrentUser(v, null), isTrue);
      expect(isVehicleOwnedByCurrentUser(v, 'someone-else'), isTrue);
    });

    test('a synced vehicle is owned only when its ownerId matches the signed-in account', () async {
      final v = await insertVehicle('owner-uuid');
      expect(isVehicleOwnedByCurrentUser(v, 'owner-uuid'), isTrue);
      expect(isVehicleOwnedByCurrentUser(v, 'someone-else'), isFalse);
      expect(isVehicleOwnedByCurrentUser(v, null), isFalse);
    });
  });

  group('canEditVehicle', () {
    late AppDatabase db;
    setUp(() => db = AppDatabase(NativeDatabase.memory()));
    tearDown(() => db.close());

    Future<Vehicle> insertVehicle(String? ownerId, {String? myRole}) async {
      final now = DateTime.now();
      const id = 'veh-2';
      await db.into(db.vehicles).insert(
            VehiclesCompanion.insert(
              id: id,
              brand: 'Peugeot',
              model: '208',
              currentMileage: 1000,
              createdAt: now,
              updatedAt: now,
              ownerId: Value(ownerId),
              myRole: Value(myRole),
            ),
          );
      return (db.select(db.vehicles)..where((v) => v.id.equals(id))).getSingle();
    }

    test('the owner can always edit their own vehicle', () async {
      final v = await insertVehicle('owner-uuid');
      expect(canEditVehicle(v, 'owner-uuid'), isTrue);
    });

    test('a never-synced local vehicle is always editable', () async {
      final v = await insertVehicle(null);
      expect(canEditVehicle(v, 'anyone'), isTrue);
    });

    test('an editor collaborator can edit a shared vehicle', () async {
      final v = await insertVehicle('owner-uuid', myRole: 'editor');
      expect(canEditVehicle(v, 'collaborator-uuid'), isTrue);
    });

    test('a viewer collaborator can never edit a shared vehicle - RLS would '
        'reject it anyway, but the UI must never let a local edit silently '
        'orphan itself from sync', () async {
      final v = await insertVehicle('owner-uuid', myRole: 'viewer');
      expect(canEditVehicle(v, 'collaborator-uuid'), isFalse);
    });
  });
}
