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

    test('permis de conduire defaults to 120 months (10 years)', () {
      expect(defaultRenewalMonths('Permis de conduire'), 120);
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

    test('permis de conduire délivré le 01/03/2020 -> expire le '
        '01/03/2030 (10 ans)', () {
      final issued = DateTime(2020, 3, 1);
      final months = defaultRenewalMonths('Permis de conduire')!;
      final suggested =
          DateTime(issued.year, issued.month + months, issued.day);
      expect(suggested, DateTime(2030, 3, 1));
    });

    test('vignette is civil-year bound, never a fixed 12-month interval',
        () {
      expect(isCivilYearBound('Vignette'), isTrue);
      expect(defaultRenewalMonths('Vignette'), isNull);
    });

    test(
        'TEST 25: la vignette de l\'année Y échoit (au sens des rappels) au '
        '31 janvier Y+1, jamais "date de paiement + 12 mois" - le délai de '
        'grâce accordé par l\'État est intégré à l\'échéance elle-même', () {
      expect(civilYearDueDate(2026), DateTime(2027, 1, 31));
      // Peu importe le mois où elle a été payée dans l'année, seule
      // l'année civile choisie compte.
      expect(civilYearDueDate(2025), DateTime(2026, 1, 31));
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
        'TEST 25: buying the vignette for a civil year creates a reminder '
        'due 31/01 of the following year, worded "Vignette YYYY à payer"',
        () async {
      const vignetteYear = 2026;
      final due = civilYearDueDate(vignetteYear);
      await documents.createDocument(
        vehicleId: vehicleId,
        type: 'Vignette',
        issueDate: DateTime(vignetteYear, 1, 1),
        expiryDate: due,
      );
      final active = await reminders.watchActiveForVehicle(vehicleId).first;
      expect(active, hasLength(1));
      expect(active.first.title, 'Vignette 2026 à payer');
      expect(active.first.dueDate, DateTime(2027, 1, 31));
    });

    test(
        'renewing the vignette for the following year keeps last year\'s '
        'version in history and replaces the reminder - never stacking two',
        () async {
      const firstYear = 2026;
      final docId = await documents.createDocument(
        vehicleId: vehicleId,
        type: 'Vignette',
        issueDate: DateTime(firstYear, 1, 1),
        expiryDate: civilYearDueDate(firstYear),
      );
      const secondYear = 2027;
      await documents.renewDocument(
        documentId: docId,
        issueDate: DateTime(secondYear, 1, 1),
        expiryDate: civilYearDueDate(secondYear),
      );

      final active = await reminders.watchActiveForVehicle(vehicleId).first;
      expect(active, hasLength(1));
      expect(active.first.title, 'Vignette 2027 à payer');

      final all = await reminders.watchAll().first;
      expect(all.where((r) => r.status == ReminderStatus.dismissed),
          hasLength(1));

      final doc = await documents.getById(docId);
      expect(doc!.version!.issueDate, DateTime(secondYear, 1, 1));
    });
  });
}
