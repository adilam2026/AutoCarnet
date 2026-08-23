import 'package:autocarnet/core/database/database.dart';
import 'package:autocarnet/core/utils/id_generator.dart';
import 'package:autocarnet/core/utils/mileage_result.dart';
import 'package:autocarnet/features/audit/data/audit_repository.dart';
import 'package:autocarnet/features/reminders/data/reminder_repository.dart';
import 'package:autocarnet/features/vehicles/data/vehicle_repository.dart';
import 'package:autocarnet/features/vehicles/domain/vehicle_card_color.dart';
import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late AppDatabase db;
  late VehicleRepository repo;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    repo = VehicleRepository(db, AuditRepository(db), ReminderRepository(db));
  });

  tearDown(() => db.close());

  test('quick creation only requires brand, model and mileage', () async {
    final id = await repo.createVehicle(
      brand: 'Renault',
      model: 'Clio',
      currentMileage: 50000,
    );
    final vehicle = await repo.getOne(id);
    expect(vehicle.brand, 'Renault');
    expect(vehicle.currentMileage, 50000);
  });

  test('raising the mileage is always OK (RG-VEH-005)', () async {
    final id = await repo.createVehicle(
      brand: 'Renault',
      model: 'Clio',
      currentMileage: 50000,
    );
    final result = await repo.checkMileageChange(id, 51000);
    expect(result, isA<MileageOk>());
  });

  test(
      'lowering the mileage with no conflicting operation only needs '
      'confirmation (Situation A)', () async {
    final id = await repo.createVehicle(
      brand: 'Renault',
      model: 'Clio',
      currentMileage: 50000,
    );
    final result = await repo.checkMileageChange(id, 49000);
    expect(result, isA<MileageNeedsConfirmation>());
  });

  test(
      'lowering the mileage below a recorded operation is blocked '
      '(Situation B)', () async {
    final id = await repo.createVehicle(
      brand: 'Renault',
      model: 'Clio',
      currentMileage: 82000,
    );
    // Vidange recorded at 82 000 km, freins at 80 000 km.
    await repo.recordOperationMileage(
      vehicleId: id,
      value: 82000,
      source: 'maintenance',
      sourceId: 'vidange-1',
    );
    await repo.recordOperationMileage(
      vehicleId: id,
      value: 80000,
      source: 'maintenance',
      sourceId: 'freins-1',
    );

    final result = await repo.checkMileageChange(id, 70000);
    expect(result, isA<MileageBlocked>());
    expect((result as MileageBlocked).conflictingDescriptions, hasLength(2));
  });

  test('confirmed mileage update creates a new history entry, never '
      'overwrites (RG-VEH-006/007)', () async {
    final id = await repo.createVehicle(
      brand: 'Renault',
      model: 'Clio',
      currentMileage: 50000,
    );
    await repo.recordManualMileage(id, 49500);
    final history = await repo.watchMileageHistory(id).first;
    expect(history.length, 2);
    final vehicle = await repo.getOne(id);
    expect(vehicle.currentMileage, 49500);
  });

  test(
      'firstRegistrationDate is the single source of truth for year: '
      'persisting a precise MEC date keeps its own day/month/year exactly, '
      'and the derived year survives a fresh read (Date MEC checklist)',
      () async {
    final id = await repo.createVehicle(
      brand: 'Audi',
      model: 'Q5',
      currentMileage: 89400,
    );
    final v = await repo.getOne(id);
    final mec = DateTime(2021, 12, 22);
    await repo.updateVehicle(v.copyWith(
      year: Value(mec.year),
      firstRegistrationDate: Value(mec),
      firstRegistrationDatePrecision: const Value(null),
    ));

    final reloaded = await repo.getOne(id);
    expect(reloaded.firstRegistrationDate, mec);
    expect(reloaded.firstRegistrationDate!.day, 22);
    expect(reloaded.firstRegistrationDate!.month, 12);
    expect(reloaded.year, 2021);
    expect(reloaded.firstRegistrationDatePrecision, isNull);
  });

  test('a sold vehicle no longer needs future reminders (RG-ALR-007)',
      () async {
    final id = await repo.createVehicle(
      brand: 'Renault',
      model: 'Clio',
      currentMileage: 50000,
    );
    final reminders = ReminderRepository(db);
    await reminders.upsertForSource(
      vehicleId: id,
      sourceType: 'document',
      sourceId: 'doc-1',
      title: 'Assurance à renouveler',
      dueDate: DateTime.now().add(const Duration(days: 10)),
    );
    await repo.setStatus(id, VehicleStatus.sold);
    final active = await reminders.watchActiveForVehicle(id).first;
    expect(active, isEmpty);
  });

  test('deleting a vehicle removes it from the list without a hard SQL '
      'delete, and stops its reminders', () async {
    final id = await repo.createVehicle(
      brand: 'Renault',
      model: 'Clio',
      currentMileage: 50000,
    );
    final reminders = ReminderRepository(db);
    await reminders.upsertForSource(
      vehicleId: id,
      sourceType: 'document',
      sourceId: 'doc-1',
      title: 'Assurance à renouveler',
      dueDate: DateTime.now().add(const Duration(days: 10)),
    );

    await repo.softDelete(id);

    final all = await repo.watchAll().first;
    expect(all.where((v) => v.id == id), isEmpty);
    // Still readable directly by id - a soft delete, not a hard one.
    final stillThere = await repo.getOne(id);
    expect(stillThere.isDeleted, isTrue);
    final active = await reminders.watchActiveForVehicle(id).first;
    expect(active, isEmpty);
  });

  test('existsLocally is true once created, false for an id never pulled/created here', () async {
    final id = await repo.createVehicle(
      brand: 'Renault',
      model: 'Clio',
      currentMileage: 50000,
    );
    expect(await repo.existsLocally(id), isTrue);
    expect(await repo.existsLocally('never-synced-id'), isFalse);
  });

  test(
      'watchOne emits null (not a crash) for an id that does not exist '
      'locally yet - regression for the "Rejoindre un véhicule" crash '
      '(Drift\'s watchSingle() throwing StateError("Expected exactly one '
      'element, but got 0") the instant a share invite is accepted but the '
      'vehicle has not reached the local mirror yet), then emits the row '
      'once it is inserted, without ever throwing', () async {
    final emissions = <Vehicle?>[];
    final sub = repo.watchOne('not-synced-yet-id').listen(emissions.add);
    await Future<void>.delayed(Duration.zero);
    expect(emissions, everyElement(isNull));
    expect(emissions, isNotEmpty);

    final id = await repo.createVehicle(
      brand: 'Peugeot',
      model: '308',
      currentMileage: 12000,
    );
    // Drift re-runs a table-level watch on any write to that table, even
    // an unrelated row - watchOne('not-synced-yet-id') must keep emitting
    // null for that unrelated insert, and never throw.
    await Future<void>.delayed(Duration.zero);
    expect(emissions, everyElement(isNull));
    await sub.cancel();

    final sub2 = repo.watchOne(id).listen(emissions.add);
    await Future<void>.delayed(Duration.zero);
    expect(emissions.last, isA<Vehicle>());
    expect(emissions.last!.id, id);
    await sub2.cancel();
  });

  group('VehicleCardColor.nextFor (pure)', () {
    test('an empty garage always starts with the first palette colour', () {
      expect(VehicleCardColor.nextFor(const []), VehicleCardColor.bluePetrole);
    });

    test('each new vehicle gets a colour not yet used, as long as the palette allows it', () {
      final used = <String?>[];
      for (final expected in VehicleCardColor.values) {
        final next = VehicleCardColor.nextFor(used);
        expect(next, expected);
        used.add(next.storageKey);
      }
    });

    test('once every colour has been used once, assignment starts repeating from the top', () {
      final allUsedOnce = VehicleCardColor.values.map((c) => c.storageKey).toList();
      expect(VehicleCardColor.nextFor(allUsedOnce), VehicleCardColor.bluePetrole);
    });

    test('null and unrecognised keys are ignored, never counted as a used colour', () {
      expect(
        VehicleCardColor.nextFor([null, 'not-a-real-color', null]),
        VehicleCardColor.bluePetrole,
      );
    });
  });

  test('createVehicle auto-assigns a card colour, distinct from the paint colour field', () async {
    final id = await repo.createVehicle(brand: 'Renault', model: 'Clio', currentMileage: 50000);
    final vehicle = await repo.getOne(id);
    expect(vehicle.cardColorKey, isNotNull);
    expect(VehicleCardColor.fromKeyOrNull(vehicle.cardColorKey), isNotNull);
  });

  test('successive vehicles get visibly distinct card colours (least-used-first)', () async {
    final q5Id = await repo.createVehicle(brand: 'Audi', model: 'Q5', currentMileage: 86750);
    final astraId = await repo.createVehicle(brand: 'Opel', model: 'Astra', currentMileage: 270000);
    final q5 = await repo.getOne(q5Id);
    final astra = await repo.getOne(astraId);
    expect(q5.cardColorKey, isNot(astra.cardColorKey));
  });

  test('updateVehicleCardColor persists a manual choice and allows two vehicles to share it',
      () async {
    final q5Id = await repo.createVehicle(brand: 'Audi', model: 'Q5', currentMileage: 86750);
    final astraId = await repo.createVehicle(brand: 'Opel', model: 'Astra', currentMileage: 270000);
    await repo.updateVehicleCardColor(q5Id, VehicleCardColor.blueNuit);
    await repo.updateVehicleCardColor(astraId, VehicleCardColor.blueNuit);
    final q5 = await repo.getOne(q5Id);
    final astra = await repo.getOne(astraId);
    expect(q5.cardColorKey, VehicleCardColor.blueNuit.storageKey);
    expect(astra.cardColorKey, VehicleCardColor.blueNuit.storageKey);
  });

  group('backfillMissingCardColors', () {
    test('is a no-op once every vehicle already has a colour', () async {
      final id = await repo.createVehicle(brand: 'Renault', model: 'Clio', currentMileage: 50000);
      final before = await repo.getOne(id);
      await repo.backfillMissingCardColors();
      final after = await repo.getOne(id);
      expect(after.cardColorKey, before.cardColorKey);
    });

    test('assigns a colour to a vehicle created before this feature existed, '
        'touching no other field', () async {
      final id = newId();
      final now = DateTime.now();
      await db.into(db.vehicles).insert(VehiclesCompanion.insert(
            id: id,
            brand: 'Renault',
            model: 'Clio',
            currentMileage: 120000,
            createdAt: now,
            updatedAt: now,
          ));
      var vehicle = await repo.getOne(id);
      expect(vehicle.cardColorKey, isNull);

      await repo.backfillMissingCardColors();

      vehicle = await repo.getOne(id);
      expect(vehicle.cardColorKey, isNotNull);
      expect(vehicle.brand, 'Renault');
      expect(vehicle.currentMileage, 120000);
    });

    test('backfilled vehicles get distinct colours from each other, oldest first', () async {
      final olderId = newId();
      final newerId = newId();
      final older = DateTime(2020);
      final newer = DateTime(2021);
      await db.into(db.vehicles).insert(VehiclesCompanion.insert(
            id: olderId,
            brand: 'Opel',
            model: 'Astra',
            currentMileage: 270000,
            createdAt: older,
            updatedAt: older,
          ));
      await db.into(db.vehicles).insert(VehiclesCompanion.insert(
            id: newerId,
            brand: 'Audi',
            model: 'Q5',
            currentMileage: 86750,
            createdAt: newer,
            updatedAt: newer,
          ));

      await repo.backfillMissingCardColors();

      final olderVehicle = await repo.getOne(olderId);
      final newerVehicle = await repo.getOne(newerId);
      expect(olderVehicle.cardColorKey, VehicleCardColor.bluePetrole.storageKey);
      expect(newerVehicle.cardColorKey, VehicleCardColor.blueNuit.storageKey);
    });
  });

  group('VehicleCardColor contrast (pure)', () {
    test('every palette entry\'s onColor contrasts clearly with its own background', () {
      for (final c in VehicleCardColor.values) {
        final bgLuminance = c.color.computeLuminance();
        final fgLuminance = c.onColor.computeLuminance();
        expect((bgLuminance - fgLuminance).abs(), greaterThan(0.3),
            reason: '${c.name}: onColor must contrast clearly with its own background');
      }
    });

    test('contrastingOnColor picks dark ink on a light background, white on a dark one', () {
      expect(contrastingOnColor(Colors.white), isNot(Colors.white));
      expect(contrastingOnColor(Colors.white).computeLuminance(), lessThan(0.1));
      expect(contrastingOnColor(const Color(0xFF0B0B0B)), Colors.white);
    });

    test('safeAccentOnLightSurface darkens a colour too light to read on a white card, '
        'leaves an already-dark one untouched', () {
      final darkened = safeAccentOnLightSurface(Colors.white);
      expect(darkened, isNot(Colors.white));
      expect(darkened.computeLuminance(), lessThan(0.5));

      const dark = Color(0xFF123B54);
      expect(safeAccentOnLightSurface(dark), dark);
    });

    test('every current palette entry already reads fine on a light surface (no-op today)', () {
      for (final c in VehicleCardColor.values) {
        expect(c.onLightSurface, c.color,
            reason: '${c.name} should not need darkening with the current palette');
      }
    });
  });
}
