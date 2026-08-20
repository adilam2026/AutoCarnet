import 'package:autocarnet/core/database/database.dart';
import 'package:autocarnet/features/audit/data/audit_repository.dart';
import 'package:autocarnet/features/documents/data/document_repository.dart';
import 'package:autocarnet/features/providers/data/provider_repository.dart';
import 'package:autocarnet/features/reminders/data/reminder_repository.dart';
import 'package:autocarnet/features/timeline/data/timeline_repository.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

/// Two more cross-account leaks found in the same class as the vehicle/
/// reminder/audit ones (multi_account_isolation_test.dart,
/// multi_account_reminders_audit_test.dart), found by a deliberate
/// second-pass audit of every repository rather than waiting to discover
/// them live: service providers (private contacts - name, phone, email)
/// and driver documents (permis de conduire, pièce d'identité - the
/// highest-severity case, real identity documents) both had zero account
/// scoping at all.
void main() {
  late AppDatabase db;
  late ProviderRepository providers;
  late DocumentRepository documents;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    providers = ProviderRepository(db);
    documents = DocumentRepository(
      db,
      TimelineRepository(db),
      ReminderRepository(db),
    );
  });

  tearDown(() => db.close());

  test('a provider created by user A never appears in user B\'s list or search', () async {
    await providers.createProvider(name: 'Garage Audi Casablanca', currentUserId: 'user-A');

    final listForB = await providers.watchAll(currentUserId: 'user-B').first;
    final searchForB = await providers.search('Audi', currentUserId: 'user-B');
    final duplicateForB =
        await providers.findLikelyDuplicate('Audi Casablanca', currentUserId: 'user-B');

    expect(listForB, isEmpty);
    expect(searchForB, isEmpty);
    expect(duplicateForB, isNull);
  });

  test('a provider created by user A is still visible to user A', () async {
    final id = await providers.createProvider(name: 'Station Total', currentUserId: 'user-A');

    final listForA = await providers.watchAll(currentUserId: 'user-A').first;

    expect(listForA.map((p) => p.id), contains(id));
  });

  test(
      'handleAccountSwitch reattributes providers created before this device ever had an '
      'account to whoever was actually using it', () async {
    final id = await providers.createProvider(name: 'Garage local');

    await providers.handleAccountSwitch('user-A');

    final forB = await providers.watchAll(currentUserId: 'user-B').first;
    final forA = await providers.watchAll(currentUserId: 'user-A').first;
    expect(forB.map((p) => p.id), isNot(contains(id)));
    expect(forA.map((p) => p.id), contains(id));
  });

  test(
      'a driver document (permis, pièce d\'identité) created by user A never appears in '
      'user B\'s driver documents - the highest-severity leak found in this audit', () async {
    await documents.createDocument(
      vehicleId: null,
      type: 'permis de conduire',
      documentNumber: 'A123456',
      currentUserId: 'user-A',
    );

    final forB = await documents.watchDriverDocuments(currentUserId: 'user-B').first;
    final forA = await documents.watchDriverDocuments(currentUserId: 'user-A').first;

    expect(forB, isEmpty);
    expect(forA, isNotEmpty);
  });

  test('a vehicle-scoped document is unaffected by driver-document account scoping', () async {
    // Vehicle-scoped documents are already gated by the vehicle they
    // belong to (see multi_account_isolation_test.dart) - this just
    // confirms createDocument/watchDriverDocuments never mix the two.
    final vehicleDocId = await documents.createDocument(
      vehicleId: 'some-vehicle-id',
      type: 'carte grise',
      currentUserId: 'user-A',
    );

    final driverDocsForA = await documents.watchDriverDocuments(currentUserId: 'user-A').first;

    expect(driverDocsForA.map((d) => d.document.id), isNot(contains(vehicleDocId)));
  });

  test(
      'handleAccountSwitch reattributes an unowned driver document to whoever was actually '
      'using the device, and never touches vehicle-scoped documents', () async {
    final driverDocId = await documents.createDocument(vehicleId: null, type: 'pièce d\'identité');
    final vehicleDocId =
        await documents.createDocument(vehicleId: 'some-vehicle-id', type: 'carte grise');

    await documents.handleAccountSwitch('user-A');

    final forB = await documents.watchDriverDocuments(currentUserId: 'user-B').first;
    final forA = await documents.watchDriverDocuments(currentUserId: 'user-A').first;
    expect(forB.map((d) => d.document.id), isNot(contains(driverDocId)));
    expect(forA.map((d) => d.document.id), contains(driverDocId));

    // Vehicle-scoped document untouched by the driver-document switch pass.
    final vehicleDoc = await documents.getById(vehicleDocId);
    expect(vehicleDoc!.document.ownerId, isNull);
  });
}
