import 'package:autocarnet/core/database/database.dart';
import 'package:autocarnet/features/onboarding_lock/data/local_profile_repository.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

/// The last gap flagged in the Auth/Session/Multi-compte audit: local
/// profile preferences (displayName, currency, distanceUnit) had no
/// `ownerId` at all, so they were device-wide instead of following the
/// signed-in account - after a switch, the new account would silently see
/// the previous one's name and currency. This reproduces the exact
/// scenario: A's preferences -> disconnect -> B's own preferences (B
/// edits them) -> disconnect -> reconnect A -> A's original preferences
/// come back uncontaminated by anything B did.
void main() {
  late AppDatabase db;
  late LocalProfileRepository profiles;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    profiles = LocalProfileRepository(db);
  });

  tearDown(() => db.close());

  test(
      'A -> disconnect -> B (own name/currency, edits them) -> disconnect -> reconnect A: '
      'A gets back exactly its own name/MAD, never contaminated by B', () async {
    // --- Compte A se connecte pour la première fois : profil créé avec
    // --- son nom et sa devise (comme AppGate._onAccountAuthenticated). ---
    await profiles.create(displayName: 'Adil', currency: 'MAD', ownerId: 'user-A');
    final aProfile = (await profiles.getOrNull(currentUserId: 'user-A'))!;
    expect(aProfile.displayName, 'Adil');
    expect(aProfile.currency, 'MAD');

    // --- Déconnexion de A, connexion de B sur le même téléphone : ---
    // --- handleAccountSwitch tourne d'abord (rien à réattribuer ici, ---
    // --- aucun profil orphelin), puis B n'a pas encore de profil -> ---
    // --- profil neuf avec SES propres valeurs, jamais celles de A. ---
    await profiles.handleAccountSwitch('user-A');
    final existingForB = await profiles.getOrNull(currentUserId: 'user-B');
    expect(existingForB, isNull, reason: 'B must never inherit A\'s profile row');
    await profiles.create(displayName: 'Sara', currency: 'EUR', ownerId: 'user-B');

    final bProfile = (await profiles.getOrNull(currentUserId: 'user-B'))!;
    expect(bProfile.displayName, 'Sara');
    expect(bProfile.currency, 'EUR');
    // B must never see A's name/devise just by being on the same device.
    expect(bProfile.displayName, isNot('Adil'));
    expect(bProfile.currency, isNot('MAD'));

    // --- B modifie ses propres préférences. ---
    await profiles.updatePreferences(bProfile.id, displayName: 'Sara B.', currency: 'USD');
    final bProfileAfterEdit = (await profiles.getOrNull(currentUserId: 'user-B'))!;
    expect(bProfileAfterEdit.displayName, 'Sara B.');
    expect(bProfileAfterEdit.currency, 'USD');

    // --- Déconnexion de B, reconnexion de A : A retrouve exactement son ---
    // --- nom et sa devise d'origine, sans aucune contamination par B. ---
    await profiles.handleAccountSwitch('user-B');
    final aProfileAgain = (await profiles.getOrNull(currentUserId: 'user-A'))!;
    expect(aProfileAgain.id, aProfile.id);
    expect(aProfileAgain.displayName, 'Adil');
    expect(aProfileAgain.currency, 'MAD');
    expect(aProfileAgain.displayName, isNot('Sara B.'));
    expect(aProfileAgain.currency, isNot('USD'));

    // --- Et B, si reconnecté à nouveau, retrouve ses propres modifs. ---
    final bProfileAgain = (await profiles.getOrNull(currentUserId: 'user-B'))!;
    expect(bProfileAgain.displayName, 'Sara B.');
    expect(bProfileAgain.currency, 'USD');
  });

  test(
      'a pre-account offline profile (ownerId null) is claimed, not discarded, on the first '
      'ever cloud sign-in - preferences set before linking an account survive', () async {
    // Onboarding creates a profile before any account exists at all.
    await profiles.create(displayName: 'Utilisateur hors-ligne', currency: 'MAD');
    final orphan = (await profiles.getOrNull())!;
    expect(orphan.ownerId, isNull);

    // First-ever sign-in: AppGate finds this exact row via
    // getOrNull(currentUserId: ...) (owner-or-orphan) and claims it -
    // never creates a second, empty-defaults row.
    final found = await profiles.getOrNull(currentUserId: 'user-A');
    expect(found!.id, orphan.id);
    await profiles.claimOwnership(orphan.id, 'user-A');

    final claimed = (await profiles.getOrNull(currentUserId: 'user-A'))!;
    expect(claimed.id, orphan.id);
    expect(claimed.displayName, 'Utilisateur hors-ligne');
    expect(claimed.ownerId, 'user-A');

    // A different account must never see this now-claimed profile.
    final forB = await profiles.getOrNull(currentUserId: 'user-B');
    expect(forB, isNull);
  });

  test('watch() scoped to the current account only ever emits that account\'s profile', () async {
    await profiles.create(displayName: 'Adil', currency: 'MAD', ownerId: 'user-A');
    await profiles.create(displayName: 'Sara', currency: 'EUR', ownerId: 'user-B');

    final forA = await profiles.watch(currentUserId: 'user-A').first;
    final forB = await profiles.watch(currentUserId: 'user-B').first;
    final forNoAccount = await profiles.watch().first;

    expect(forA!.displayName, 'Adil');
    expect(forB!.displayName, 'Sara');
    expect(forNoAccount, isNull, reason: 'no orphan row exists once both accounts have their own');
  });
}
