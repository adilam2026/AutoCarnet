import 'package:autocarnet/core/database/database.dart';
import 'package:autocarnet/features/audit/data/audit_repository.dart';
import 'package:autocarnet/features/maintenance/data/maintenance_repository.dart';
import 'package:autocarnet/features/maintenance/domain/operation_recurrence_rules.dart';
import 'package:autocarnet/features/reminders/data/reminder_repository.dart';
import 'package:autocarnet/features/timeline/data/timeline_repository.dart';
import 'package:autocarnet/features/vehicles/data/vehicle_repository.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

/// "NOUVELLES CORRECTIONS IMPORTANTES" - une opération plus ancienne
/// ajoutée après coup ne doit jamais devenir la référence pour calculer la
/// prochaine échéance : seuls le kilométrage et la date réels de
/// l'opération comptent, jamais l'ordre de saisie ni createdAt.
void main() {
  late AppDatabase db;
  late ReminderRepository reminders;
  late VehicleRepository vehicles;
  late MaintenanceRepository maintenance;
  late TimelineRepository timeline;
  late String vehicleId;

  const category = 'Vidange + filtres';
  final frequencyKm = resolveFrequency(category: category).frequencyKm!;

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    final audit = AuditRepository(db);
    timeline = TimelineRepository(db);
    reminders = ReminderRepository(db);
    vehicles = VehicleRepository(db, audit, reminders);
    maintenance = MaintenanceRepository(db, timeline, reminders, vehicles);

    vehicleId = await vehicles.createVehicle(
      brand: 'Audi',
      model: 'Q5',
      currentMileage: 89400,
    );
  });

  tearDown(() => db.close());

  Future<String> addVidange(double mileage, DateTime date) {
    return maintenance.createEntry(
      vehicleId: vehicleId,
      category: category,
      date: date,
      mileage: mileage,
      nextDueMileage: mileage + frequencyKm,
    );
  }

  test('TEST A: une vidange plus ancienne ajoutée après coup ne redevient '
      'jamais la référence et ne déclenche aucune fausse alerte "dépassée"',
      () async {
    await addVidange(88700, DateTime(2026, 8, 9));
    await addVidange(78900, DateTime(2025, 10, 16));

    final active = await reminders.watchActiveForVehicle(vehicleId).first;
    expect(active, hasLength(1));
    expect(active.first.dueMileage, 98700);

    const currentMileage = 89400.0;
    expect(active.first.dueMileage! - currentMileage, 9300);

    // The old entry still enriches the historique...
    final entries = await maintenance.watchForVehicle(vehicleId).first;
    expect(entries, hasLength(2));
    // ...but never keeps an active reminder of its own.
    final all = await reminders.watchAll().first;
    final dismissed = all.where((r) => r.status == ReminderStatus.dismissed);
    expect(dismissed, hasLength(1));
    expect(dismissed.first.dueMileage, 88900); // 78900 + 10000
  });

  test('TEST B: création en ordre chronologique mélangé - l\'échéance '
      'converge toujours vers le kilométrage le plus élevé', () async {
    final scrambled = <double, DateTime>{
      88700: DateTime(2026, 8, 9),
      50000: DateTime(2023, 1, 1),
      78900: DateTime(2025, 10, 16),
      65000: DateTime(2024, 3, 1),
    };
    for (final entry in scrambled.entries) {
      await addVidange(entry.key, entry.value);
    }

    final active = await reminders.watchActiveForVehicle(vehicleId).first;
    expect(active, hasLength(1));
    expect(active.first.dueMileage, 98700);

    // The historique still reflects every entry, orderable chronologically
    // by its own date - never by insertion order.
    final entries = await maintenance.watchForVehicle(vehicleId).first;
    expect(entries, hasLength(4));
    final chronological = [...entries]..sort((a, b) => a.date.compareTo(b.date));
    expect(chronological.map((e) => e.mileage).toList(),
        [50000, 65000, 78900, 88700]);
  });

  test('TEST C: corriger le kilométrage de l\'opération de référence '
      'recalcule son échéance', () async {
    final id = await addVidange(88700, DateTime(2026, 8, 9));

    await maintenance.updateEntry(
      id: id,
      vehicleId: vehicleId,
      category: category,
      date: DateTime(2026, 8, 9),
      mileage: 89000,
      nextDueMileage: 89000 + frequencyKm,
    );

    final active = await reminders.watchActiveForVehicle(vehicleId).first;
    expect(active, hasLength(1));
    expect(active.first.dueMileage, 99000);
  });

  test('deleting the reference entry promotes the next-highest mileage '
      'entry of the same category to reference', () async {
    final newer = await addVidange(88700, DateTime(2026, 8, 9));
    await addVidange(78900, DateTime(2025, 10, 16));

    await maintenance.softDelete(newer);

    final active = await reminders.watchActiveForVehicle(vehicleId).first;
    expect(active, hasLength(1));
    expect(active.first.dueMileage, 88900); // 78900 + 10000
  });
}
