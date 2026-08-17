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
    default:
      return null;
  }
}

/// The vignette is tied to the calendar year, never to "payment date + 12
/// months": paying on 15/08/2026 must still produce an échéance pinned to
/// the start of the following civil year, not 15/08/2027.
bool isCivilYearBound(String type) => type == 'Vignette';

DateTime civilYearDueDate(DateTime paidOn) => DateTime(paidOn.year + 1, 1, 1);
