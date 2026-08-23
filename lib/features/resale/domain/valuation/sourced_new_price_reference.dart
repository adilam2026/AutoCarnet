/// A small, hand-curated table of REAL historical new-car catalogue prices
/// in Morocco, each one traceable to a named source - never a guessed or
/// invented figure. This is deliberately a data table, not a pricing rule:
/// [VehicleValuationReference.newPriceFor] falls back to the generic
/// brand-tier/segment estimate for anything not listed here, and the
/// engine that consumes either kind of base price stays exactly the same
/// generic calculation either way (no per-vehicle special case is ever
/// introduced downstream of this file).
///
/// Adding an entry: every entry must carry a real source (a named site and
/// page, ideally with the exact trim/engine it was quoted for) - the
/// [note] field exists precisely to record which trim/engine the quoted
/// price applies to, since a single model can span a wide price spread
/// across finitions.
class SourcedNewPriceEntry {
  final String brand;
  final String model;
  final String generation;
  final int yearFrom;
  final int yearTo;
  final double priceMad;
  final String source;
  final String note;

  const SourcedNewPriceEntry({
    required this.brand,
    required this.model,
    required this.generation,
    required this.yearFrom,
    required this.yearTo,
    required this.priceMad,
    required this.source,
    required this.note,
  });
}

class SourcedNewPriceReference {
  const SourcedNewPriceReference._();

  /// Every price below was looked up on a named Moroccan automotive
  /// catalogue site (wandaloo.com, siaracash.ma, autonews.ma) in August
  /// 2026 - see each entry's [SourcedNewPriceEntry.source]. None of these
  /// figures are estimated, interpolated or invented: where a generation
  /// or trim isn't covered here, [VehicleValuationReference.newPriceFor]
  /// correctly falls back to the generic brand-tier estimate instead of
  /// guessing a number to fill the gap.
  static const List<SourcedNewPriceEntry> entries = [
    SourcedNewPriceEntry(
      brand: 'Opel',
      model: 'Astra',
      generation: 'Astra Berline (génération commercialisée neuve au Maroc ~2010-2015)',
      yearFrom: 2009,
      yearTo: 2015,
      priceMad: 244900,
      source: 'wandaloo.com - fiche "OPEL Astra Berline 1.7 CDTi Cosmo", prix clé en main '
          '(archive/opel/astra-berline/fiche-technique/1-7-cdti-cosmo/3056.html)',
      note: 'Finition milieu/haut de gamme diesel (1.7 CDTi Cosmo). Les finitions plus '
          'simples de la même génération (Enjoy, Cosmo Pack) étaient vendues autour de ce '
          'même ordre de grandeur - aucune fourchette basse/haute précise trouvée à ce jour.',
    ),
    SourcedNewPriceEntry(
      brand: 'Opel',
      model: 'Astra',
      generation: 'Astra nouvelle génération (commercialisée neuve au Maroc depuis 2024)',
      yearFrom: 2024,
      yearTo: 2100,
      priceMad: 273000,
      source: 'siaracash.ma - "OPEL Astra Neuve au Maroc", prix de départ de gamme',
      note: 'Prix d\'entrée de gamme (4 versions disponibles, jusqu\'à un tarif plus élevé '
          'en finition haute non détaillé ici).',
    ),
    // Note: a 2020-2023 "FY restylée" Q5 generation entry was deliberately
    // NOT added here. Two "Design"-trim prices were found (30 TDI 136 at
    // ~549 000 DH, 40 TDI 204 at ~565 000 DH), but which exact model years
    // and how the more common quattro/higher trims priced for that
    // generation couldn't be confirmed without direct page access (wandaloo.com
    // is blocked by this session's network egress policy - only search-engine
    // snippets were reachable). Rather than anchor a whole generation's
    // resale estimate on two low-confidence, possibly entry-trim-only
    // prices, this generation is deliberately left to the generic
    // brand-tier/segment fallback until it can be verified properly.
    SourcedNewPriceEntry(
      brand: 'Audi',
      model: 'Q5',
      generation: 'Q5 3e génération (commercialisée neuve au Maroc depuis 2024)',
      yearFrom: 2024,
      yearTo: 2100,
      priceMad: 689700,
      source: 'autonews.ma - "AUDI Q5 Neuve Maroc", finition Dynamic (prix de départ de gamme)',
      note: 'Prix d\'entrée de gamme (Dynamic). Les finitions Sport, S-line et S-Edition de '
          'cette génération allaient jusqu\'à 842 000 DH.',
    ),
  ];

  /// The most specific match for [brand]/[model] whose year range contains
  /// [year] - or null when nothing sourced covers this vehicle, in which
  /// case the caller must fall back to the generic estimate rather than
  /// stretching a nearby entry to fit.
  static SourcedNewPriceEntry? lookup(String brand, String model, int? year) {
    if (year == null) return null;
    final normalizedModel = model.trim().toLowerCase();
    for (final entry in entries) {
      if (entry.brand != brand) continue;
      if (entry.model.trim().toLowerCase() != normalizedModel) continue;
      if (year >= entry.yearFrom && year <= entry.yearTo) return entry;
    }
    return null;
  }
}
