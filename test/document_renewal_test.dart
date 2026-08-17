import 'package:autocarnet/core/database/database.dart';
import 'package:autocarnet/features/audit/data/audit_repository.dart';
import 'package:autocarnet/features/documents/data/document_repository.dart';
import 'package:autocarnet/features/documents/domain/document_renewal_rules.dart';
import 'package:autocarnet/features/reminders/data/reminder_repository.dart';
import 'package:autocarnet/features/timeline/data/timeline_repository.dart';
import 'package:autocarnet/features/vehicles/data/vehicle_repository.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('document_renewal_rules (pure)', () {
    test('assurance defaults to 12 months', () {
      expect(defaultRenewalMonths('Assurance'), 12);
    });

    test('visite technique defaults to 12 months', () {
      expect(defaultRenewalMonths('Visite technique'), 12);
    });

    test('a document type without a default rule returns null', () {
      expect(defaultRenewalMonths('Carte grise'), isNull);
    });

    test('TEST 23: assurance début 10/09/2026 -> expiration suggérée '
        '10/09/2027', () {
      final start = DateTime(2026, 9, 10);
      final months = defaultRenewalMonths('Assurance')!;
      final suggested =
          DateTime(start.year, start.month + months, start.day);
      expect(suggested, DateTime(2027, 9, 10));
    });

    test('TEST 24: visite technique 12/05/2026 -> prochaine suggérée '
        '12/05/2027', () {
      final visit = DateTime(2026, 5, 12);
      final months = defaultRenewalMonths('Visite technique')!;
      final suggested =
          DateTime(visit.year, visit.month + months, visit.day);
      expect(suggested, DateTime(2027, 5, 12));
    });

    test('vignette is civil-year bound, never a fixed 12-month interval',
        () {
      expect(isCivilYearBound('Vignette'), isTrue);
      expect(defaultRenewalMonths('Vignette'), isNull);
    });

    test(
        'TEST 25: vignette payée en cours d\'année reste due au 1er janvier '
        'de l\'année suivante, jamais "date de paiement + 12 mois"', () {
      expect(civilYearDueDate(DateTime(2026, 8, 16)), DateTime(2027, 1, 1));
      // Paid in January still lands on the *following* civil year - a
      // fixed +12-months rule would wrongly land in the same month.
      expect(civilYearDueDate(DateTime(2026, 1, 5)), DateTime(2027, 1, 1));
    });
  });

  group('DocumentRepository - échéances assurance/visite/vignette', () {
    late AppDatabase db;
    late DocumentRepository documents;
    late ReminderRepository reminders;
    late String vehicleId;

    setUp(() async {
      db = AppDatabase(NativeDatabase.memory());
      final audit = AuditRepository(db);
      final timeline = TimelineRepository(db);
      reminders = ReminderRepository(db);
      final vehicles = VehicleRepository(db, audit, reminders);
      documents = DocumentRepository(db, timeline, reminders);
      vehicleId = await vehicles.createVehicle(
        brand: 'Renault',
        model: 'Clio',
        currentMileage: 50000,
      );
    });

    tearDown(() => db.close());

    test('TEST 23: an assurance renewal reminder lands on start + 12 months',
        () async {
      final start = DateTime(2026, 9, 10);
      await documents.createDocument(
        vehicleId: vehicleId,
        type: 'Assurance',
        issueDate: start,
        expiryDate: DateTime(start.year + 1, start.month, start.day),
      );
      final active = await reminders.watchActiveForVehicle(vehicleId).first;
      expect(active, hasLength(1));
      expect(active.first.dueDate, DateTime(2027, 9, 10));
      expect(active.first.title, 'Assurance à renouveler');
    });

    test(
        'TEST 25: paying the vignette creates a reminder for the next civil '
        'year, worded "Vignette YYYY à payer"', () async {
      final paidOn = DateTime(2026, 3, 1);
      final due = civilYearDueDate(paidOn);
      await documents.createDocument(
        vehicleId: vehicleId,
        type: 'Vignette',
        issueDate: paidOn,
        expiryDate: due,
      );
      final active = await reminders.watchActiveForVehicle(vehicleId).first;
      expect(active, hasLength(1));
      expect(active.first.title, 'Vignette 2027 à payer');
      expect(active.first.dueDate, DateTime(2027, 1, 1));
    });

    test(
        'renewing the vignette for the following year keeps last year\'s '
        'version in history and replaces the reminder - never stacking two',
        () async {
      final firstPaid = DateTime(2026, 3, 1);
      final docId = await documents.createDocument(
        vehicleId: vehicleId,
        type: 'Vignette',
        issueDate: firstPaid,
        expiryDate: civilYearDueDate(firstPaid),
      );
      final secondPaid = DateTime(2027, 1, 10);
      await documents.renewDocument(
        documentId: docId,
        issueDate: secondPaid,
        expiryDate: civilYearDueDate(secondPaid),
      );

      final active = await reminders.watchActiveForVehicle(vehicleId).first;
      expect(active, hasLength(1));
      expect(active.first.title, 'Vignette 2028 à payer');

      final all = await reminders.watchAll().first;
      expect(all.where((r) => r.status == ReminderStatus.dismissed),
          hasLength(1));

      final doc = await documents.getById(docId);
      expect(doc!.version!.issueDate, secondPaid);
    });
  });
}
