/// AutoCarnet's default renewal interval per document type - only ever used
/// to *suggest* an expiry date so the owner doesn't have to compute it by
/// hand, never to silently override a date they already chose themselves.
/// The architecture allows finer, country/vehicle-age-dependent rules to
/// replace this later without touching the form.
int? defaultRenewalMonths(String type) {
  switch (type) {
    case 'Assurance':
    case 'Visite technique':
      return 12;
    case 'Permis de conduire':
      return 120;
    default:
      return null;
  }
}

/// The vignette is tied to the calendar year, never to "payment date + 12
/// months": a vignette bought for civil year Y is valid 1/1-31/12/Y
/// regardless of when it was paid.
bool isCivilYearBound(String type) => type == 'Vignette';

/// The vignette nominally expires 31/12 of [vignetteYear], but the state
/// grants a grace period until 31/01 of the following year before it's
/// actually overdue - so this is the date that drives status/reminders, not
/// the nominal 31/12 (which is only ever shown as information).
DateTime civilYearDueDate(int vignetteYear) => DateTime(vignetteYear + 1, 1, 31);
