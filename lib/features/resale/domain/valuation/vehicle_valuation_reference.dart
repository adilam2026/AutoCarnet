/// Internal, isolated reference layer used ONLY as a last-resort fallback
/// when the owner hasn't provided a purchase price to anchor the
/// estimation on (bloc 7). These are rough brand-tier price bands, not a
/// real market catalogue - deliberately kept separate from the engine so
/// this whole file can be swapped for a real pricing API/dataset later
/// without touching ValuationEngine or the UI.
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

  /// Midpoint of the brand's tier band - an approximate, clearly internal
  /// placeholder, only used when no purchase price is available.
  static double estimatedNewPrice(String brand) {
    final tier = tierFor(brand);
    final (min, max) = tierNewPriceRangeMad[tier]!;
    return (min + max) / 2;
  }
}
