/// AdBlue is stored as a [FuelEntry] with [adblueFuelType] as its
/// `fuelType` (mission 2026, point 2) rather than a brand new table - it
/// already needs exactly the same shape (date, kilométrage, montant,
/// quantité, prestataire, commentaire) and the same offline/sync plumbing
/// FuelEntries already has. What actually keeps it "traité séparément du
/// carburant classique" is that every consumption/cost computation
/// ([FuelRepository.computeStats]) explicitly excludes this fuel type, and
/// every UI surface treats it as its own kind of entry (its own quick
/// action, its own icon/label, its own expense category) rather than a
/// variant of a fill-up.
const String adblueFuelType = 'AdBlue';

/// AutoCarnet's default theoretical AdBlue range (mission point 3): the
/// mileage after a fill-up at which another one is expected to be needed.
/// Centralized here on purpose - a single constant, never a `10000`
/// repeated across screens - so a later pass can vary it per vehicle/model,
/// swap in a real constructor-provided range, or let the owner override it,
/// by changing only this one rule.
class AdblueRules {
  const AdblueRules._();

  static const double defaultRangeKm = 10000;

  /// The mileage at which AutoCarnet expects the next AdBlue fill-up to be
  /// needed, given the mileage of the last one.
  static double nextDueMileage(double lastFillMileage) =>
      lastFillMileage + defaultRangeKm;
}
