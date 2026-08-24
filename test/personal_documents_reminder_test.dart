import 'package:autocarnet/core/database/database.dart';
import 'package:autocarnet/features/audit/data/audit_repository.dart';
import 'package:autocarnet/features/documents/data/document_repository.dart';
import 'package:autocarnet/features/reminders/data/reminder_repository.dart';
import 'package:autocarnet/features/timeline/data/timeline_repository.dart';
import 'package:autocarnet/features/vehicles/data/vehicle_repository.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

/// Mission 2026: le permis de conduire appartient au profil, pas à un
/// véhicule - renseigné une seule fois, il doit rester valable (et son
/// alerte d'expiration ne doit remonter qu'une seule fois) quel que soit le
/// nombre de véhicules du garage.
void main() {
  late AppDatabase db;
  late VehicleRepository vehicles;
  late DocumentRepository documents;
  late ReminderRepository reminders;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    final audit = AuditRepository(db);
    final reminderRepo = ReminderRepository(db);
    vehicles = VehicleRepository(db, audit, reminderRepo);
    final timeline = TimelineRepository(db);
    documents = DocumentRepository(db, timeline, reminderRepo);
    reminders = reminderRepo;
  });

  tearDown(() => db.close());

  test(
      'a driver document (permis de conduire) with an expiry date creates exactly one '
      'reminder, with no vehicleId at all', () async {
    await documents.createDocument(
      vehicleId: null,
      type: 'Permis de conduire',
      expiryDate: DateTime.now().add(const Duration(days: 30)),
      currentUserId: 'adil',
    );

    final all = await reminders.watchAll(currentUserId: 'adil').first;
    expect(all.length, 1);
    expect(all.single.vehicleId, isNull);
    expect(all.single.title, contains('Permis de conduire'));
  });

  test(
      'Adil (Audi Q5, Volkswagen Tiguan, Opel Astra) sets his permis once - the alert '
      'appears exactly once, never once per vehicle', () async {
    await vehicles.createVehicle(brand: 'Audi', model: 'Q5', currentMileage: 40000);
    await vehicles.createVehicle(brand: 'Volkswagen', model: 'Tiguan', currentMileage: 60000);
    await vehicles.createVehicle(brand: 'Opel', model: 'Astra', currentMileage: 120000);

    await documents.createDocument(
      vehicleId: null,
      type: 'Permis de conduire',
      expiryDate: DateTime.now().add(const Duration(days: 30)),
      currentUserId: 'adil',
    );

    final active = await reminders.watchAllActive(currentUserId: 'adil').first;
    final permisReminders =
        active.where((r) => r.title.contains('Permis de conduire')).toList();
    expect(permisReminders, hasLength(1),
        reason: 'one alert regardless of how many vehicles Adil owns');
  });

  test('the personal permis reminder never leaks into a different account\'s feed', () async {
    await documents.createDocument(
      vehicleId: null,
      type: 'Permis de conduire',
      expiryDate: DateTime.now().add(const Duration(days: 30)),
      currentUserId: 'user-A',
    );

    final forA = await reminders.watchAllActive(currentUserId: 'user-A').first;
    final forB = await reminders.watchAllActive(currentUserId: 'user-B').first;

    expect(forA, isNotEmpty);
    expect(forB, isEmpty);
  });

  test('renewing the permis supersedes the old reminder instead of duplicating it', () async {
    final docId = await documents.createDocument(
      vehicleId: null,
      type: 'Permis de conduire',
      expiryDate: DateTime.now().add(const Duration(days: 10)),
      currentUserId: 'adil',
    );

    await documents.renewDocument(
      documentId: docId,
      expiryDate: DateTime.now().add(const Duration(days: 365 * 10)),
      currentUserId: 'adil',
    );

    final active = await reminders.watchAllActive(currentUserId: 'adil').first;
    final permisReminders =
        active.where((r) => r.title.contains('Permis de conduire')).toList();
    expect(permisReminders, hasLength(1));
    expect(permisReminders.single.dueDate!.isAfter(DateTime.now().add(const Duration(days: 300))),
        isTrue);
  });

  test('a driver document with no expiry date creates no reminder at all', () async {
    await documents.createDocument(
      vehicleId: null,
      type: 'Pièce d\'identité',
      currentUserId: 'adil',
    );

    final all = await reminders.watchAll(currentUserId: 'adil').first;
    expect(all, isEmpty);
  });

  test('driverDocumentsProvider-style query: watchDriverDocuments returns the permis '
      'regardless of which vehicle (if any) is selected, and a vehicle-scoped document '
      'never appears in it', () async {
    final vehicleId = await vehicles.createVehicle(brand: 'Audi', model: 'Q5', currentMileage: 1000);
    await documents.createDocument(
      vehicleId: vehicleId,
      type: 'Assurance',
      expiryDate: DateTime.now().add(const Duration(days: 60)),
      currentUserId: 'adil',
    );
    await documents.createDocument(
      vehicleId: null,
      type: 'Permis de conduire',
      expiryDate: DateTime.now().add(const Duration(days: 30)),
      currentUserId: 'adil',
    );

    final driverDocs = await documents.watchDriverDocuments(currentUserId: 'adil').first;
    expect(driverDocs, hasLength(1));
    expect(driverDocs.single.document.type, 'Permis de conduire');

    final vehicleDocs = await documents.watchForVehicle(vehicleId).first;
    expect(vehicleDocs, hasLength(1));
    expect(vehicleDocs.single.document.type, 'Assurance');
  });
}
