/// Body-segment classification, the piece the référentiel was missing
/// (bloc 24-27): a brand tier alone treats every model from the same brand
/// as equally expensive, which is exactly why a premium mid-size SUV used
/// to land at the same reference price as a premium city car. This table
/// only encodes an objective fact - which segment a given model belongs to
/// - never a calibrated price for one specific vehicle; the actual money
/// value stays entirely driven by [VehicleValuationReference]'s brand tier
/// and the multipliers below, both generic across every brand and model.
enum VehicleSegment {
  citadine,
  compacte,
  berline,
  monospace,
  suvCompact,
  suvMoyen,
  suvGrand,
  coupeCabriolet,
  pickup,
  utilitaire,
}

class VehicleSegmentRules {
  const VehicleSegmentRules._();

  /// Multiplicative adjustment applied to a brand tier's generic new-price
  /// midpoint - a mid-size SUV costs meaningfully more new than a city car
  /// of the same brand, regardless of which brand it is.
  ///
  /// `suvMoyen` lowered again, 1.46 -> 1.13 (moteur de revente recalibration
  /// pass, 2026): the depreciation curve itself (depreciation_rules.dart)
  /// was rewritten to be far less punitive per the explicit cadre métier -
  /// which means the SAME generic reference price that used to land an
  /// unsourced premium SUV (e.g. a 2021 Audi Q5, whose real generation
  /// isn't in the sourced référentiel) near the expected ~390 000 MAD under
  /// the old, steeper curve now overshoots to ~500 000+ MAD once that curve
  /// stops eating the difference on its own. This multiplier is still a
  /// single generic value shared by every brand/model in this segment
  /// (BMW X3, Mercedes GLC, Volvo XC60, Peugeot 3008, Hyundai Tucson,
  /// etc.) - never a Q5-specific tweak.
  static const Map<VehicleSegment, double> _multipliers = {
    VehicleSegment.citadine: 0.65,
    VehicleSegment.compacte: 0.90,
    VehicleSegment.berline: 1.10,
    VehicleSegment.monospace: 1.00,
    VehicleSegment.suvCompact: 1.30,
    VehicleSegment.suvMoyen: 1.13,
    VehicleSegment.suvGrand: 2.10,
    VehicleSegment.coupeCabriolet: 1.30,
    VehicleSegment.pickup: 1.20,
    VehicleSegment.utilitaire: 0.80,
  };

