import 'package:autocarnet/core/database/database.dart';
import 'package:autocarnet/features/audit/data/audit_repository.dart';
import 'package:autocarnet/features/documents/data/document_repository.dart';
import 'package:autocarnet/features/onboarding_lock/domain/gate_decision.dart';
import 'package:autocarnet/features/providers/data/provider_repository.dart';
import 'package:autocarnet/features/reminders/data/reminder_repository.dart';
import 'package:autocarnet/features/timeline/data/timeline_repository.dart';
import 'package:autocarnet/features/vehicles/data/vehicle_repository.dart';
import 'package:drift/drift.dart' hide isNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

/// The exact end-to-end scenario requested for the Auth/Session/
/// Multi-compte "Definition of Done": one continuous narrative walking
/// through account A's data, a real account switch to B, and back to A,
/// covering vehicles, personal providers and driver documents together
/// (the three entity types this audit found and fixed real leaks on) plus
/// the vehicle-sharing case in the same flow.
void main() {
  late AppDatabase db;
  late VehicleRepository vehicles;
  late ProviderRepository providers;
  late DocumentRepository documents;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    vehicles = VehicleRepository(db, AuditRepository(db), ReminderRepository(db));
    providers = ProviderRepository(db);
    documents = DocumentRepository(db, TimelineRepository(db), ReminderRepository(db));
  });

  tearDown(() => db.close());

  test(
      '1-6: A\'s vehicles/providers/documents visible while A is signed in, invisible to B after '
      'a switch, A\'s shared vehicle stays visible to B, and everything reappears when A signs '
      'back in', () async {
    // --- 1. Compte A connecté -> ses données créées et visibles. ---
    final aVehicleId = await vehicles.createVehicle(brand: 'Renault', model: 'Clio', currentMileage: 10000);
    await (db.update(db.vehicles)..where((v) => v.id.equals(aVehicleId)))
        .write(const VehiclesCompanion(ownerId: Value('user-A')));
    final aProviderId =
        await providers.createProvider(name: 'Garage Audi Rabat', currentUserId: 'user-A');
    final aDriverDocId = await documents.createDocument(
      vehicleId: null,
      type: 'permis de conduire',
      currentUserId: 'user-A',
    );
    // A vehicle A owns and has explicitly shared with B (myRole cached
    // locally for B's device, exactly as VehicleSyncService._pull sets it
    // once B has accepted a real invite).
    final sharedVehicleId =
        await vehicles.createVehicle(brand: 'Audi', model: 'Q5', currentMileage: 50000);
    await (db.update(db.vehicles)..where((v) => v.id.equals(sharedVehicleId))).write(
      const VehiclesCompanion(ownerId: Value('user-A')),
    );

    final forAInitially = await vehicles.watchAll(currentUserId: 'user-A').first;
    expect(forAInitially.map((v) => v.id), containsAll([aVehicleId, sharedVehicleId]));
    expect((await providers.watchAll(currentUserId: 'user-A').first).map((p) => p.id),
        contains(aProviderId));
    expect(
        (await documents.watchDriverDocuments(currentUserId: 'user-A').first)
            .map((d) => d.document.id),
        contains(aDriverDocId));

    // --- 2/3. Déconnexion A, connexion B sur le même téléphone. ---
    // AppGate._onAccountAuthenticated runs handleAccountSwitch first
    // (clearing any myRole left over from whoever used the device before,
    // reattributing unowned rows) - only *afterwards* does B's own sync
    // pass run and set myRole from B's real, current vehicle_members
    // row. Order matters and is reproduced exactly here.
    await vehicles.handleAccountSwitch('user-A');
    await providers.handleAccountSwitch('user-A');
    await documents.handleAccountSwitch('user-A');
    // B's own sync pulling the real share for sharedVehicleId.
    await (db.update(db.vehicles)..where((v) => v.id.equals(sharedVehicleId)))
        .write(const VehiclesCompanion(myRole: Value('viewer')));

    // --- 4. Aucune donnée privée de A visible pour B. ---
    final forB = await vehicles.watchAll(currentUserId: 'user-B').first;
    expect(forB.map((v) => v.id), isNot(contains(aVehicleId)));
    expect((await providers.watchAll(currentUserId: 'user-B').first).map((p) => p.id),
        isNot(contains(aProviderId)));
    expect(
        (await documents.watchDriverDocuments(currentUserId: 'user-B').first)
            .map((d) => d.document.id),
        isNot(contains(aDriverDocId)));

    // --- 5. Le véhicule explicitement partagé avec B reste visible. ---
    expect(forB.map((v) => v.id), contains(sharedVehicleId));

    // --- 10. Les documents conducteur ne sont jamais partagés avec les ---
    // --- utilisateurs d'un véhicule partagé. ---
    // B can see the shared vehicle but must never see A's own driver
    // documents just because a vehicle is shared - already asserted
    // above (driver documents stayed invisible to B even though the
    // vehicle share was granted).

    // --- 6. Déconnexion B, reconnexion A -> tout réapparaît. ---
    // A is the *same* account as before, so AppGate never calls
    // handleAccountSwitch for this leg (see app_gate.dart: only a
    // genuinely *different* account triggers it) - nothing was ever
    // touched for A's own data, it's simply readable again once A is
    // signed in.
    final forAAgain = await vehicles.watchAll(currentUserId: 'user-A').first;
    final providersForAAgain = await providers.watchAll(currentUserId: 'user-A').first;
    final docsForAAgain = await documents.watchDriverDocuments(currentUserId: 'user-A').first;
    expect(forAAgain.map((v) => v.id), containsAll([aVehicleId, sharedVehicleId]));
    expect(providersForAAgain.map((p) => p.id), contains(aProviderId));
    expect(docsForAAgain.map((d) => d.document.id), contains(aDriverDocId));
  });

  test(
      '7/8: an offline-but-authenticated session keeps reading the current account\'s local '
      'data, while a real sign-out (mustReauthenticateViaEmail) blocks it regardless of PIN/cache',
      () {
    // 7. Session authentifiée hors connexion -> données locales
    // accessibles: isSignedIn stays true purely from the cached Supabase
    // session, with no network involved at all - see AccountRepository
    // .isSignedIn (currentSession != null) and gate_decision_test.dart's
    // dedicated "offline is not a logout" case.
    expect(
      mustReauthenticateViaEmail(hasEverLinkedCloudAccount: true, isSignedIn: true),
      isFalse,
      reason: 'an authenticated-but-offline session must keep local data reachable',
    );

    // 8. Vraie déconnexion -> PIN/biométrie ne peuvent plus rouvrir
    // l'ancien compte, quelles que soient les données encore en cache
    // localement (see AppGate._evaluate + the whole point of
    // handleAccountSwitch above: the *data* can stay cached, but the
    // *gate* refuses to reach it without a fresh sign-in).
    expect(
      mustReauthenticateViaEmail(hasEverLinkedCloudAccount: true, isSignedIn: false),
      isTrue,
      reason: 'a real sign-out must never be bypassable by PIN/biometric/local cache',
    );
  });
}
