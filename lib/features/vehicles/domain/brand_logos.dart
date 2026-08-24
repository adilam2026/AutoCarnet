import 'package:flutter/widgets.dart' show IconData;
import 'package:simple_icons/simple_icons.dart';

import 'brand_normalization.dart';

/// Brand -> logo glyph mapping (bloc: identité visuelle). Every glyph comes
/// from `simple_icons` - a locally-bundled, CC0-licensed Flutter port of
/// simpleicons.org - never fetched from the network or hotlinked from a
/// URL found on the web. Deliberately a closed, explicit map rather than a
/// naming-convention guess: a brand not listed here simply has no logo
/// (see [brandLogoFor]), it's never approximated.
///
/// Coverage is partial by construction - simple_icons only ships glyphs for
/// the car brands it curates, so several [carBrands] entries (e.g. Jaguar,
/// Land Rover, Lexus, Mercedes-Benz, Alfa Romeo) have no entry here. That's
/// a real, known limitation of this data source, not an oversight - the
/// generic vehicle icon fallback exists precisely for this case.
const Map<String, IconData> _logosByCanonicalBrand = {
  'Audi': SimpleIcons.audi,
  'BMW': SimpleIcons.bmw,
  'Chevrolet': SimpleIcons.chevrolet,
  'Citroën': SimpleIcons.citroen,
  'Dacia': SimpleIcons.dacia,
  'DS Automobiles': SimpleIcons.dsautomobiles,
  'Fiat': SimpleIcons.fiat,
  'Ford': SimpleIcons.ford,
  'Honda': SimpleIcons.honda,
  'Hyundai': SimpleIcons.hyundai,
  'Jeep': SimpleIcons.jeep,
  'Kia': SimpleIcons.kia,
  'Mazda': SimpleIcons.mazda,
  'MG': SimpleIcons.mg,
  'Mini': SimpleIcons.mini,
  'Mitsubishi': SimpleIcons.mitsubishi,
  'Nissan': SimpleIcons.nissan,
  'Opel': SimpleIcons.opel,
  'Peugeot': SimpleIcons.peugeot,
  'Porsche': SimpleIcons.porsche,
  'Renault': SimpleIcons.renault,
  'Seat': SimpleIcons.seat,
  'Škoda': SimpleIcons.skoda,
  'Smart': SimpleIcons.smart,
  'Subaru': SimpleIcons.subaru,
  'Suzuki': SimpleIcons.suzuki,
  'Tesla': SimpleIcons.tesla,
  'Toyota': SimpleIcons.toyota,
  'Volkswagen': SimpleIcons.volkswagen,
  'Volvo': SimpleIcons.volvo,
};

/// A locally-bundled brand glyph for [brand], or null when none exists -
/// the caller must fall back to a generic vehicle icon in that case, never
/// leave a gap or invent one. [brand] is normalized first (see
/// [normalizeBrand]) so spelling variants (VW, Mercedes, Citroen...) still
/// resolve correctly.
IconData? brandLogoFor(String brand) => _logosByCanonicalBrand[normalizeBrand(brand)];
