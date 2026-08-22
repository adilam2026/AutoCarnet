import 'package:autocarnet/core/database/database.dart';
import 'package:autocarnet/core/sync/document_sync_mapping.dart';
import 'package:autocarnet/core/sync/expense_sync_mapping.dart';
import 'package:autocarnet/core/sync/frequency_pref_sync_mapping.dart';
import 'package:autocarnet/core/sync/fuel_sync_mapping.dart';
import 'package:autocarnet/core/sync/maintenance_sync_mapping.dart';
import 'package:autocarnet/core/sync/mileage_sync_mapping.dart';
import 'package:autocarnet/core/sync/reminder_sync_mapping.dart';
import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('phase 4 sync mappings (pure)', () {
    late AppDatabase db;
    setUp(() => db = AppDatabase(NativeDatabase.memory()));
    tearDown(() => db.close());

    test('maintenance entry + parts round-trip without loss', () async {
      final now = DateTime.utc(2026, 1, 1);
      await db.into(db.vehicles).insert(VehiclesCompanion.insert(
            id: 'v1',
            brand: 'Dacia',
            model: 'Duster',
            currentMileage: 1000,
            createdAt: now,
            updatedAt: now,
          ));
      await db.into(db.maintenanceEntries).insert(MaintenanceEntriesCompanion.insert(
            id: 'm1',
            vehicleId: 'v1',
            category: 'Vidange',
            date: now,
            mileage: 50000,
            createdAt: now,
            updatedAt: now,
            comments: const Value('RAS'),
          ));
      final local =
          await (db.select(db.maintenanceEntries)..where((e) => e.id.equals('m1'))).getSingle();
      final row = maintenanceEntryToRemoteRow(local);
      expect(row['category'], 'Vidange');
      expect(row.containsKey('version'), isFalse);

      final companion = maintenanceEntryFromRemoteRow({
        ...row,
        'version': 3,
        'created_by': 'user-a',
        'updated_by': 'user-b',
      });
      expect(companion.category.value, 'Vidange');
      expect(companion.version.value, 3);
      expect(companion.createdBy.value, 'user-a');
      expect(companion.updatedBy.value, 'user-b');
      expect(companion.syncStatus.value, 'synced');

      await db.into(db.maintenanceParts).insert(MaintenancePartsCompanion.insert(
            id: 'p1',
            maintenanceEntryId: 'm1',
            designation: 'Filtre à huile',
            quantity: const Value(2),
            unitPrice: const Value(45),
          ));
      final part =
          await (db.select(db.maintenanceParts)..where((p) => p.id.equals('p1'))).getSingle();
      final partRow = maintenancePartToRemoteRow(part);
      expect(partRow['designation'], 'Filtre à huile');
      final partCompanion = maintenancePartFromRemoteRow(partRow);
      expect(partCompanion.quantity.value, 2);
      expect(partCompanion.unitPrice.value, 45);
    });

    test('expense round-trips without loss', () async {
      final now = DateTime.utc(2026, 1, 1);
      final row = expenseToRemoteRow(Expense(
        id: 'e1',
        vehicleId: 'v1',
        category: 'Assurance',
        date: now,
        amount: 3200,
        currency: 'MAD',
        providerId: null,
        mileage: null,
        paymentMethod: null,
        comments: null,
        linkedMaintenanceId: null,
        linkedFuelId: null,
        linkedDocumentVersionId: null,
        createdAt: now,
        updatedAt: now,
        isDeleted: false,
        syncStatus: 'pendingSync',
        version: 0,
        createdBy: null,
        updatedBy: null,
      ));
      final companion = expenseFromRemoteRow({...row, 'version': 1, 'created_by': 'u1'});
      expect(companion.amount.value, 3200);
      expect(companion.version.value, 1);
      expect(companion.createdBy.value, 'u1');
    });

    test('fuel entry round-trips without loss', () async {
      final now = DateTime.utc(2026, 1, 1);
      final row = fuelEntryToRemoteRow(FuelEntry(
        id: 'f1',
        vehicleId: 'v1',
        date: now,
        mileage: 51000,
        providerId: null,
        fuelType: 'Essence',
        quantityLiters: 40,
        pricePerLiter: 13.5,
        totalAmount: 540,
        isFullTank: true,
        comments: null,
        linkedExpenseId: null,
        createdAt: now,
        updatedAt: now,
        isDeleted: false,
        syncStatus: 'pendingSync',
        version: 0,
        createdBy: null,
        updatedBy: null,
      ));
      final companion = fuelEntryFromRemoteRow(row);
      expect(companion.quantityLiters.value, 40);
      expect(companion.fuelType.value, 'Essence');
      expect(companion.syncStatus.value, 'synced');
    });

    test('document round-trips, ownerId doubling as created_by', () async {
      final now = DateTime.utc(2026, 1, 1);
      final row = documentToRemoteRow(Document(
        id: 'd1',
        vehicleId: 'v1',
        type: 'Assurance',
        holder: null,
        currentVersionId: 'dv1',
        createdAt: now,
        updatedAt: now,
        isDeleted: false,
        ownerId: 'owner-1',
        syncStatus: 'pendingSync',
        version: 0,
        updatedBy: null,
      ));
      expect(row.containsKey('created_by'), isFalse);
      final companion = documentFromRemoteRow({...row, 'created_by': 'owner-1', 'version': 2});
      expect(companion.ownerId.value, 'owner-1');
      expect(companion.version.value, 2);
    });

    test('document version round-trips, falling back to createdAt when never updated', () async {
      final now = DateTime.utc(2026, 1, 1);
      final row = documentVersionToRemoteRow(DocumentVersion(
        id: 'dv1',
        documentId: 'd1',
        documentNumber: null,
        issueDate: null,
        expiryDate: DateTime.utc(2027, 1, 1),
        cost: 1200,
        providerId: null,
        comments: null,
        status: DocumentVersionStatus.valid,
        createdAt: now,
        updatedAt: null,
        syncStatus: 'pendingSync',
        version: 0,
        createdBy: null,
        updatedBy: null,
      ));
      expect(row['updated_at'], now.toIso8601String());
      final companion = documentVersionFromRemoteRow(row);
      expect(companion.cost.value, 1200);
      expect(companion.status.value, DocumentVersionStatus.valid);
    });

    test('an unknown document status name degrades to valid instead of throwing', () {
      final companion = documentVersionFromRemoteRow({
        'id': 'dv2',
        'document_id': 'd1',
        'status': 'not_a_real_status',
        'created_at': DateTime.utc(2026, 1, 1).toIso8601String(),
        'updated_at': DateTime.utc(2026, 1, 1).toIso8601String(),
      });
      expect(companion.status.value, DocumentVersionStatus.valid);
    });

    test('reminder round-trips without loss', () {
      final now = DateTime.utc(2026, 1, 1);
      final row = reminderToRemoteRow(Reminder(
        id: 'r1',
        vehicleId: 'v1',
        sourceType: 'maintenance',
        sourceId: 'm1',
        title: 'Vidange à prévoir',
        dueDate: DateTime.utc(2026, 6, 1),
        dueMileage: null,
        priority: 'normal',
        status: ReminderStatus.active,
        snoozedUntil: null,
        createdAt: now,
        updatedAt: now,
        syncStatus: 'pendingSync',
        version: 0,
        createdBy: null,
        updatedBy: null,
      ));
      final companion = reminderFromRemoteRow(row);
      expect(companion.title.value, 'Vidange à prévoir');
      expect(companion.status.value, ReminderStatus.active);
    });

    test('an unknown reminder status name degrades to active instead of throwing', () {
      final companion = reminderFromRemoteRow({
        'id': 'r2',
        'vehicle_id': 'v1',
        'source_type': 'document',
        'source_id': 'd1',
        'title': 'X',
        'status': 'bogus',
        'created_at': DateTime.utc(2026, 1, 1).toIso8601String(),
        'updated_at': DateTime.utc(2026, 1, 1).toIso8601String(),
      });
      expect(companion.status.value, ReminderStatus.active);
    });

    test('mileage entry round-trips without loss and carries no version', () {
      final now = DateTime.utc(2026, 1, 1);
      final row = mileageEntryToRemoteRow(MileageEntry(
        id: 'me1',
        vehicleId: 'v1',
        value: 52000,
        recordedAt: now,
        source: 'manual',
        sourceId: null,
        note: null,
        createdAt: now,
        syncStatus: 'pendingSync',
        createdBy: null,
      ));
      expect(row.containsKey('version'), isFalse);
      final companion = mileageEntryFromRemoteRow({...row, 'created_by': 'u1'});
      expect(companion.value.value, 52000);
      expect(companion.createdBy.value, 'u1');
    });

    test('operation frequency preference round-trips without loss', () {
      final now = DateTime.utc(2026, 1, 1);
      final row = frequencyPrefToRemoteRow(OperationFrequencyPreference(
        id: 'ofp1',
        vehicleId: 'v1',
        category: 'Vidange',
        frequencyKm: 10000,
        frequencyMonths: null,
        updatedAt: now,
        syncStatus: 'pendingSync',
        version: 0,
        createdBy: null,
        updatedBy: null,
      ));
      final companion = frequencyPrefFromRemoteRow({...row, 'version': 4});
      expect(companion.frequencyKm.value, 10000);
      expect(companion.version.value, 4);
    });
  });
}
