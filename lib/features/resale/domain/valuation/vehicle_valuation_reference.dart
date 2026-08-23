import 'sourced_new_price_reference.dart';
import 'vehicle_segment_rules.dart';

/// The base new-price used to anchor every estimation (there is no real
/// purchase price input - the Acquisition section was removed from the
/// vehicle sheet). [sourced] tells the engine whether [priceMad] came from
/// a real, traceable Moroccan catalogue price ([SourcedNewPriceReference])
/// or from the generic brand-tier/segment fallback below - the engine
/// uses this to cap confidence, never claiming "bonne confiance" off an
/// unverified generic guess.
class NewPriceEstimate {
  final double priceMad;
  final bool sourced;
  final String? source;
  const NewPriceEstimate({required this.priceMad, required this.sourced, this.source});
}

/// Internal, isolated reference layer. [SourcedNewPriceReference] is tried
/// first for a real, traceable price; the brand-tier bands below are only
/// a last-resort generic fallback when nothing sourced covers this
/// vehicle - rough bands, not a real market catalogue, deliberately kept
/// separate from the engine so this whole file can be swapped for a real
/// pricing API/dataset later without touching ValuationEngine or the UI.
enum BrandTier { economy, mainstream, premium, luxury }

class VehicleValuationReference {
  const VehicleValuationReference._();

  /// Indicative new-price band per tier, in MAD. Deliberately a range, not
  /// a false-precision point value - the engine uses the midpoint and
  /// lowers confidence when it has to fall back to this table at all.
  static const Map<BrandTier, (double min, double max)> tierNewPriceRangeMad = {
    BrandTier.economy: (110000, 180000),
    BrandTier.mainstream: (180000, 280000),
    BrandTier.premium: (350000, 600000),
    BrandTier.luxury: (600000, 1200000),
  };

  static const Map<String, BrandTier> _brandTiers = {
    // Economy
    'Dacia': BrandTier.economy,
    'Chery': BrandTier.economy,
    'Daewoo': BrandTier.economy,
    'DFSK': BrandTier.economy,
    'Geely': BrandTier.economy,
    'MG': BrandTier.economy,
    'SsangYong': BrandTier.economy,
    'Suzuki': BrandTier.economy,
    'Isuzu': BrandTier.economy,
    'Chevrolet': BrandTier.economy,
    // Mainstream
    'Renault': BrandTier.mainstream,
    'Peugeot': BrandTier.mainstream,
    'Citroën': BrandTier.mainstream,
    'Volkswagen': BrandTier.mainstream,
    'Hyundai': BrandTier.mainstream,
    'Kia': BrandTier.mainstream,
    'Toyota': BrandTier.mainstream,
    'Nissan': BrandTier.mainstream,
    'Honda': BrandTier.mainstream,
    'Mazda': BrandTier.mainstream,
    'Ford': BrandTier.mainstream,
    'Opel': BrandTier.mainstream,
    'Seat': BrandTier.mainstream,
    'Škoda': BrandTier.mainstream,
    'Fiat': BrandTier.mainstream,
    'Mitsubishi': BrandTier.mainstream,
    'Subaru': BrandTier.mainstream,
    'Jeep': BrandTier.mainstream,
    'Smart': BrandTier.mainstream,
    'GMC': BrandTier.mainstream,
    'Dodge': BrandTier.mainstream,
    'BYD': BrandTier.mainstream,
    'Cupra': BrandTier.mainstream,
    // Premium
    'Audi': BrandTier.premium,
    'BMW': BrandTier.premium,
    'Mercedes-Benz': BrandTier.premium,
    'Volvo': BrandTier.premium,
    'Mini': BrandTier.premium,
    'Lexus': BrandTier.premium,
    'Alfa Romeo': BrandTier.premium,
    'DS Automobiles': BrandTier.premium,
    'Tesla': BrandTier.premium,
    // Luxury
    'Porsche': BrandTier.luxury,
    'Land Rover': BrandTier.luxury,
    'Jaguar': BrandTier.luxury,
  };

  static BrandTier tierFor(String brand) => _brandTiers[brand] ?? BrandTier.mainstream;

  /// Midpoint of the brand's tier band, adjusted for the model's body
  /// segment when it's a recognised one (bloc 24-27: a brand tier alone
  /// can't tell a city car from a mid-size SUV of the same brand) - an
  /// approximate, clearly internal placeholder, only used when nothing
  /// sourced covers this vehicle.
  static double _genericEstimate(String brand, String? model) {
    final tier = tierFor(brand);
    final (min, max) = tierNewPriceRangeMad[tier]!;
    final base = (min + max) / 2;
    final segment = VehicleSegmentRules.segmentFor(brand, model);
    return base * VehicleSegmentRules.multiplierFor(segment);
  }

  /// The engine's single entry point for the base new price: a real,
  /// traceable Moroccan catalogue price for this exact brand/model/year
  /// when one is on file, otherwise the generic brand-tier/segment
  /// fallback. Either way the value returned feeds the exact same
  /// depreciation/mileage/condition/motorisation calculation downstream -
  /// the reference table may know real prices per model, but the pricing
  /// algorithm itself never special-cases a specific vehicle.
  static NewPriceEstimate newPriceFor(String brand, String? model, {int? year}) {
    final sourced =
        model == null ? null : SourcedNewPriceReference.lookup(brand, model, year);
    if (sourced != null) {
      return NewPriceEstimate(priceMad: sourced.priceMad, sourced: true, source: sourced.source);
    }
    return NewPriceEstimate(priceMad: _genericEstimate(brand, model), sourced: false);
  }
}
