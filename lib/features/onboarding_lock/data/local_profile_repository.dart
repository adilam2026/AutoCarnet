import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/database/database.dart';
import '../../../core/database/providers.dart';
import '../../../core/utils/id_generator.dart';
import '../../account/data/account_repository.dart';

/// AutoCarnet is offline-first (Principe 9): a single local profile is
/// enough to use the app fully. It can later be linked to a cloud account
/// without changing how every other module reads/writes data.
///
/// A profile's `ownerId` ties its preferences (displayName, currency,
/// distanceUnit) to whichever cloud account they belong to - `null` means
/// "created before any account ever signed in on this device" (pure
/// offline use). Without this, a second account signing in on the same
/// phone would silently inherit the first account's name and currency
/// instead of getting its own - see AppGate._onAccountAuthenticated for
/// how a profile is claimed (first sign-in) or freshly created (a real
/// account switch) accordingly.
class LocalProfileRepository {
  LocalProfileRepository(this._db);
  final AppDatabase _db;

  Stream<LocalProfile?> watch({String? currentUserId}) {
    final query = _db.select(_db.localProfiles);
    if (currentUserId != null) {
      query.where((p) => p.ownerId.equals(currentUserId) | p.ownerId.isNull());
    } else {
      query.where((p) => p.ownerId.isNull());
    }
    return query.watch().map((rows) => _pick(rows, currentUserId));
  }

  Future<LocalProfile?> getOrNull({String? currentUserId}) async {
    final query = _db.select(_db.localProfiles);
    if (currentUserId != null) {
      query.where((p) => p.ownerId.equals(currentUserId) | p.ownerId.isNull());
    } else {
      query.where((p) => p.ownerId.isNull());
    }
    return _pick(await query.get(), currentUserId);
  }

  /// A row already owned by [currentUserId] always wins over a leftover
  /// orphan row (there should be at most one of each once AppGate has run,
  /// but preferring the owned one keeps this correct even mid-transition).
  LocalProfile? _pick(List<LocalProfile> rows, String? currentUserId) {
    if (rows.isEmpty) return null;
    if (currentUserId == null) return rows.first;
    return rows.firstWhere(
      (r) => r.ownerId == currentUserId,
      orElse: () => rows.first,
    );
  }

  Future<void> create({
    required String displayName,
    String currency = 'MAD',
    String distanceUnit = 'km',
    String? ownerId,
  }) {
    return _db.into(_db.localProfiles).insert(
          LocalProfilesCompanion.insert(
            id: newId(),
            displayName: displayName,
            currency: Value(currency),
            distanceUnit: Value(distanceUnit),
            createdAt: DateTime.now(),
            ownerId: Value(ownerId),
          ),
        );
  }

  Future<void> updatePreferences(
    String id, {
    String? displayName,
    String? currency,
    String? distanceUnit,
  }) {
    return (_db.update(_db.localProfiles)..where((p) => p.id.equals(id))).write(
      LocalProfilesCompanion(
        displayName:
            displayName != null ? Value(displayName) : const Value.absent(),
        currency: currency != null ? Value(currency) : const Value.absent(),
        distanceUnit:
            distanceUnit != null ? Value(distanceUnit) : const Value.absent(),
      ),
    );
  }

  /// A pre-account local profile (created via onboarding, `ownerId` still
  /// null) becomes this account's own profile the first time a cloud
  /// account signs in on this device - its existing name/currency are kept
  /// (linking an account never wipes what was already there), just tagged
  /// so a later, genuinely different account never inherits it.
  Future<void> claimOwnership(String id, String ownerId) {
    return (_db.update(_db.localProfiles)..where((p) => p.id.equals(id)))
        .write(LocalProfilesCompanion(ownerId: Value(ownerId)));
  }

  /// Same reattribution pattern as VehicleRepository/ProviderRepository/
  /// DocumentRepository: on a genuine account switch, any profile still
  /// unowned on this device belonged to whoever was using it before, not
  /// to the new account - reattribute it rather than ever deleting it.
  Future<void> handleAccountSwitch(String previousOwnerId) {
    return (_db.update(_db.localProfiles)..where((p) => p.ownerId.isNull()))
        .write(LocalProfilesCompanion(ownerId: Value(previousOwnerId)));
  }
}

final localProfileRepositoryProvider = Provider<LocalProfileRepository>((ref) {
  return LocalProfileRepository(ref.watch(appDatabaseProvider));
});

final localProfileProvider = StreamProvider<LocalProfile?>((ref) {
  // Rebuilds whenever the signed-in account changes (sign in, sign out,
  // account switch) - without re-scoping here, account B could keep
  // seeing account A's displayName/currency after A signs out, or after
  // B signs in on the same device (see LocalProfileRepository doc).
  ref.watch(authStateChangesProvider);
  final currentUserId = ref.watch(accountRepositoryProvider).currentUser?.id;
  return ref.watch(localProfileRepositoryProvider).watch(currentUserId: currentUserId);
});

/// Real, wired setting: every new expense/entretien/plein defaults to this
/// currency instead of a hardcoded value (Principe 3: a preference set once
/// applies everywhere, it isn't cosmetic).
final defaultCurrencyProvider = Provider<String>((ref) {
  return ref.watch(localProfileProvider).maybeWhen(
        data: (p) => p?.currency ?? 'MAD',
        orElse: () => 'MAD',
      );
});

const List<String> availableCurrencies = ['MAD', 'EUR', 'USD', 'GBP', 'CHF'];