  /// Known model -> segment, covering the curated model suggestions in
  /// [carModelsByBrand]. A model AutoCarnet doesn't recognise (free text,
  /// or a brand without a curated list) simply gets no adjustment - never a
  /// guess dressed up as a fact.
  static const Map<String, Map<String, VehicleSegment>> _modelSegments = {
    'Audi': {
      'A1': VehicleSegment.citadine,
      'A3': VehicleSegment.compacte,
      'A4': VehicleSegment.berline,
      'A5': VehicleSegment.coupeCabriolet,
      'A6': VehicleSegment.berline,
      'Q2': VehicleSegment.suvCompact,
      'Q3': VehicleSegment.suvCompact,
      'Q5': VehicleSegment.suvMoyen,
      'Q7': VehicleSegment.suvGrand,
      'Q8': VehicleSegment.suvGrand,
      'e-tron': VehicleSegment.suvMoyen,
    },
    'BMW': {
      'Série 1': VehicleSegment.compacte,
      'Série 2': VehicleSegment.coupeCabriolet,
      'Série 3': VehicleSegment.berline,
      'Série 4': VehicleSegment.coupeCabriolet,
      'Série 5': VehicleSegment.berline,
      'X1': VehicleSegment.suvCompact,
      'X2': VehicleSegment.suvCompact,
      'X3': VehicleSegment.suvMoyen,
      'X5': VehicleSegment.suvGrand,
      'X6': VehicleSegment.suvGrand,
    },
    'Citroën': {
      'C3': VehicleSegment.citadine,
      'C3 Aircross': VehicleSegment.suvCompact,
      'C4': VehicleSegment.compacte,
      'C4 Picasso': VehicleSegment.monospace,
      'C5 Aircross': VehicleSegment.suvMoyen,
      'Berlingo': VehicleSegment.utilitaire,
      'Jumpy': VehicleSegment.utilitaire,
    },
    'Dacia': {
      'Sandero': VehicleSegment.citadine,
      'Logan': VehicleSegment.berline,
      'Duster': VehicleSegment.suvCompact,
      'Spring': VehicleSegment.citadine,
      'Jogger': VehicleSegment.monospace,
      'Lodgy': VehicleSegment.monospace,
      'Dokker': VehicleSegment.utilitaire,
    },
    'Fiat': {
      '500': VehicleSegment.citadine,
      '500X': VehicleSegment.suvCompact,
      'Panda': VehicleSegment.citadine,
      'Tipo': VehicleSegment.compacte,
      'Doblo': VehicleSegment.utilitaire,
      'Punto': VehicleSegment.citadine,
    },
    'Ford': {
      'Fiesta': VehicleSegment.citadine,
      'Focus': VehicleSegment.compacte,
      'Puma': VehicleSegment.suvCompact,
      'Kuga': VehicleSegment.suvMoyen,
      'EcoSport': VehicleSegment.suvCompact,
      'Transit': VehicleSegment.utilitaire,
    },
    'Honda': {
      'Civic': VehicleSegment.compacte,
      'CR-V': VehicleSegment.suvMoyen,
      'HR-V': VehicleSegment.suvCompact,
      'Jazz': VehicleSegment.citadine,
      'Accord': VehicleSegment.berline,
    },
    'Hyundai': {
      'i10': VehicleSegment.citadine,
      'i20': VehicleSegment.citadine,
      'i30': VehicleSegment.compacte,
      'Tucson': VehicleSegment.suvMoyen,
      'Santa Fe': VehicleSegment.suvGrand,
      'Kona': VehicleSegment.suvCompact,
      'Accent': VehicleSegment.berline,
    },
    'Jeep': {
      'Renegade': VehicleSegment.suvCompact,
      'Compass': VehicleSegment.suvCompact,
      'Cherokee': VehicleSegment.suvMoyen,
      'Wrangler': VehicleSegment.suvMoyen,
    },
    'Kia': {
      'Picanto': VehicleSegment.citadine,
      'Rio': VehicleSegment.citadine,
      'Ceed': VehicleSegment.compacte,
      'Sportage': VehicleSegment.suvMoyen,
      'Sorento': VehicleSegment.suvGrand,
      'Stonic': VehicleSegment.suvCompact,
    },
    'Mazda': {
      'Mazda2': VehicleSegment.citadine,
      'Mazda3': VehicleSegment.compacte,
      'CX-3': VehicleSegment.suvCompact,
      'CX-5': VehicleSegment.suvMoyen,
      'CX-30': VehicleSegment.suvCompact,
    },
    'Mercedes-Benz': {
      'Classe A': VehicleSegment.compacte,
      'Classe B': VehicleSegment.monospace,
      'Classe C': VehicleSegment.berline,
      'Classe E': VehicleSegment.berline,
      'GLA': VehicleSegment.suvCompact,
      'GLC': VehicleSegment.suvMoyen,
      'GLE': VehicleSegment.suvGrand,
    },
    'Nissan': {
      'Micra': VehicleSegment.citadine,
      'Juke': VehicleSegment.suvCompact,
      'Qashqai': VehicleSegment.suvMoyen,
      'X-Trail': VehicleSegment.suvGrand,
      'Navara': VehicleSegment.pickup,
    },
    'Opel': {
      'Corsa': VehicleSegment.citadine,
      'Astra': VehicleSegment.compacte,
      'Crossland': VehicleSegment.suvCompact,
      'Grandland': VehicleSegment.suvMoyen,
      'Mokka': VehicleSegment.suvCompact,
    },
    'Peugeot': {
      '108': VehicleSegment.citadine,
      '208': VehicleSegment.citadine,
      '2008': VehicleSegment.suvCompact,
      '308': VehicleSegment.compacte,
      '3008': VehicleSegment.suvMoyen,
      '5008': VehicleSegment.suvGrand,
      'Partner': VehicleSegment.utilitaire,
    },
    'Renault': {
      'Clio': VehicleSegment.citadine,
      'Captur': VehicleSegment.suvCompact,
      'Mégane': VehicleSegment.compacte,
      'Kadjar': VehicleSegment.suvMoyen,
      'Scénic': VehicleSegment.monospace,
      'Talisman': VehicleSegment.berline,
      'Kangoo': VehicleSegment.utilitaire,
    },
    'Seat': {
      'Ibiza': VehicleSegment.citadine,
      'Leon': VehicleSegment.compacte,
      'Arona': VehicleSegment.suvCompact,
      'Ateca': VehicleSegment.suvMoyen,
    },
    'Škoda': {
      'Fabia': VehicleSegment.citadine,
      'Octavia': VehicleSegment.compacte,
      'Kamiq': VehicleSegment.suvCompact,
      'Karoq': VehicleSegment.suvMoyen,
      'Kodiaq': VehicleSegment.suvGrand,
    },
    'Suzuki': {
      'Swift': VehicleSegment.citadine,
      'Vitara': VehicleSegment.suvCompact,
      'S-Cross': VehicleSegment.suvCompact,
      'Jimny': VehicleSegment.suvCompact,
    },
    'Toyota': {
      'Yaris': VehicleSegment.citadine,
      'Corolla': VehicleSegment.compacte,
      'C-HR': VehicleSegment.suvCompact,
      'RAV4': VehicleSegment.suvMoyen,
      'Land Cruiser': VehicleSegment.suvGrand,
      'Hilux': VehicleSegment.pickup,
    },
    'Volkswagen': {
      'Polo': VehicleSegment.citadine,
      'Golf': VehicleSegment.compacte,
      'Passat': VehicleSegment.berline,
      'T-Roc': VehicleSegment.suvCompact,
      'Tiguan': VehicleSegment.suvMoyen,
      'Touareg': VehicleSegment.suvGrand,
      'Caddy': VehicleSegment.utilitaire,
    },
    'Volvo': {
      'XC40': VehicleSegment.suvCompact,
      'XC60': VehicleSegment.suvMoyen,
      'XC90': VehicleSegment.suvGrand,
      'S60': VehicleSegment.berline,
      'V60': VehicleSegment.berline,
    },
  };

  static VehicleSegment? segmentFor(String brand, String? model) {
    if (model == null || model.trim().isEmpty) return null;
    final models = _modelSegments[brand];
    if (models == null) return null;
    final normalized = model.trim().toLowerCase();
    for (final entry in models.entries) {
      if (entry.key.toLowerCase() == normalized) return entry.value;
    }
    return null;
  }

  /// 1.0 (no adjustment) when the model isn't recognised - an unclassified
  /// vehicle must never be silently pushed up or down.
  static double multiplierFor(VehicleSegment? segment) {
    if (segment == null) return 1.0;
    return _multipliers[segment] ?? 1.0;
  }
}
