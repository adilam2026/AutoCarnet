/// The number of years after first registration before a technical
/// inspection (visite technique) becomes legally mandatory in Morocco.
const int visiteTechniqueMandatoryFromYears = 5;

/// Whether a vehicle registered on [firstRegistrationDate] is old enough to
/// require a visite technique yet. Unknown registration date defaults to
/// true (mandatory), since silently hiding a real requirement is worse than
/// an occasional false positive nudging the owner to add one early.
bool visiteTechniqueMandatoryYet(DateTime? firstRegistrationDate, {DateTime? now}) {
  if (firstRegistrationDate == null) return true;
  final mandatoryFrom = DateTime(
    firstRegistrationDate.year + visiteTechniqueMandatoryFromYears,
    firstRegistrationDate.month,
    firstRegistrationDate.day,
  );
  final reference = now ?? DateTime.now();
  return !reference.isBefore(mandatoryFrom);
}
