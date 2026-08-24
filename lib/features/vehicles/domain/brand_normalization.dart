import 'vehicle_reference_data.dart';

/// Normalizes brand-name spelling variants (accents, casing, spacing,
/// shorthand) to the exact string used in [carBrands] - so that "VW",
/// "Mercedes" or "Citroen" (no diaeresis) resolve to the same canonical
/// brand as "Volkswagen", "Mercedes-Benz" or "Citroën" wherever a mapping
/// (e.g. [brandLogoFor]) is keyed off the brand name. A brand this app
/// doesn't recognise is returned unchanged - never guessed at (Principe 7:
/// free text is always allowed, this never blocks or rewrites it).
String normalizeBrand(String raw) {
  final trimmed = raw.trim();
  if (trimmed.isEmpty) return trimmed;
  final key = _normalizedKey(trimmed);
  return _aliases[key] ?? _canonicalByKey[key] ?? trimmed;
}

/// Every entry of [carBrands] indexed by its own normalized key, so any
/// accent/casing/spacing variant of an already-correct name (e.g. "skoda"
/// for "Škoda", "citroen" for "Citroën") resolves without needing an
/// explicit alias for each one.
final Map<String, String> _canonicalByKey = {
  for (final brand in carBrands) _normalizedKey(brand): brand,
};

/// Genuine shorthand/alternate names - not just a formatting difference
/// from the canonical spelling, so these can't be derived automatically.
const Map<String, String> _aliases = {
  'vw': 'Volkswagen',
  'mercedes': 'Mercedes-Benz',
  'benz': 'Mercedes-Benz',
  'alfa': 'Alfa Romeo',
  'ds': 'DS Automobiles',
};

String _normalizedKey(String brand) =>
    _stripDiacritics(brand).toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');

String _stripDiacritics(String s) =>
    s.replaceAll('ë', 'e').replaceAll('Ë', 'E').replaceAll('š', 's').replaceAll('Š', 'S');
