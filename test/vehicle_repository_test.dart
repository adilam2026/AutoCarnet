import 'package:autocarnet/core/database/database.dart';
import 'package:autocarnet/core/utils/mileage_result.dart';
import 'package:autocarnet/features/audit/data/audit_repository.dart';
import 'package:autocarnet/features/reminders/data/reminder_repository.dart';
import 'package:autocarnet/features/vehicles/data/vehicle_repository.dart';
import 'package:drift/drift.dart' hide isNull;
import 'package:drift/native.dart';
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
}
